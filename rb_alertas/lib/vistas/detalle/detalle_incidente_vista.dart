import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' show Distance, LatLng, LengthUnit;
import 'package:rb_alertas/modelos/modelos.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/servicios/comentario_servicio.dart';
import 'package:rb_alertas/servicios/denuncia_servicio.dart';
import 'package:rb_alertas/servicios/reporte_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/vistas/detalle/widgets/dialogos_detalle.dart';
import 'package:rb_alertas/vistas/detalle/widgets/encabezado_detalle.dart';
import 'package:rb_alertas/vistas/detalle/widgets/seccion_comentarios.dart';
import 'package:rb_alertas/vistas/detalle/widgets/secciones_detalle.dart';
import 'package:rb_alertas/widgets/comentarios.dart';
import 'package:rb_alertas/widgets/denuncia.dart';
import 'package:rb_alertas/widgets/dialogos.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Detalle de un reporte. Devuelve `true` al cerrarse si el reporte cambió
/// (por ejemplo, se marcó como resuelto).
class DetalleIncidenteVista extends StatefulWidget {
  final int idReporte;

  /// Al abrir, baja hasta los comentarios (botón de la tarjeta del mapa, aviso push).
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
  static const _tamanoMaximoFoto = 10 * 1024 * 1024;

  final _reporteServicio = ReporteServicio();
  final _comentarioServicio = ComentarioServicio();
  final _denunciaServicio = DenunciaServicio();
  final _campoComentario = TextEditingController();
  final _focoComentario = FocusNode();
  final _llaveComentarios = GlobalKey();
  bool _yaBajoAComentarios = false;

  DetalleReporte? _detalle;
  String? _error;
  bool _resolviendo = false;
  bool _votando = false;

  /// Se devuelve al cerrar para que el mapa recargue los pines.
  bool _cambio = false;

  /// Distancia desde el usuario, solo si ya dio permiso de ubicación.
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

  void _avisar(String mensaje) => mostrarAviso(context, mensaje);

  // ---------------------------------------------------------------------------
  // Carga

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final detalle = await _reporteServicio.obtenerDetalle(widget.idReporte);
      if (!mounted) return;
      setState(() => _detalle = detalle);
      _bajarAComentarios();
      if (_distanciaMetros == null) _calcularDistancia(detalle);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  /// "A 350 m de ti". No pide permiso: si no lo hay, simplemente no se muestra.
  Future<void> _calcularDistancia(DetalleReporte d) async {
    try {
      final permiso = await Geolocator.checkPermission();
      if (permiso != LocationPermission.always && permiso != LocationPermission.whileInUse) return;
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
      final conversacion = await _comentarioServicio.obtenerComentarios(widget.idReporte);
      if (!mounted) return;
      setState(() => _conversacion = conversacion);
      _bajarAComentarios();
    } catch (e) {
      if (mounted) setState(() => _errorComentarios = mensajeDeError(e));
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
      Scrollable.ensureVisible(contexto, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    });
  }

  // ---------------------------------------------------------------------------
  // Acciones sobre el reporte

  Future<void> _contactarEmergencias(DetalleReporte d) async {
    final entidad = d.emergencia;
    if (entidad == null) {
      _avisar('No hay un número de emergencia asociado a este reporte');
      return;
    }
    if (!await confirmarLlamada(context, entidad)) return;

    final abierta = await launchUrl(Uri(scheme: 'tel', path: entidad.telefono)).catchError((_) => false);
    if (!abierta && mounted) _avisar('Marca al ${entidad.telefono} (${entidad.nombre})');
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
    if (mounted) _avisar('Copiado: pégalo donde quieras compartirlo');
  }

  /// Registra, cambia o retira el voto del usuario sobre este reporte.
  /// Tocar de nuevo el botón ya marcado equivale a retirar el voto.
  Future<void> _votar(DetalleReporte d, TipoVoto voto) async {
    if (!Sesion.activa) {
      _avisar('Inicia sesión para confirmar o desmentir un reporte');
      return;
    }
    setState(() => _votando = true);
    try {
      final resumen = d.miVoto == voto
          ? await _reporteServicio.quitarVoto(d.id)
          : await _reporteServicio.votar(d.id, voto);
      if (!mounted) return;
      // El estado puede haber cambiado a VALIDADO o DESCARTADO por el trigger.
      if (resumen.estado != d.estado) _cambio = true;
      await _cargar();
    } catch (e) {
      if (mounted) _avisar(mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _votando = false);
    }
  }

  Future<void> _marcarResuelto(DetalleReporte d) async {
    if (!Sesion.activa) {
      _avisar('Debes iniciar sesión');
      return;
    }
    if (!await confirmarResuelto(context)) return;

    setState(() => _resolviendo = true);
    try {
      await _reporteServicio.marcarResuelto(d.id);
      _cambio = true;
      if (!mounted) return;
      _avisar('Reporte marcado como resuelto');
      await _cargar();
    } catch (e) {
      if (mounted) _avisar(mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _resolviendo = false);
    }
  }

  /// Denuncia el reporte o, con [comentario], uno de sus comentarios.
  Future<void> _denunciar(DetalleReporte d, {Comentario? comentario}) async {
    if (!Sesion.activa) {
      _avisar('Inicia sesión para denunciar');
      return;
    }
    final denuncia = await pedirDenuncia(context, esComentario: comentario != null);
    if (denuncia == null) return;
    final (motivo, detalle) = denuncia;
    try {
      if (comentario == null) {
        await _denunciaServicio.denunciarReporte(idReporte: d.id, motivo: motivo, detalle: detalle);
        if (mounted) _avisar('Gracias, revisaremos este reporte');
      } else {
        final oculto = await _denunciaServicio.denunciarComentario(
          idReporte: d.id,
          idComentario: comentario.id,
          motivo: motivo,
          detalle: detalle,
        );
        if (!mounted) return;
        _avisar(
          oculto
              ? 'Gracias. El comentario quedó oculto mientras lo revisamos'
              : 'Gracias, revisaremos este comentario',
        );
        if (oculto) await _cargarComentarios();
      }
    } catch (e) {
      if (mounted) _avisar(mensajeDeError(e));
    }
  }

  // ---------------------------------------------------------------------------
  // Comentarios

  /// La barra para escribir solo aparece con sesión y mientras el reporte esté vigente.
  bool _puedeComentar(DetalleReporte d) =>
      Sesion.activa && !Sesion.esAdmin && (_conversacion?.puedeComentar ?? d.activo);

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
      if (mounted) _avisar('No se pudo abrir la cámara o la galería');
      return;
    }
    if (archivo == null) return;
    if (await archivo.length() > _tamanoMaximoFoto) {
      if (mounted) _avisar('La foto no puede superar los 10 MB');
      return;
    }
    final bytes = await archivo.readAsBytes();
    if (!mounted) return;
    setState(() => _fotoComentario = Evidencia(nombreArchivo: archivo!.name, bytes: bytes));
  }

  Future<void> _publicarComentario(DetalleReporte d) async {
    if (!Sesion.activa) {
      _avisar('Inicia sesión para comentar');
      return;
    }
    final texto = _campoComentario.text.trim();
    if (texto.isEmpty && _fotoComentario == null) {
      _avisar('Escribe un comentario o adjunta una foto');
      return;
    }

    setState(() => _publicando = true);
    try {
      await _comentarioServicio.comentar(
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
    } catch (e) {
      if (mounted) _avisar(mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  Future<void> _eliminarComentario(DetalleReporte d, Comentario c) async {
    if (!Sesion.activa) return;
    final eliminar = await confirmar(
      context,
      titulo: 'Eliminar comentario',
      mensaje: 'Tu comentario dejará de verse en este reporte. ¿Quieres eliminarlo?',
      accion: 'Eliminar',
    );
    if (!eliminar) return;

    try {
      await _comentarioServicio.eliminar(idReporte: d.id, idComentario: c.id);
      if (!mounted) return;
      // Si se estaba respondiendo a ese comentario, ya no se puede.
      if (_respondiendoA?.id == c.id) setState(() => _respondiendoA = null);
      _avisar('Comentario eliminado');
      await _cargarComentarios();
    } catch (e) {
      if (mounted) _avisar(mensajeDeError(e));
    }
  }

  // ---------------------------------------------------------------------------
  // Interfaz

  @override
  Widget build(BuildContext context) {
    final detalle = _detalle;
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
            Expanded(child: detalle == null ? _cargando() : _cuerpo(detalle)),
            if (detalle != null && _puedeComentar(detalle)) _barraComentario(detalle),
          ],
        ),
      ),
    );
  }

  Widget _botonVolver() => BotonCircular(
    icono: Icons.arrow_back_rounded,
    tooltip: 'Volver',
    onTap: () => Navigator.pop(context, _cambio),
  );

  /// Mientras carga, o con el error y "Reintentar".
  Widget _cargando() {
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
        SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: _botonVolver())),
      ],
    );
  }

  Widget _cuerpo(DetalleReporte detalle) {
    // El mapa ocupa cerca de un tercio de la pantalla, sin pasar de 300.
    final altoMapa = context.altoRelativo(0.34, minimo: 190, maximo: 300);
    final margen = context.pantallaAngosta ? 18.0 : 24.0;

    return Stack(
      children: [
        SingleChildScrollView(
          child: Stack(
            children: [
              SizedBox(height: altoMapa, child: MapaDetalle(detalle: detalle)),
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
                _botonVolver(),
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

  Widget _contenido(DetalleReporte d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EncabezadoDetalle(detalle: d, distanciaMetros: _distanciaMetros),
        const SizedBox(height: 20),
        AutorDetalle(
          detalle: d,
          onDenunciar: !d.esAutor && !Sesion.esAdmin ? () => _denunciar(d) : null,
        ),
        const SizedBox(height: 18),
        Text(d.descripcion, style: const TextStyle(fontSize: 17, height: 1.5, color: RBColores.tinta)),
        if (d.imagenes.isNotEmpty) ...[
          const SizedBox(height: 20),
          MediaDetalle(url: d.imagenes.first),
        ],
        if (d.esIncidenteAgrupado) ...[
          const SizedBox(height: 22),
          MismoIncidente(
            detalle: d,
            onAbrir: (id) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DetalleIncidenteVista(idReporte: id)),
            ),
          ),
        ],
        const SizedBox(height: 22),
        const Divider(height: 1),
        const SizedBox(height: 16),
        VotosDetalle(detalle: d, votando: _votando, onVotar: (voto) => _votar(d, voto)),
        const SizedBox(height: 16),
        const Divider(height: 1),
        if (d.esAutor || d.estado == 'RESUELTO') ...[
          const SizedBox(height: 22),
          BotonResuelto(detalle: d, resolviendo: _resolviendo, onResolver: () => _marcarResuelto(d)),
        ],
        const SizedBox(height: 26),
        SeccionComentarios(
          key: _llaveComentarios,
          conversacion: _conversacion,
          error: _errorComentarios,
          onReintentar: _cargarComentarios,
          puedeResponder: _puedeComentar(d),
          publicando: _publicando,
          onResponder: _responder,
          onEliminar: (c) => _eliminarComentario(d, c),
          onDenunciar: (c) => _denunciar(d, comentario: c),
        ),
      ],
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
