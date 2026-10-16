import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:rb_alertas/servicios/reporte_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/servicios/ubicacion_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Formulario para reportar un incidente. Se abre desde el botón "Reportar"
/// del mapa y, al enviarse, devuelve el punto reportado para centrar el mapa.
class ReportarIncidenteVista extends StatefulWidget {
  const ReportarIncidenteVista({super.key});

  @override
  State<ReportarIncidenteVista> createState() => _ReportarIncidenteVistaState();
}

class _ReportarIncidenteVistaState extends State<ReportarIncidenteVista> {
  // Centro de Puerto Montt, usado mientras no haya ubicación real.
  static const _ubicacionPorDefecto = LatLng(-41.4693, -72.9424);
  static const _tamanoMaximoEvidencia = 20 * 1024 * 1024;
  static const _maximoDescripcion = 500;

  final _formKey = GlobalKey<FormState>();
  final _descripcionController = TextEditingController();
  final _mapController = MapController();
  final _reporteServicio = ReporteServicio();
  final _ubicacionServicio = UbicacionServicio();

  List<CategoriaIncidente>? _categorias;
  String? _errorCategorias;
  int? _idCategoria;

  Evidencia? _evidencia;
  bool _evidenciaEsVideo = false;

  LatLng _ubicacion = _ubicacionPorDefecto;
  // Solo se puede enviar con una ubicación real (GPS o marcada en el mapa),
  // no con el centro de la ciudad que se muestra por defecto.
  bool _ubicacionConfirmada = false;
  // true si el punto vino del GPS; false si el usuario lo marcó a mano.
  bool _ubicacionPorGps = false;
  String? _direccion;
  bool _buscandoUbicacion = false;
  bool _mapaListo = false;
  // Aumenta cada vez que cambia la ubicación elegida; sirve para descartar un
  // GPS que responde tarde, después de que el usuario ya marcó otro punto.
  int _versionUbicacion = 0;

  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _cargarCategorias();
    _detectarUbicacion();
  }

  @override
  void dispose() {
    _descripcionController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _cargarCategorias() async {
    setState(() {
      _categorias = null;
      _errorCategorias = null;
    });

    try {
      final categorias = await _reporteServicio.obtenerCategorias();
      if (!mounted) return;
      setState(() {
        _categorias = categorias;
        _idCategoria ??= categorias.isNotEmpty ? categorias.first.id : null;
      });
    } on ReporteServicioException catch (e) {
      if (!mounted) return;
      setState(() => _errorCategorias = e.mensaje);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorCategorias = 'No se pudo conectar con el servidor');
    }
  }

  Future<void> _detectarUbicacion() async {
    setState(() => _buscandoUbicacion = true);
    final version = _versionUbicacion;

    try {
      final punto = await _ubicacionServicio.obtenerUbicacionActual();
      if (!mounted || _versionUbicacion != version) return;
      _moverUbicacion(punto, porGps: true);
    } on UbicacionServicioException catch (e) {
      if (!mounted) return;
      _mostrarMensaje(e.mensaje.replaceAll('toca el mapa', 'usa «Ajustar»'));
    } catch (_) {
      if (!mounted) return;
      _mostrarMensaje('No pudimos detectar tu ubicación: usa «Ajustar» para marcar el lugar');
    } finally {
      if (mounted) setState(() => _buscandoUbicacion = false);
    }
  }

  Future<void> _moverUbicacion(LatLng punto, {bool porGps = false}) async {
    setState(() {
      _versionUbicacion++;
      _ubicacion = punto;
      _ubicacionConfirmada = true;
      _ubicacionPorGps = porGps;
      _direccion = null;
    });
    if (_mapaListo) {
      _mapController.move(punto, _mapController.camera.zoom);
    }

    final direccion = await _ubicacionServicio.obtenerDireccion(punto);
    // Si el usuario ya marcó otro punto, esta respuesta llegó tarde.
    if (!mounted || _ubicacion != punto) return;
    setState(() {
      _direccion =
          direccion ??
          '${punto.latitude.toStringAsFixed(5)}, ${punto.longitude.toStringAsFixed(5)}';
    });
  }

  /// Abre un mapa grande para mover el pin hasta el lugar exacto.
  Future<void> _ajustarUbicacion() async {
    final punto = await showModalBottomSheet<LatLng>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AjustarUbicacion(inicial: _ubicacion, ubicacionServicio: _ubicacionServicio),
    );
    if (punto != null && mounted) _moverUbicacion(punto);
  }

  Future<void> _seleccionarEvidencia({required bool camara}) async {
    final selector = ImagePicker();
    final XFile? archivo;
    try {
      archivo = camara
          ? await selector.pickImage(source: ImageSource.camera, maxWidth: 1920, imageQuality: 85)
          : await selector.pickMedia(maxWidth: 1920, imageQuality: 85);
    } catch (_) {
      if (mounted) _mostrarMensaje('No se pudo abrir la cámara o la galería');
      return;
    }
    if (archivo == null) return;

    // Se revisa el tamaño antes de leerlo: un video largo puede pesar cientos
    // de MB y cargarlo completo en memoria solo para rechazarlo congela la app.
    if (await archivo.length() > _tamanoMaximoEvidencia) {
      if (mounted) _mostrarMensaje('La evidencia no puede superar los 20 MB');
      return;
    }
    final bytes = await archivo.readAsBytes();
    if (!mounted) return;

    final nombre = archivo.name.toLowerCase();
    final esVideo =
        (archivo.mimeType ?? '').startsWith('video/') ||
        nombre.endsWith('.mp4') ||
        nombre.endsWith('.mov') ||
        nombre.endsWith('.webm');
    final evidencia = Evidencia(nombreArchivo: archivo.name, bytes: bytes);
    setState(() {
      _evidencia = evidencia;
      _evidenciaEsVideo = esVideo;
    });
  }

  Future<void> _enviarReporte() async {
    final token = Sesion.token;
    if (token == null || token.isEmpty) {
      _mostrarMensaje('Debes iniciar sesión para enviar un reporte');
      return;
    }
    if (_idCategoria == null) {
      _mostrarMensaje('Selecciona una categoría');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (!_ubicacionConfirmada) {
      _mostrarMensaje('Usa «Ajustar» para marcar dónde ocurrió el incidente');
      return;
    }

    setState(() => _enviando = true);

    try {
      await _reporteServicio.enviarReporte(
        token: token,
        idCategoria: _idCategoria!,
        descripcion: _descripcionController.text.trim(),
        latitud: _ubicacion.latitude,
        longitud: _ubicacion.longitude,
        direccion: _direccion,
        evidencia: _evidencia,
      );

      if (!mounted) return;
      _mostrarMensaje('Reporte enviado. ¡Gracias por alertar a tu comunidad!');
      Navigator.pop(context, _ubicacion);
    } on ReporteServicioException catch (e) {
      if (!mounted) return;
      _mostrarMensaje(e.mensaje);
    } catch (_) {
      if (!mounted) return;
      _mostrarMensaje('No se pudo conectar con el servidor');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mientras se envía no se puede salir: el resultado se perdería.
    return PopScope(canPop: !_enviando, child: _pantalla());
  }

  Widget _pantalla() {
    return Scaffold(
      backgroundColor: RBColores.fondo,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 20, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: _enviando ? null : () => Navigator.maybePop(context),
                    icon: const Icon(Icons.close_rounded, size: 30, color: RBColores.tinta),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Reportar incidente',
                        style: TextStyle(
                          fontFamily: RBFuentes.titulos,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: RBColores.azul,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const EtiquetaSeccion('¿Qué está pasando?'),
                          const SizedBox(height: 12),
                          _selectorCategoria(),
                          const SizedBox(height: 26),
                          const EtiquetaSeccion('Ubicación'),
                          const SizedBox(height: 12),
                          _tarjetaUbicacion(),
                          const SizedBox(height: 26),
                          const EtiquetaSeccion('Descripción'),
                          const SizedBox(height: 12),
                          _campoDescripcion(),
                          if (_evidencia != null) ...[
                            const SizedBox(height: 26),
                            const EtiquetaSeccion('Evidencia'),
                            const SizedBox(height: 12),
                            _vistaEvidencia(),
                          ],
                          if (context.pantallaBaja) ...[
                            const SizedBox(height: 22),
                            _mensajeSuricata(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _barraInferior(),
          ],
        ),
      ),
    );
  }

  Widget _selectorCategoria() {
    if (_errorCategorias != null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              _errorCategorias!,
              style: const TextStyle(fontSize: 14, color: RBColores.rojo),
            ),
          ),
          TextButton(onPressed: _cargarCategorias, child: const Text('Reintentar')),
        ],
      );
    }

    final categorias = _categorias;
    if (categorias == null) {
      return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
    }

    // Las categorías vienen de la BD: la grilla se arma con las que existan.
    return LayoutBuilder(
      builder: (context, limites) {
        const separacion = 10.0;
        final columnas = limites.maxWidth >= 330 ? 4 : 3;
        final ancho = (limites.maxWidth - separacion * (columnas - 1)) / columnas;
        return Wrap(
          spacing: separacion,
          runSpacing: separacion,
          children: [
            for (final categoria in categorias)
              SizedBox(width: ancho, child: _tarjetaCategoria(categoria, ancho)),
          ],
        );
      },
    );
  }

  Widget _tarjetaCategoria(CategoriaIncidente categoria, double ancho) {
    final activo = categoria.id == _idCategoria;
    final icono = (ancho * 0.5).clamp(34.0, 44.0);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: activo ? RBColores.azul50 : Colors.white,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => setState(() => _idCategoria = categoria.id),
            child: Container(
              // Ocupa todo el ancho de su columna.
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: activo ? RBColores.azul : RBColores.linea,
                  width: activo ? 2.2 : 1.2,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconoCategoria(
                    codigo: categoria.codigo,
                    colorHex: categoria.colorHex,
                    tamano: icono,
                  ),
                  const SizedBox(height: 8),
                  // El nombre se achica antes que cortarse ("Sospechoso").
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      nombreCortoCategoria(categoria.codigo, categoria.nombre),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: activo ? FontWeight.w800 : FontWeight.w600,
                        color: activo ? RBColores.azul : RBColores.tinta,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (activo)
          Positioned(
            top: -6,
            right: -6,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: RBColores.azul,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
              ),
              child: const Icon(Icons.check_rounded, size: 15, color: Colors.white),
            ),
          ),
      ],
    );
  }

  Widget _tarjetaUbicacion() {
    final String titulo;
    final Widget subtitulo;
    if (!_ubicacionConfirmada) {
      titulo = _buscandoUbicacion ? 'Detectando ubicación…' : 'Sin ubicación';
      subtitulo = const Text(
        'Usa «Ajustar» para marcar el lugar',
        style: TextStyle(fontSize: 14.5, color: RBColores.texto2),
      );
    } else {
      titulo = _direccion ?? 'Buscando dirección…';
      subtitulo = Row(
        children: [
          Icon(
            _ubicacionPorGps ? Icons.check_rounded : Icons.touch_app_outlined,
            size: 17,
            color: RBColores.verde,
          ),
          const SizedBox(width: 4),
          Text(
            _ubicacionPorGps ? 'Detectada con tu GPS' : 'Marcada en el mapa',
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: RBColores.verde,
            ),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(RBRadios.tarjeta + 4),
        border: Border.all(color: RBColores.linea),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 150,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _ubicacion,
                    initialZoom: 16,
                    // El mapa no se arrastra: tocarlo mueve el pin a ese punto.
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                    onMapReady: () => _mapaListo = true,
                    onTap: (_, punto) => _moverUbicacion(punto),
                  ),
                  children: [capaMapaBase()],
                ),
                // Pin fijo al centro: el mapa siempre se centra en la ubicación.
                IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 40),
                      child: Icon(
                        Icons.location_on_rounded,
                        size: 46,
                        color: _ubicacionConfirmada ? RBColores.azul : RBColores.placeholder,
                        shadows: const [Shadow(color: Colors.white, blurRadius: 6)],
                      ),
                    ),
                  ),
                ),
                if (_buscandoUbicacion)
                  const Positioned(
                    top: 10,
                    left: 10,
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                const Positioned(left: 4, bottom: 2, child: AtribucionMapa()),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: RBColores.tinta,
                        ),
                      ),
                      const SizedBox(height: 3),
                      subtitulo,
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _ajustarUbicacion,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: RBColores.azul,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    minimumSize: const Size(0, 52),
                  ),
                  child: const Text('Ajustar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _campoDescripcion() {
    // FormField propio para que el contador quede dentro de la caja, abajo a
    // la derecha, y el error de validación aparezca debajo.
    return FormField<String>(
      validator: (_) {
        final valor = _descripcionController.text;
        if (valor.trim().isEmpty) {
          return 'Describe brevemente lo que sucedió';
        }
        // La API cuenta puntos de código: un emoji puede valer 2 o más.
        if (valor.trim().runes.length > _maximoDescripcion) {
          return 'La descripción no puede superar los 500 caracteres';
        }
        return null;
      },
      builder: (estado) {
        final usados = _descripcionController.text.trim().runes.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(RBRadios.tarjeta + 4),
                border: Border.all(
                  color: estado.hasError ? RBColores.rojo : RBColores.bordeCampo,
                  width: 1.2,
                ),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _descripcionController,
                    minLines: 3,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: [LengthLimitingTextInputFormatter(_maximoDescripcion)],
                    onChanged: (valor) => estado.didChange(valor),
                    style: const TextStyle(fontSize: 16, color: RBColores.tinta),
                    decoration: const InputDecoration(
                      hintText: 'Describe brevemente lo que sucedió...',
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$usados/$_maximoDescripcion',
                      style: const TextStyle(fontSize: 14, color: RBColores.texto2),
                    ),
                  ),
                ],
              ),
            ),
            if (estado.hasError)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                child: Text(
                  estado.errorText!,
                  style: const TextStyle(fontSize: 12.5, color: RBColores.rojo),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _vistaEvidencia() {
    final evidencia = _evidencia!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(RBRadios.tarjeta),
      child: SizedBox(
        width: double.infinity,
        height: 170,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_evidenciaEsVideo)
              Container(
                color: RBColores.azul50,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.videocam_outlined, color: RBColores.azul, size: 34),
                    const SizedBox(height: 6),
                    Text(
                      evidencia.nombreArchivo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, color: RBColores.tinta),
                    ),
                  ],
                ),
              )
            else
              Image.memory(evidencia.bytes, fit: BoxFit.cover),
            Positioned(
              top: 10,
              right: 10,
              child: Material(
                color: Colors.black.withValues(alpha: 0.55),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Quitar evidencia',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                  onPressed: () => setState(() => _evidencia = null),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Suricata con el aviso a los vecinos.
  Widget _mensajeSuricata() {
    return Row(
      children: [
        AvatarSuricata(tamano: context.escala(56)),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: RBColores.verde50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Se avisará a los vecinos que estén cerca del lugar. '
              '¡Gracias por cuidar tu barrio!',
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: RBColores.verde,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _barraInferior() {
    // En pantallas bajas la barra fija solo lleva los botones, para dejar
    // más espacio al formulario.
    final baja = context.pantallaBaja;
    final alto = baja || context.pantallaAngosta ? 52.0 : 60.0;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        baja ? 10 : 14,
        16,
        (baja ? 10 : 14) + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: RBColores.linea)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!baja) ...[_mensajeSuricata(), const SizedBox(height: 12)],
          Row(
            children: [
              _botonAdjuntar(
                icono: Icons.photo_camera_outlined,
                tooltip: 'Tomar foto',
                tamano: alto,
                onTap: () => _seleccionarEvidencia(camara: true),
              ),
              const SizedBox(width: 10),
              _botonAdjuntar(
                icono: Icons.image_outlined,
                tooltip: 'Elegir foto o video',
                tamano: alto,
                onTap: () => _seleccionarEvidencia(camara: false),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: alto,
                  child: ElevatedButton.icon(
                    onPressed: _enviando ? null : _enviarReporte,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: RBColores.verde,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: RBColores.verde.withValues(alpha: 0.6),
                      disabledForegroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(RBRadios.tarjeta),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: RBFuentes.interfaz,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    icon: _enviando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Icon(Icons.near_me_outlined, size: 22),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(_enviando ? 'Enviando…' : 'Enviar reporte'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _botonAdjuntar({
    required IconData icono,
    required String tooltip,
    required double tamano,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(RBRadios.tarjeta),
        child: InkWell(
          onTap: _enviando ? null : onTap,
          borderRadius: BorderRadius.circular(RBRadios.tarjeta),
          child: Container(
            width: tamano,
            height: tamano,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(RBRadios.tarjeta),
              border: Border.all(color: RBColores.bordeCampo, width: 1.2),
            ),
            child: Icon(icono, color: RBColores.azul, size: 26),
          ),
        ),
      ),
    );
  }
}

/// Mapa grande para ajustar el punto del reporte: el pin queda fijo al
/// centro y lo que se mueve es el mapa.
class _AjustarUbicacion extends StatefulWidget {
  final LatLng inicial;
  final UbicacionServicio ubicacionServicio;

  const _AjustarUbicacion({required this.inicial, required this.ubicacionServicio});

  @override
  State<_AjustarUbicacion> createState() => _AjustarUbicacionState();
}

class _AjustarUbicacionState extends State<_AjustarUbicacion> {
  final _controlador = MapController();
  late LatLng _centro = widget.inicial;
  bool _buscando = false;

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  Future<void> _usarGps() async {
    setState(() => _buscando = true);
    try {
      final punto = await widget.ubicacionServicio.obtenerUbicacionActual();
      if (!mounted) return;
      setState(() => _centro = punto);
      _controlador.move(punto, 17);
    } catch (_) {
      // Sin GPS el usuario igual puede mover el mapa a mano.
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.of(context).size.height * 0.78;
    return SizedBox(
      height: alto,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).padding.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ajustar ubicación',
              style: TextStyle(
                fontFamily: RBFuentes.titulos,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: RBColores.azul,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Mueve el mapa hasta dejar el pin sobre el lugar exacto.',
              style: TextStyle(fontSize: 15, color: RBColores.texto2),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(RBRadios.tarjeta),
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _controlador,
                      options: MapOptions(
                        initialCenter: _centro,
                        initialZoom: 17,
                        minZoom: 11,
                        maxZoom: 19,
                        interactionOptions: const InteractionOptions(
                          flags:
                              InteractiveFlag.drag |
                              InteractiveFlag.pinchZoom |
                              InteractiveFlag.doubleTapZoom |
                              InteractiveFlag.scrollWheelZoom,
                        ),
                        onPositionChanged: (posicion, hayGesto) {
                          if (hayGesto) setState(() => _centro = posicion.center);
                        },
                      ),
                      children: [capaMapaBase()],
                    ),
                    const IgnorePointer(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 46),
                          child: Icon(Icons.location_on_rounded, size: 50, color: RBColores.azul),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: BotonCircular(
                        icono: Icons.my_location_rounded,
                        color: RBColores.azul,
                        tooltip: 'Usar mi ubicación',
                        onTap: _buscando ? null : _usarGps,
                      ),
                    ),
                    const Positioned(left: 4, bottom: 2, child: AtribucionMapa()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, _centro),
                child: const Text('Confirmar ubicación'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
