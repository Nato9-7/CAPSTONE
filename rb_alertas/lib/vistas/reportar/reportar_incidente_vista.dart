import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:rb_alertas/config/mapa_config.dart';
import 'package:rb_alertas/modelos/modelos.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/servicios/grupos_servicio.dart';
import 'package:rb_alertas/servicios/reporte_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/servicios/ubicacion_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/reportar/widgets/ajustar_ubicacion.dart';
import 'package:rb_alertas/vistas/reportar/widgets/barra_envio.dart';
import 'package:rb_alertas/vistas/reportar/widgets/campo_descripcion.dart';
import 'package:rb_alertas/vistas/reportar/widgets/seccion_grupos.dart';
import 'package:rb_alertas/vistas/reportar/widgets/selector_categoria.dart';
import 'package:rb_alertas/vistas/reportar/widgets/tarjeta_ubicacion.dart';
import 'package:rb_alertas/vistas/reportar/widgets/vista_evidencia.dart';
import 'package:rb_alertas/widgets/dialogos.dart';
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
  static const _tamanoMaximoEvidencia = 20 * 1024 * 1024;
  static const _maximoDescripcion = 500;

  final _formKey = GlobalKey<FormState>();
  final _descripcionController = TextEditingController();
  final _mapController = MapController();
  final _reporteServicio = ReporteServicio();
  final _ubicacionServicio = UbicacionServicio();
  final _gruposServicio = GruposServicio();

  List<CategoriaIncidente>? _categorias;
  String? _errorCategorias;
  int? _idCategoria;

  Evidencia? _evidencia;
  bool _evidenciaEsVideo = false;

  LatLng _ubicacion = MapaConfig.centroPorDefecto;
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

  // Grupos del usuario cuyo círculo contiene la ubicación elegida. Vacío si no
  // tiene grupos ahí: la sección no se muestra y el reporte es uno normal.
  List<GrupoEnPunto> _gruposDisponibles = [];
  final Set<int> _gruposElegidos = {};
  // Privado: solo lo ven los vecinos de los grupos elegidos.
  bool _soloGrupo = false;

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
    } catch (e) {
      if (mounted) setState(() => _errorCategorias = mensajeDeError(e));
    }
  }

  // ---------------------------------------------------------------------------
  // Ubicación y grupos

  Future<void> _detectarUbicacion() async {
    setState(() => _buscandoUbicacion = true);
    final version = _versionUbicacion;
    try {
      final punto = await _ubicacionServicio.obtenerUbicacionActual();
      if (!mounted || _versionUbicacion != version) return;
      _moverUbicacion(punto, porGps: true);
    } on UbicacionServicioException catch (e) {
      if (mounted) mostrarAviso(context, e.mensaje.replaceAll('toca el mapa', 'usa «Ajustar»'));
    } catch (_) {
      if (mounted) {
        mostrarAviso(context, 'No pudimos detectar tu ubicación: usa «Ajustar» para marcar el lugar');
      }
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
    if (_mapaListo) _mapController.move(punto, _mapController.camera.zoom);
    _buscarGrupos(punto);

    final direccion = await _ubicacionServicio.obtenerDireccion(punto);
    // Si el usuario ya marcó otro punto, esta respuesta llegó tarde.
    if (!mounted || _ubicacion != punto) return;
    setState(() {
      _direccion =
          direccion ?? '${punto.latitude.toStringAsFixed(5)}, ${punto.longitude.toStringAsFixed(5)}';
    });
  }

  /// Revisa en qué grupos del usuario cae el punto. Si falla, el reporte se
  /// puede enviar igual como uno normal: los grupos son un extra.
  Future<void> _buscarGrupos(LatLng punto) async {
    if (!Sesion.activa) return;
    try {
      final grupos = await _gruposServicio.enPunto(latitud: punto.latitude, longitud: punto.longitude);
      // Si el usuario ya marcó otro punto, esta respuesta llegó tarde.
      if (!mounted || _ubicacion != punto) return;
      setState(() {
        _gruposDisponibles = grupos;
        // Se conservan solo los elegidos que siguen conteniendo el punto.
        _gruposElegidos.retainWhere((id) => grupos.any((g) => g.id == id));
        if (_gruposElegidos.isEmpty) _soloGrupo = false;
      });
    } catch (_) {
      if (!mounted || _ubicacion != punto) return;
      setState(() {
        _gruposDisponibles = [];
        _gruposElegidos.clear();
        _soloGrupo = false;
      });
    }
  }

  void _alternarGrupo(int idGrupo) {
    setState(() {
      if (!_gruposElegidos.remove(idGrupo)) _gruposElegidos.add(idGrupo);
      if (_gruposElegidos.isEmpty) _soloGrupo = false;
    });
  }

  /// Abre un mapa grande para mover el pin hasta el lugar exacto.
  Future<void> _ajustarUbicacion() async {
    final punto = await showModalBottomSheet<LatLng>(
      context: context,
      isScrollControlled: true,
      builder: (_) => HojaAjustarUbicacion(inicial: _ubicacion, ubicacionServicio: _ubicacionServicio),
    );
    if (punto != null && mounted) _moverUbicacion(punto);
  }

  // ---------------------------------------------------------------------------
  // Evidencia y envío

  Future<void> _seleccionarEvidencia({required bool camara}) async {
    final selector = ImagePicker();
    final XFile? archivo;
    try {
      archivo = camara
          ? await selector.pickImage(source: ImageSource.camera, maxWidth: 1920, imageQuality: 85)
          : await selector.pickMedia(maxWidth: 1920, imageQuality: 85);
    } catch (_) {
      if (mounted) mostrarAviso(context, 'No se pudo abrir la cámara o la galería');
      return;
    }
    if (archivo == null) return;

    // Se revisa el tamaño antes de leerlo: un video largo puede pesar cientos
    // de MB y cargarlo completo en memoria solo para rechazarlo congela la app.
    if (await archivo.length() > _tamanoMaximoEvidencia) {
      if (mounted) mostrarAviso(context, 'La evidencia no puede superar los 20 MB');
      return;
    }
    final bytes = await archivo.readAsBytes();
    if (!mounted) return;

    final nombre = archivo.name.toLowerCase();
    final esVideo = (archivo.mimeType ?? '').startsWith('video/') ||
        ['.mp4', '.mov', '.webm'].any(nombre.endsWith);
    final evidencia = Evidencia(nombreArchivo: archivo.name, bytes: bytes);
    setState(() {
      _evidencia = evidencia;
      _evidenciaEsVideo = esVideo;
    });
  }

  Future<void> _enviarReporte() async {
    if (!Sesion.activa) {
      mostrarAviso(context, 'Debes iniciar sesión para enviar un reporte');
      return;
    }
    if (_idCategoria == null) {
      mostrarAviso(context, 'Selecciona una categoría');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (!_ubicacionConfirmada) {
      mostrarAviso(context, 'Usa «Ajustar» para marcar dónde ocurrió el incidente');
      return;
    }

    setState(() => _enviando = true);
    try {
      await _reporteServicio.enviarReporte(
        idCategoria: _idCategoria!,
        descripcion: _descripcionController.text.trim(),
        latitud: _ubicacion.latitude,
        longitud: _ubicacion.longitude,
        direccion: _direccion,
        evidencia: _evidencia,
        idsGrupos: _gruposElegidos.toList(),
        soloGrupo: _soloGrupo,
      );
      if (!mounted) return;
      mostrarAviso(
        context,
        _soloGrupo
            ? 'Reporte enviado a tu grupo. ¡Gracias por avisar a tus vecinos!'
            : 'Reporte enviado. ¡Gracias por alertar a tu comunidad!',
      );
      Navigator.pop(context, _ubicacion);
    } catch (e) {
      if (mounted) mostrarAviso(context, mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Interfaz

  @override
  Widget build(BuildContext context) {
    // Mientras se envía no se puede salir: el resultado se perdería.
    return PopScope(
      canPop: !_enviando,
      child: Scaffold(
        backgroundColor: RBColores.fondo,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _encabezado(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Form(key: _formKey, child: _formulario()),
                    ),
                  ),
                ),
              ),
              BarraEnvio(
                enviando: _enviando,
                soloGrupo: _soloGrupo,
                onTomarFoto: () => _seleccionarEvidencia(camara: true),
                onElegirArchivo: () => _seleccionarEvidencia(camara: false),
                onEnviar: _enviarReporte,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _encabezado() {
    return Padding(
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
    );
  }

  Widget _formulario() {
    final evidencia = _evidencia;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EtiquetaSeccion('¿Qué está pasando?'),
        const SizedBox(height: 12),
        SelectorCategoria(
          categorias: _categorias,
          error: _errorCategorias,
          idSeleccionada: _idCategoria,
          onSeleccionar: (id) => setState(() => _idCategoria = id),
          onReintentar: _cargarCategorias,
        ),
        const SizedBox(height: 26),
        const EtiquetaSeccion('Ubicación'),
        const SizedBox(height: 12),
        TarjetaUbicacion(
          mapController: _mapController,
          ubicacion: _ubicacion,
          confirmada: _ubicacionConfirmada,
          porGps: _ubicacionPorGps,
          direccion: _direccion,
          buscando: _buscandoUbicacion,
          onMapaListo: () => _mapaListo = true,
          onTocarMapa: _moverUbicacion,
          onAjustar: _ajustarUbicacion,
        ),
        if (_gruposDisponibles.isNotEmpty) ...[
          const SizedBox(height: 26),
          const EtiquetaSeccion('Compartir en tus grupos'),
          const SizedBox(height: 12),
          SeccionGrupos(
            grupos: _gruposDisponibles,
            elegidos: _gruposElegidos,
            soloGrupo: _soloGrupo,
            onAlternarGrupo: _alternarGrupo,
            onSoloGrupo: (valor) => setState(() => _soloGrupo = valor),
          ),
        ],
        const SizedBox(height: 26),
        const EtiquetaSeccion('Descripción'),
        const SizedBox(height: 12),
        CampoDescripcion(controller: _descripcionController, maximo: _maximoDescripcion),
        if (evidencia != null) ...[
          const SizedBox(height: 26),
          const EtiquetaSeccion('Evidencia'),
          const SizedBox(height: 12),
          VistaEvidencia(
            evidencia: evidencia,
            esVideo: _evidenciaEsVideo,
            onQuitar: () => setState(() => _evidencia = null),
          ),
        ],
        // En pantallas bajas el mensaje va al final del formulario y no en la barra.
        if (context.pantallaBaja) ...[
          const SizedBox(height: 22),
          MensajeSuricata(soloGrupo: _soloGrupo),
        ],
      ],
    );
  }
}
