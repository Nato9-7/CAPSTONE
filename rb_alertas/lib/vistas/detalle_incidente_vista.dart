import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' show Distance, LatLng, LengthUnit;
import 'package:rb_alertas/config/api_config.dart';
import 'package:rb_alertas/servicios/comentario_servicio.dart';
import 'package:rb_alertas/servicios/reporte_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/boton_voto.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';
import 'package:rb_alertas/widgets/comentarios.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Detalle de un reporte. Devuelve `true` al cerrarse si el reporte cambió
/// (por ejemplo, se marcó como resuelto).
class DetalleIncidenteVista extends StatefulWidget {
  final int idReporte;
  // Al abrir, baja hasta los comentarios (botón de la tarjeta del mapa, aviso push).
  final bool irAComentarios;

  const DetalleIncidenteVista({
    super.key,
    required this.idReporte,
    this.irAComentarios = false,
  });

  @override
  State<DetalleIncidenteVista> createState() => _DetalleIncidenteVistaState();
}

class _DetalleIncidenteVistaState extends State<DetalleIncidenteVista> {
  final _reporteServicio = ReporteServicio();
  final _comentarioServicio = ComentarioServicio();
  final _campoComentario = TextEditingController();
  final _focoComentario = FocusNode();
  final _llaveComentarios = GlobalKey();
  bool _yaBajoAComentarios = false;

  static const _tamanoMaximoFoto = 10 * 1024 * 1024;

  DetalleReporte? _detalle;
  String? _error;
  bool _resolviendo = false;
  bool _votando = false;
  bool _cambio = false;
  // Distancia desde el usuario, solo si ya dio permiso de ubicación.
  double? _distanciaMetros;

  // Conversación del reporte. Se carga aparte: si falla, el detalle se ve igual.
  ConversacionReporte? _conversacion;
  String? _errorComentarios;
  Comentario? _respondiendoA;
  Evidencia? _fotoComentario;
  bool _publicando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarComentarios();
  }

  @override
  void dispose() {
    _campoComentario.dispose();
    _focoComentario.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final detalle = await _reporteServicio.obtenerDetalle(
        widget.idReporte,
        token: Sesion.token,
      );
      if (!mounted) return;
      setState(() => _detalle = detalle);
      _bajarAComentarios();
      if (_distanciaMetros == null) _calcularDistancia(detalle);
    } on ReporteServicioException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo conectar con el servidor');
    }
  }

  /// "A 350 m de ti". No pide permiso: si no lo hay, simplemente no se muestra.
  Future<void> _calcularDistancia(DetalleReporte d) async {
    try {
      final permiso = await Geolocator.checkPermission();
      if (permiso != LocationPermission.always &&
          permiso != LocationPermission.whileInUse) {
        return;
      }
      final posicion = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(timeLimit: Duration(seconds: 8)),
          );
      final metros = const Distance().as(
        LengthUnit.Meter,
        LatLng(posicion.latitude, posicion.longitude),
        LatLng(d.latitud, d.longitud),
      );
      if (mounted) setState(() => _distanciaMetros = metros);
    } catch (_) {
      // Sin ubicación se omite la distancia.
    }
  }

  Future<void> _cargarComentarios() async {
    setState(() => _errorComentarios = null);
    try {
      final conversacion = await _comentarioServicio.obtenerComentarios(
        widget.idReporte,
        token: Sesion.token,
      );
      if (!mounted) return;
      setState(() => _conversacion = conversacion);
      _bajarAComentarios();
    } on ComentarioServicioException catch (e) {
      if (mounted) setState(() => _errorComentarios = e.mensaje);
    } catch (_) {
      if (mounted) setState(() => _errorComentarios = 'No se pudo conectar con el servidor');
    }
  }

  /// Con [DetalleIncidenteVista.irAComentarios], baja una sola vez hasta la
  /// conversación, cuando ya cargaron el reporte y sus comentarios.
  void _bajarAComentarios() {
    if (!widget.irAComentarios || _yaBajoAComentarios) return;
    if (_detalle == null || _conversacion == null) return;
    _yaBajoAComentarios = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final contexto = _llaveComentarios.currentContext;
      if (contexto == null) return;
      Scrollable.ensureVisible(
        contexto,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  bool _esVideo(String url) {
    final u = url.toLowerCase();
    return u.endsWith('.mp4') || u.endsWith('.mov') || u.endsWith('.webm');
  }

  // ---------------------------------------------------------------------------
  // Acciones

  Future<void> _contactarEmergencias(DetalleReporte d) async {
    final entidad = d.emergencia;
    if (entidad == null) {
      _mostrarMensaje('No hay un número de emergencia asociado a este reporte');
      return;
    }
    final llamar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contactar emergencias'),
        content: Text('¿Llamar a ${entidad.nombre} al ${entidad.telefono}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: RBColores.rojo),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.call_rounded, size: 18),
            label: const Text('Llamar'),
          ),
        ],
      ),
    );
    if (llamar != true) return;

    final abierta = await launchUrl(Uri(scheme: 'tel', path: entidad.telefono))
        .catchError((_) => false);
    if (!abierta && mounted) {
      _mostrarMensaje('Marca al ${entidad.telefono} (${entidad.nombre})');
    }
  }

  Future<void> _compartir(DetalleReporte d) async {
    final titulo = tituloReporte(d.categoria, d.direccion);
    final lat = d.latitud.toStringAsFixed(5);
    final lon = d.longitud.toStringAsFixed(5);
    final texto = '🚨 $titulo\n'
        '${d.descripcion}\n'
        '${d.direccion != null ? '📍 ${d.direccion}\n' : ''}'
        'https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=17/$lat/$lon\n'
        '— Reportado en RB Alertas';
    // En web, share_plus abre el programa de correo cuando el navegador no
    // tiene hoja para compartir (casi todos los de escritorio): se copia el texto.
    if (!kIsWeb) {
      try {
        await SharePlus.instance.share(ShareParams(text: texto, subject: titulo));
        return;
      } catch (_) {
        // si falla, se copia al portapapeles
      }
    }
    await Clipboard.setData(ClipboardData(text: texto));
    if (mounted) _mostrarMensaje('Copiado: pégalo donde quieras compartirlo');
  }

  /// Registra, cambia o retira el voto del usuario sobre este reporte.
  /// Tocar de nuevo el botón ya marcado equivale a retirar el voto.
  Future<void> _votar(DetalleReporte d, TipoVoto voto) async {
    final token = Sesion.token;
    if (token == null || token.isEmpty) {
      _mostrarMensaje('Inicia sesión para confirmar o desmentir un reporte');
      return;
    }

    setState(() => _votando = true);
    try {
      final resumen = d.miVoto == voto
          ? await _reporteServicio.quitarVoto(d.id, token)
          : await _reporteServicio.votar(d.id, token, voto);
      if (!mounted) return;
      // El estado puede haber cambiado a VALIDADO o DESCARTADO por el trigger.
      if (resumen.estado != d.estado) _cambio = true;
      await _cargar();
    } on ReporteServicioException catch (e) {
      if (mounted) _mostrarMensaje(e.mensaje);
    } catch (_) {
      if (mounted) _mostrarMensaje('No se pudo conectar con el servidor');
    } finally {
      if (mounted) setState(() => _votando = false);
    }
  }

  Future<void> _marcarResuelto(DetalleReporte d) async {
    final token = Sesion.token;
    if (token == null || token.isEmpty) {
      _mostrarMensaje('Debes iniciar sesión');
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marcar como resuelto'),
        content: const Text(
          'El reporte dejará de mostrarse en el mapa. ¿Confirmas que el incidente está resuelto?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: RBColores.verde),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí, está resuelto'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _resolviendo = true);
    try {
      await _reporteServicio.marcarResuelto(d.id, token);
      _cambio = true;
      if (!mounted) return;
      _mostrarMensaje('Reporte marcado como resuelto');
      await _cargar();
    } on ReporteServicioException catch (e) {
      if (mounted) _mostrarMensaje(e.mensaje);
    } catch (_) {
      if (mounted) _mostrarMensaje('No se pudo conectar con el servidor');
    } finally {
      if (mounted) setState(() => _resolviendo = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Comentarios

  bool get _haySesion => Sesion.token != null && Sesion.token!.isNotEmpty;

  /// La barra para escribir solo aparece con sesión y mientras el reporte esté vigente.
  bool _puedeComentar(DetalleReporte d) =>
      _haySesion && !Sesion.esAdmin && (_conversacion?.puedeComentar ?? d.activo);

  void _responder(Comentario c) {
    setState(() => _respondiendoA = c);
    _focoComentario.requestFocus();
  }

  Future<void> _seleccionarFoto({required bool camara}) async {
    final XFile? archivo;
    try {
      archivo = await ImagePicker().pickImage(
        source: camara ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1920,
        imageQuality: 85,
      );
    } catch (_) {
      if (mounted) _mostrarMensaje('No se pudo abrir la cámara o la galería');
      return;
    }
    if (archivo == null) return;
    if (await archivo.length() > _tamanoMaximoFoto) {
      if (mounted) _mostrarMensaje('La foto no puede superar los 10 MB');
      return;
    }
    final bytes = await archivo.readAsBytes();
    if (!mounted) return;
    setState(() => _fotoComentario = Evidencia(nombreArchivo: archivo!.name, bytes: bytes));
  }

  Future<void> _publicarComentario(DetalleReporte d) async {
    final token = Sesion.token;
    if (token == null || token.isEmpty) {
      _mostrarMensaje('Inicia sesión para comentar');
      return;
    }
    final texto = _campoComentario.text.trim();
    if (texto.isEmpty && _fotoComentario == null) {
      _mostrarMensaje('Escribe un comentario o adjunta una foto');
      return;
    }

    setState(() => _publicando = true);
    try {
      await _comentarioServicio.comentar(
        token: token,
        idReporte: d.id,
        contenido: texto,
        idPadre: _respondiendoA?.id,
        foto: _fotoComentario,
      );
      if (!mounted) return;
      _campoComentario.clear();
      _focoComentario.unfocus();
      setState(() {
        _respondiendoA = null;
        _fotoComentario = null;
      });
      await _cargarComentarios();
    } on ComentarioServicioException catch (e) {
      if (mounted) _mostrarMensaje(e.mensaje);
    } catch (_) {
      if (mounted) _mostrarMensaje('No se pudo conectar con el servidor');
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  Future<void> _eliminarComentario(DetalleReporte d, Comentario c) async {
    final token = Sesion.token;
    if (token == null || token.isEmpty) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar comentario'),
        content: const Text('Tu comentario dejará de verse en este reporte. ¿Quieres eliminarlo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: RBColores.rojo),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _comentarioServicio.eliminar(token: token, idReporte: d.id, idComentario: c.id);
      if (!mounted) return;
      // Si se estaba respondiendo a ese comentario, ya no se puede.
      if (_respondiendoA?.id == c.id) setState(() => _respondiendoA = null);
      _mostrarMensaje('Comentario eliminado');
      await _cargarComentarios();
    } on ComentarioServicioException catch (e) {
      if (mounted) _mostrarMensaje(e.mensaje);
    } catch (_) {
      if (mounted) _mostrarMensaje('No se pudo conectar con el servidor');
    }
  }

  // ---------------------------------------------------------------------------
  // Interfaz

  @override
  Widget build(BuildContext context) {
    // Al volver al mapa se avisa si el reporte cambió, para recargar los pines.
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _cambio);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        // La barra va en el body y no en bottomNavigationBar: solo el body se
        // achica al abrir el teclado, así la barra sube y queda a la vista.
        body: Column(
          children: [
            Expanded(child: _cuerpo()),
            if (_detalle != null && _puedeComentar(_detalle!)) _barraComentario(_detalle!),
          ],
        ),
      ),
    );
  }

  Widget _cuerpo() {
    final detalle = _detalle;
    if (detalle == null) {
      return Stack(
        children: [
          Center(
            child: _error == null
                ? const CircularProgressIndicator()
                : EstadoVacio(
                    icono: Icons.cloud_off_rounded,
                    titulo: 'No se pudo cargar el reporte',
                    detalle: _error!,
                    accion: 'Reintentar',
                    onAccion: _cargar,
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: BotonCircular(
                icono: Icons.arrow_back_rounded,
                tooltip: 'Volver',
                onTap: () => Navigator.pop(context, _cambio),
              ),
            ),
          ),
        ],
      );
    }

    // El mapa ocupa cerca de un tercio de la pantalla, sin pasar de 300.
    final altoMapa = context.altoRelativo(0.34, minimo: 190, maximo: 300);
    final margen = context.pantallaAngosta ? 18.0 : 24.0;

    return Stack(
      children: [
        SingleChildScrollView(
          child: Stack(
            children: [
              SizedBox(height: altoMapa, child: _mapa(detalle)),
              Container(
                margin: EdgeInsets.only(top: altoMapa - 28),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(RBRadios.hoja)),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        margen,
                        24,
                        margen,
                        // Con la barra de comentarios abajo, ella ya respeta el borde inferior.
                        28 + (_puedeComentar(detalle) ? 0 : MediaQuery.of(context).padding.bottom),
                      ),
                      child: _contenido(detalle),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                BotonCircular(
                  icono: Icons.arrow_back_rounded,
                  tooltip: 'Volver',
                  onTap: () => Navigator.pop(context, _cambio),
                ),
                const Spacer(),
                BotonCircular(
                  icono: Icons.call_rounded,
                  fondo: RBColores.rojo,
                  color: Colors.white,
                  tooltip: 'Contactar emergencias',
                  onTap: () => _contactarEmergencias(detalle),
                ),
                const SizedBox(width: 12),
                BotonCircular(
                  icono: Icons.share_outlined,
                  tooltip: 'Compartir',
                  onTap: () => _compartir(detalle),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _mapa(DetalleReporte d) {
    final punto = LatLng(d.latitud, d.longitud);
    return FlutterMap(
      options: MapOptions(
        initialCenter: punto,
        initialZoom: 16.5,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
      ),
      children: [
        capaMapaBase(),
        MarkerLayer(
          markers: [
            Marker(
              point: punto,
              width: 90,
              height: 90,
              child: PinIncidente(
                codigo: d.categoriaCodigo,
                colorHex: d.colorHex,
                seleccionado: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _contenido(DetalleReporte d) {
    final color = colorCategoria(d.categoriaCodigo, colorHex: d.colorHex);
    final estado = EstadoVisual.desdeApi(d.estado);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(iconoCategoria(d.categoriaCodigo), size: 17, color: color),
                  const SizedBox(width: 6),
                  Text(
                    nombreCortoCategoria(d.categoriaCodigo, d.categoria),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color),
                  ),
                ],
              ),
            ),
            ChipEstado(
              estado: estado,
              grande: true,
              texto: estado == EstadoVisual.validada ? 'Validada por vecinos' : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          tituloReporte(d.categoria, d.direccion),
          style: TextStyle(
            fontFamily: RBFuentes.titulos,
            fontSize: context.escala(30),
            height: 1.15,
            fontWeight: FontWeight.w800,
            color: RBColores.azul,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 18,
          runSpacing: 6,
          children: [
            if (d.fechaCreacion != null)
              _meta(Icons.schedule_rounded, tiempoRelativoInicio(d.fechaCreacion)),
            if (_distanciaMetros != null)
              _meta(Icons.place_outlined, 'A ${distanciaLegible(_distanciaMetros!)} de ti'),
          ],
        ),
        if (d.direccion != null && d.direccion!.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          _meta(Icons.signpost_outlined, d.direccion!),
        ],
        const SizedBox(height: 20),
        _autor(d),
        const SizedBox(height: 18),
        Text(
          d.descripcion,
          style: const TextStyle(fontSize: 17, height: 1.5, color: RBColores.tinta),
        ),
        if (d.imagenes.isNotEmpty) ...[
          const SizedBox(height: 20),
          _media(d),
        ],
        const SizedBox(height: 22),
        const Divider(height: 1),
        const SizedBox(height: 16),
        _votos(d),
        const SizedBox(height: 16),
        const Divider(height: 1),
        if (d.esAutor || d.estado == 'RESUELTO') ...[
          const SizedBox(height: 22),
          _botonResuelto(d),
        ],
        const SizedBox(height: 26),
        _comentarios(d),
      ],
    );
  }

  Widget _meta(IconData icono, String texto) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 18, color: RBColores.texto2),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            texto,
            style: const TextStyle(fontSize: 15.5, color: RBColores.texto2),
          ),
        ),
      ],
    );
  }

  Widget _autor(DetalleReporte d) {
    // El autor aparece con un alias de suricata (lo arma la API):
    // su nombre real no se muestra por seguridad.
    return Row(
      children: [
        const AvatarSuricata(tamano: 54),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                d.autor,
                style: const TextStyle(
                  fontSize: 17.5,
                  fontWeight: FontWeight.w700,
                  color: RBColores.tinta,
                ),
              ),
              Text(
                d.esAutor
                    ? 'Tú reportaste este incidente · perfil anónimo'
                    : 'Autor del reporte · perfil anónimo',
                style: const TextStyle(fontSize: 14, color: RBColores.texto2),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _media(DetalleReporte d) {
    final url = d.imagenes.first;
    final radio = BorderRadius.circular(RBRadios.tarjeta);

    if (_esVideo(url)) {
      return Material(
        color: RBColores.azul50,
        borderRadius: radio,
        child: InkWell(
          borderRadius: radio,
          onTap: () => launchUrl(Uri.parse(ApiConfig.urlArchivo(url))),
          child: const SizedBox(
            height: 180,
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_circle_outline_rounded, size: 54, color: RBColores.azul),
                SizedBox(height: 6),
                Text(
                  'Ver video adjunto',
                  style: TextStyle(fontWeight: FontWeight.w700, color: RBColores.azul),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: radio,
      child: Image.network(
        ApiConfig.urlArchivo(url),
        width: double.infinity,
        height: 220,
        fit: BoxFit.cover,
        loadingBuilder: (context, hijo, progreso) => progreso == null
            ? hijo
            : Container(
                height: 220,
                color: RBColores.azul50,
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
        errorBuilder: (context, error, pila) => Container(
          height: 160,
          color: RBColores.azul50,
          child: const Center(
            child: Icon(Icons.broken_image_outlined, size: 40, color: RBColores.texto2),
          ),
        ),
      ),
    );
  }

  /// Confirmar o desmentir (CU-16). El autor no vota su propio reporte: ve
  /// solo el recuento.
  Widget _votos(DetalleReporte d) {
    final puedeVotar = d.esAutor == false && d.activo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '¿Es confiable este reporte?',
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w600,
                  color: RBColores.tinta,
                ),
              ),
            ),
            BotonVoto(
              icono: Icons.thumb_up_outlined,
              iconoActivo: Icons.thumb_up_rounded,
              cantidad: d.confirmaciones,
              marcado: d.miVoto == TipoVoto.confirma,
              positivo: true,
              onTap: puedeVotar && !_votando ? () => _votar(d, TipoVoto.confirma) : null,
            ),
            const SizedBox(width: 10),
            BotonVoto(
              icono: Icons.thumb_down_outlined,
              iconoActivo: Icons.thumb_down_rounded,
              cantidad: d.desmentidos,
              marcado: d.miVoto == TipoVoto.desmiente,
              positivo: false,
              onTap: puedeVotar && !_votando ? () => _votar(d, TipoVoto.desmiente) : null,
            ),
          ],
        ),
        if (!puedeVotar) ...[
          const SizedBox(height: 6),
          Text(
            d.esAutor
                ? 'Así responde la comunidad a tu reporte.'
                : 'Este reporte ya no admite votos.',
            style: const TextStyle(fontSize: 13.5, color: RBColores.texto2),
          ),
        ],
      ],
    );
  }

  Widget _botonResuelto(DetalleReporte d) {
    final resuelto = !d.activo;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton.icon(
        // Solo el autor puede marcarlo; si ya no está vigente se muestra deshabilitado.
        onPressed: resuelto || _resolviendo ? null : () => _marcarResuelto(d),
        style: OutlinedButton.styleFrom(
          foregroundColor: RBColores.verde,
          disabledForegroundColor: RBColores.verde.withValues(alpha: 0.75),
          backgroundColor: RBColores.verde50,
          disabledBackgroundColor: RBColores.verde50,
          side: BorderSide(color: RBColores.verde.withValues(alpha: resuelto ? 0.35 : 0.7), width: 1.4),
        ),
        icon: _resolviendo
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: RBColores.verde),
              )
            : const Icon(Icons.check_circle_outline_rounded, size: 22),
        label: Text(
          d.estado == 'RESUELTO'
              ? 'Incidente resuelto'
              : resuelto
                  ? 'Este reporte ya no está vigente'
                  : 'Marcar como resuelto',
        ),
      ),
    );
  }

  Widget _comentarios(DetalleReporte d) {
    final conversacion = _conversacion;
    final puedeResponder = _puedeComentar(d);

    final Widget contenido;
    if (conversacion == null) {
      contenido = _errorComentarios == null
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_errorComentarios!, style: const TextStyle(fontSize: 15, color: RBColores.texto2)),
                TextButton(onPressed: _cargarComentarios, child: const Text('Reintentar')),
              ],
            );
    } else if (conversacion.comentarios.isEmpty) {
      contenido = Text(
        puedeResponder
            ? 'Aún no hay comentarios. Si sabes algo más del incidente, cuéntale a tus vecinos.'
            : 'Aún no hay comentarios.',
        style: const TextStyle(fontSize: 15, height: 1.4, color: RBColores.texto2),
      );
    } else {
      contenido = Column(
        children: [
          for (final c in conversacion.comentarios) ...[
            _tarjetaComentario(d, c, puedeResponder),
            for (final r in c.respuestas)
              Padding(
                // Bajo el avatar del comentario raíz; menos sangría en pantallas angostas.
                padding: EdgeInsets.only(left: context.pantallaAngosta ? 30 : 48, top: 10),
                child: _tarjetaComentario(d, r, puedeResponder, respuesta: true),
              ),
            const SizedBox(height: 16),
          ],
        ],
      );
    }

    // Por qué no aparece la barra para escribir.
    final aviso = conversacion == null || puedeResponder || Sesion.esAdmin
        ? null
        : !conversacion.puedeComentar
            ? 'Este reporte ya no está vigente: la conversación quedó cerrada.'
            : 'Inicia sesión para comentar.';

    return Column(
      key: _llaveComentarios,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.chat_bubble_outline_rounded, size: 24, color: RBColores.azul),
            const SizedBox(width: 10),
            Text(
              'Comentarios',
              style: TextStyle(
                fontFamily: RBFuentes.titulos,
                fontSize: context.escala(24),
                fontWeight: FontWeight.w800,
                color: RBColores.azul,
              ),
            ),
            if (conversacion != null && conversacion.total > 0) ...[
              const SizedBox(width: 8),
              Text(
                '${conversacion.total}',
                style: const TextStyle(fontSize: 16, color: RBColores.texto2),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        contenido,
        if (aviso != null) ...[
          const SizedBox(height: 4),
          Text(aviso, style: const TextStyle(fontSize: 13.5, color: RBColores.texto2)),
        ],
      ],
    );
  }

  Widget _tarjetaComentario(
    DetalleReporte d,
    Comentario c,
    bool puedeResponder, {
    bool respuesta = false,
  }) {
    return TarjetaComentario(
      comentario: c,
      respuesta: respuesta,
      onResponder: puedeResponder && c.publicado && !_publicando ? () => _responder(c) : null,
      onEliminar: c.esMio ? () => _eliminarComentario(d, c) : null,
      onVerFoto: (url) => verFotoComentario(context, url),
    );
  }

  Widget _barraComentario(DetalleReporte d) {
    return BarraComentario(
      controlador: _campoComentario,
      foco: _focoComentario,
      respondiendoA: _respondiendoA?.autor,
      foto: _fotoComentario?.bytes,
      enviando: _publicando,
      onCamara: () => _seleccionarFoto(camara: true),
      onGaleria: () => _seleccionarFoto(camara: false),
      onEnviar: () => _publicarComentario(d),
      onCancelarRespuesta: () => setState(() => _respondiendoA = null),
      onQuitarFoto: () => setState(() => _fotoComentario = null),
    );
  }
}
