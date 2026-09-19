import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:rb_alertas/servicios/reporte_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/servicios/ubicacion_servicio.dart';
import 'package:rb_alertas/vistas/mapa_vista.dart';
import 'package:rb_alertas/widgets/barra_navegacion_inferior.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';

class ReportarIncidenteVista extends StatefulWidget {
  const ReportarIncidenteVista({super.key});

  @override
  State<ReportarIncidenteVista> createState() => _ReportarIncidenteVistaState();
}

class _ReportarIncidenteVistaState extends State<ReportarIncidenteVista> {
  static const _colorAzul = Color(0xFF0056D2);
  static const _colorFondo = Color(0xFFF7F8FC);
  static const _colorTitulo = Color(0xFF111827);
  static const _colorTextoGris = Color(0xFF6B7280);
  static const _colorBorde = Color(0xFFD1D5DB);

  // Centro de Puerto Montt, usado mientras no haya ubicación real.
  static const _ubicacionPorDefecto = LatLng(-41.4693, -72.9424);
  static const _tamanoMaximoEvidencia = 20 * 1024 * 1024;

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
      _moverUbicacion(punto);
    } on UbicacionServicioException catch (e) {
      if (!mounted) return;
      _mostrarMensaje(e.mensaje);
    } catch (_) {
      if (!mounted) return;
      _mostrarMensaje(
        'No pudimos detectar tu ubicación: toca el mapa para marcar el lugar',
      );
    } finally {
      if (mounted) setState(() => _buscandoUbicacion = false);
    }
  }

  Future<void> _moverUbicacion(LatLng punto) async {
    setState(() {
      _versionUbicacion++;
      _ubicacion = punto;
      _ubicacionConfirmada = true;
      _direccion = null;
    });
    if (_mapaListo) {
      _mapController.move(punto, _mapController.camera.zoom);
    }

    final direccion = await _ubicacionServicio.obtenerDireccion(punto);
    // Si el usuario ya marcó otro punto, esta respuesta llegó tarde.
    if (!mounted || _ubicacion != punto) return;
    setState(() {
      _direccion = direccion ??
          '${punto.latitude.toStringAsFixed(5)}, ${punto.longitude.toStringAsFixed(5)}';
    });
  }

  void _cambiarZoom(double delta) {
    if (!_mapaListo) return;
    final zoom = (_mapController.camera.zoom + delta).clamp(3.0, 19.0);
    _mapController.move(_ubicacion, zoom);
  }

  Future<void> _seleccionarEvidencia() async {
    final origen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(context, 'camara'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir foto o video'),
              onTap: () => Navigator.pop(context, 'galeria'),
            ),
          ],
        ),
      ),
    );
    if (origen == null) return;

    final selector = ImagePicker();
    final XFile? archivo;
    try {
      archivo = origen == 'camara'
          ? await selector.pickImage(
              source: ImageSource.camera,
              maxWidth: 1920,
              imageQuality: 85,
            )
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
    final esVideo = (archivo.mimeType ?? '').startsWith('video/') ||
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
    final uuidUsuario = Sesion.uuidUsuario;
    if (uuidUsuario == null) {
      _mostrarMensaje('Debes iniciar sesión para enviar un reporte');
      return;
    }
    if (_idCategoria == null) {
      _mostrarMensaje('Selecciona una categoría');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (!_ubicacionConfirmada) {
      _mostrarMensaje('Toca el mapa para marcar dónde ocurrió el incidente');
      return;
    }

    setState(() => _enviando = true);

    try {
      await _reporteServicio.enviarReporte(
        uuidUsuario: uuidUsuario,
        idCategoria: _idCategoria!,
        descripcion: _descripcionController.text.trim(),
        latitud: _ubicacion.latitude,
        longitud: _ubicacion.longitude,
        direccion: _direccion,
        evidencia: _evidencia,
      );

      if (!mounted) return;
      _mostrarMensaje('Reporte enviado. ¡Gracias por alertar a tu comunidad!');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MapaVista(centrarEn: _ubicacion),
        ),
      );
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
    return PopScope(
      canPop: !_enviando,
      child: _pantalla(),
    );
  }

  Widget _pantalla() {
    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        backgroundColor: _colorFondo,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: _colorAzul),
          onPressed: () {},
        ),
        title: const Text(
          'RB Alertas',
          style: TextStyle(
            color: _colorAzul,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: _colorAzul),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reportar Incidente',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: _colorTitulo,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Selecciona una categoría y proporciona detalles para '
                    'alertar a la comunidad y autoridades.',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: _colorTextoGris,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),

                  _etiqueta('CATEGORÍA'),
                  const SizedBox(height: 10),
                  _selectorCategoria(),
                  const SizedBox(height: 24),

                  _etiqueta('DESCRIPCIÓN'),
                  const SizedBox(height: 10),
                  _campoDescripcion(),
                  const SizedBox(height: 24),

                  _etiqueta('EVIDENCIA (OPCIONAL)'),
                  const SizedBox(height: 10),
                  _cajaEvidencia(),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      _etiqueta('UBICACIÓN DETECTADA'),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _buscandoUbicacion ? null : _detectarUbicacion,
                        style: TextButton.styleFrom(
                          foregroundColor: _colorAzul,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.my_location_rounded, size: 16),
                        label: const Text(
                          'Actualizar',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _mapaUbicacion(),
                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _enviando ? null : _enviarReporte,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _colorAzul,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _colorAzul.withValues(alpha: 0.6),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: _enviando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_outlined, size: 20),
                      label: Text(
                        _enviando ? 'Enviando...' : 'Enviar Reporte',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: BarraNavegacionInferior(
        seccionActiva: SeccionApp.reportar,
        habilitada: !_enviando,
      ),
    );
  }

  Widget _etiqueta(String texto) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: Color(0xFF374151),
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
              style: const TextStyle(fontSize: 13, color: Color(0xFFB91C1C)),
            ),
          ),
          TextButton(
            onPressed: _cargarCategorias,
            child: const Text('Reintentar'),
          ),
        ],
      );
    }

    final categorias = _categorias;
    if (categorias == null) {
      return const SizedBox(
        height: 40,
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: _colorAzul),
            ),
            SizedBox(width: 10),
            Text(
              'Cargando categorías...',
              style: TextStyle(fontSize: 13, color: _colorTextoGris),
            ),
          ],
        ),
      );
    }

    // Las categorías vienen de la BD y pueden ser varias: se acomodan en
    // varias líneas para que todas queden a la vista.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final categoria in categorias) _chipCategoria(categoria),
      ],
    );
  }

  Widget _chipCategoria(CategoriaIncidente categoria) {
    final activo = categoria.id == _idCategoria;
    final colorContenido = activo ? Colors.white : const Color(0xFF1F2937);

    return Material(
      color: activo ? _colorAzul : const Color(0xFFE8EBF3),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => setState(() => _idCategoria = categoria.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(iconoCategoria(categoria.codigo), size: 18, color: colorContenido),
              const SizedBox(width: 6),
              Text(
                categoria.nombre,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: colorContenido,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _campoDescripcion() {
    return TextFormField(
      controller: _descripcionController,
      minLines: 4,
      maxLines: 6,
      textCapitalization: TextCapitalization.sentences,
      inputFormatters: [LengthLimitingTextInputFormatter(500)],
      validator: (valor) {
        if (valor == null || valor.trim().isEmpty) {
          return 'Describe brevemente lo que sucedió';
        }
        // La API cuenta puntos de código: un emoji puede valer 2 o más.
        if (valor.trim().runes.length > 500) {
          return 'La descripción no puede superar los 500 caracteres';
        }
        return null;
      },
      decoration: InputDecoration(
        hintText: 'Describe brevemente lo que sucedió...',
        hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.all(14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _colorBorde),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _colorAzul, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFB91C1C)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFB91C1C), width: 1.6),
        ),
      ),
    );
  }

  Widget _cajaEvidencia() {
    final evidencia = _evidencia;

    if (evidencia == null) {
      return CustomPaint(
        painter: const _BordePunteado(color: Color(0xFFB8C0CC)),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _seleccionarEvidencia,
            borderRadius: BorderRadius.circular(12),
            child: const SizedBox(
              width: double.infinity,
              height: 110,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined, color: _colorAzul, size: 30),
                  SizedBox(height: 8),
                  Text(
                    'Adjuntar foto o video',
                    style: TextStyle(
                      fontSize: 13,
                      color: _colorAzul,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: double.infinity,
        height: 150,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_evidenciaEsVideo)
              Container(
                color: const Color(0xFFE8EBF3),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.videocam_outlined, color: _colorAzul, size: 34),
                    const SizedBox(height: 6),
                    Text(
                      evidencia.nombreArchivo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
                    ),
                  ],
                ),
              )
            else
              Image.memory(evidencia.bytes, fit: BoxFit.cover),
            Positioned(
              top: 8,
              right: 8,
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

  Widget _mapaUbicacion() {
    final String textoUbicacion;
    if (!_ubicacionConfirmada) {
      textoUbicacion = _buscandoUbicacion
          ? 'Detectando ubicación...'
          : 'Toca el mapa para marcar el lugar';
    } else {
      textoUbicacion = _direccion ?? 'Buscando dirección...';
    }

    return Container(
      height: 150,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _colorBorde),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _ubicacion,
                initialZoom: 15,
                // El mapa no se arrastra: tocarlo mueve el pin a ese punto.
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
                onMapReady: () => _mapaListo = true,
                onTap: (_, punto) => _moverUbicacion(punto),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.rbalertas.rb_alertas',
                ),
              ],
            ),

            // Pin fijo al centro: el mapa siempre se centra en la ubicación.
            IgnorePointer(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 34,
                      color: _ubicacionConfirmada ? _colorAzul : _colorTextoGris,
                    ),
                    const SizedBox(height: 2),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 230),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Text(
                        textoUbicacion,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: _colorTitulo,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_buscandoUbicacion)
              const Positioned(
                top: 8,
                left: 8,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _colorAzul),
                ),
              ),

            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _colorBorde),
                ),
                child: Column(
                  children: [
                    _botonZoom(Icons.add, () => _cambiarZoom(1)),
                    Container(width: 22, height: 1, color: _colorBorde),
                    _botonZoom(Icons.remove, () => _cambiarZoom(-1)),
                  ],
                ),
              ),
            ),

            const Positioned(
              left: 6,
              bottom: 3,
              child: Text(
                '© OpenStreetMap',
                style: TextStyle(fontSize: 8, color: Color(0xFF6B7280)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _botonZoom(IconData icono, VoidCallback alPresionar) {
    return InkWell(
      onTap: alPresionar,
      child: SizedBox(
        width: 24,
        height: 24,
        child: Icon(icono, size: 16, color: const Color(0xFF374151)),
      ),
    );
  }
}

class _BordePunteado extends CustomPainter {
  final Color color;

  const _BordePunteado({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final borde = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      );

    for (final tramo in borde.computeMetrics()) {
      var distancia = 0.0;
      while (distancia < tramo.length) {
        canvas.drawPath(tramo.extractPath(distancia, distancia + 6), pincel);
        distancia += 11;
      }
    }
  }

  @override
  bool shouldRepaint(_BordePunteado anterior) => anterior.color != color;
}
