import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/servicios/ubicacion_servicio.dart';
import 'package:rb_alertas/servicios/zonas_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/fondo_acceso.dart' show CampoRotulado;
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Crea o edita una zona segura. Se muestra como panel inferior sobre la
/// lista de zonas; devuelve `true` si se guardó o se eliminó algo.
class ZonaDetalleVista extends StatefulWidget {
  final ZonaSegura? zona;
  final List<int> radiosPermitidos;

  const ZonaDetalleVista({
    super.key,
    this.zona,
    required this.radiosPermitidos,
  });

  static Future<bool?> abrir(
    BuildContext context, {
    ZonaSegura? zona,
    required List<int> radiosPermitidos,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      builder: (_) => ZonaDetalleVista(zona: zona, radiosPermitidos: radiosPermitidos),
    );
  }

  @override
  State<ZonaDetalleVista> createState() => _ZonaDetalleVistaState();
}

class _ZonaDetalleVistaState extends State<ZonaDetalleVista> {
  /// Centro del mapa cuando no hay zona ni GPS: plaza de armas de Puerto Montt.
  static const _centroPorDefecto = LatLng(-41.4717, -72.9369);

  /// Velocidad a pie para traducir el radio a minutos de caminata (4 km/h).
  static const _metrosPorMinutoCaminando = 66.7;

  final _servicio = ZonasServicio();
  final _ubicacionServicio = UbicacionServicio();
  final _mapController = MapController();
  bool _mapaListo = false;
  final _nombreCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();

  late TipoZona _tipo;
  late LatLng _centro;
  late int _radio;
  bool _guardando = false;
  bool _buscandoUbicacion = false;

  /// Mientras el usuario mueve el mapa no se le pisa lo que escribió a mano.
  bool _direccionEditadaAMano = false;

  bool get _esNueva => widget.zona == null;

  List<int> get _radios => widget.radiosPermitidos.isEmpty
      ? const [500, 1000, 2000]
      : widget.radiosPermitidos;

  @override
  void initState() {
    super.initState();
    final zona = widget.zona;
    _tipo = zona?.tipo ?? TipoZona.casa;
    _centro = zona != null
        ? LatLng(zona.latitud, zona.longitud)
        : _centroPorDefecto;
    // Si el radio guardado ya no está entre los permitidos, se usa el del medio.
    _radio = zona != null && _radios.contains(zona.radioMetros)
        ? zona.radioMetros
        : _radios[_radios.length ~/ 2];
    _nombreCtrl.text = zona != null && zona.tipo == TipoZona.otro
        ? zona.nombre
        : '';
    _direccionCtrl.text = zona?.direccion ?? '';
    if (zona == null) _usarUbicacionActual(silencioso: true);
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _direccionCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  /// Centra el mapa en el GPS. [silencioso] evita el aviso de error al abrir
  /// una zona nueva: si no hay permiso, el usuario igual puede mover el mapa.
  Future<void> _usarUbicacionActual({bool silencioso = false}) async {
    setState(() => _buscandoUbicacion = true);
    try {
      final punto = await _ubicacionServicio.obtenerUbicacionActual();
      if (!mounted) return;
      setState(() => _centro = punto);
      _ajustarMapa();
      _completarDireccion(punto);
    } on UbicacionServicioException catch (e) {
      if (!silencioso) _mostrarMensaje(e.mensaje);
    } catch (_) {
      if (!silencioso) _mostrarMensaje('No se pudo obtener tu ubicación');
    } finally {
      if (mounted) setState(() => _buscandoUbicacion = false);
    }
  }

  /// Rellena la dirección con geocodificación inversa, salvo que el usuario
  /// ya haya escrito la suya.
  Future<void> _completarDireccion(LatLng punto) async {
    if (_direccionEditadaAMano) return;
    final direccion = await _ubicacionServicio.obtenerDireccion(punto);
    if (!mounted || direccion == null || _direccionEditadaAMano) return;
    setState(() => _direccionCtrl.text = direccion);
  }

  String _radioTexto(int metros) => metros < 1000
      ? '$metros m'
      : '${(metros / 1000).toStringAsFixed(metros % 1000 == 0 ? 0 : 1).replaceAll('.', ',')} km';

  int get _minutosCaminando => (_radio / _metrosPorMinutoCaminando).round();

  /// Zoom al que el círculo entra completo en la vista previa.
  double get _zoomVistaPrevia =>
      _radio >= 2000 ? 13 : (_radio >= 1000 ? 14 : 15);

  /// Lleva el mapa al punto y al zoom actuales. El move va después del frame
  /// porque el controlador no acepta órdenes mientras se está construyendo.
  void _ajustarMapa() {
    if (!_mapaListo) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapaListo) return;
      _mapController.move(_centro, _zoomVistaPrevia);
    });
  }

  Future<void> _guardar() async {
    final token = Sesion.token;
    if (token == null || token.isEmpty) {
      _mostrarMensaje('Inicia sesión para guardar tus zonas');
      return;
    }
    if (_tipo.nombreLibre && _nombreCtrl.text.trim().isEmpty) {
      _mostrarMensaje('Escribe un nombre para la zona');
      return;
    }

    setState(() => _guardando = true);
    try {
      if (_esNueva) {
        await _servicio.crear(
          token: token,
          tipo: _tipo,
          nombre: _nombreCtrl.text,
          latitud: _centro.latitude,
          longitud: _centro.longitude,
          radioMetros: _radio,
          direccion: _direccionCtrl.text,
        );
      } else {
        await _servicio.actualizar(
          token: token,
          idZona: widget.zona!.id,
          tipo: _tipo,
          nombre: _nombreCtrl.text,
          latitud: _centro.latitude,
          longitud: _centro.longitude,
          radioMetros: _radio,
          direccion: _direccionCtrl.text,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ZonasServicioException catch (e) {
      _mostrarMensaje(e.mensaje);
    } catch (_) {
      _mostrarMensaje('No se pudo conectar con el servidor');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _eliminar() async {
    final zona = widget.zona;
    final token = Sesion.token;
    if (zona == null || token == null) return;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contextoDialogo) => AlertDialog(
        title: const Text('Eliminar zona'),
        content: Text(
          '¿Eliminar «${zona.nombre}»? Dejarás de recibir alertas de lo que '
          'ocurra en ese sector.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contextoDialogo, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(contextoDialogo, true),
            style: TextButton.styleFrom(foregroundColor: RBColores.rojo),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    setState(() => _guardando = true);
    try {
      await _servicio.eliminar(token: token, idZona: zona.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ZonasServicioException catch (e) {
      _mostrarMensaje(e.mensaje);
    } catch (_) {
      _mostrarMensaje('No se pudo conectar con el servidor');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Interfaz

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.of(context).size.height * 0.92;
    // ScaffoldMessenger propio: los avisos se ven encima del panel.
    return SizedBox(
      height: alto,
      child: ScaffoldMessenger(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: RBColores.bordeCampo,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 14, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _esNueva ? 'Nueva ubicación' : 'Editar ubicación',
                        style: TextStyle(
                          fontFamily: RBFuentes.titulos,
                          fontSize: context.escala(28),
                          fontWeight: FontWeight.w800,
                          color: RBColores.azul,
                        ),
                      ),
                    ),
                    BotonCircular(
                      icono: Icons.close_rounded,
                      fondo: RBColores.fondo,
                      tamano: 48,
                      tooltip: 'Cerrar',
                      onTap: _guardando ? null : () => Navigator.pop(context, false),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                  children: [
                    _tipoDeLugar(),
                    const SizedBox(height: 18),
                    _campoNombre(),
                    const SizedBox(height: 18),
                    CampoRotulado(
                      rotulo: 'Dirección de referencia',
                      campo: TextField(
                        controller: _direccionCtrl,
                        maxLength: 255,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) => _direccionEditadaAMano = true,
                        decoration: const InputDecoration(
                          hintText: 'Av. Presidente Ibáñez 1234',
                          counterText: '',
                          prefixIcon: Icon(Icons.place_outlined, color: RBColores.azul),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _radioCobertura(),
                    const SizedBox(height: 22),
                    const Text('Vista previa', style: RBTexto.rotuloCampo),
                    const SizedBox(height: 4),
                    const Text(
                      'Mueve el mapa hasta dejar el punto sobre el lugar exacto.',
                      style: TextStyle(fontSize: 14, color: RBColores.texto2),
                    ),
                    const SizedBox(height: 10),
                    _vistaPrevia(),
                    if (!_esNueva) ...[
                      const SizedBox(height: 14),
                      Center(
                        child: TextButton.icon(
                          onPressed: _guardando ? null : _eliminar,
                          style: TextButton.styleFrom(foregroundColor: RBColores.rojo),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Eliminar ubicación'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _barraAcciones(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tipoDeLugar() {
    return CampoRotulado(
      rotulo: 'Tipo de lugar',
      campo: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tipo in TipoZona.values)
            ChipFiltro(
              etiqueta: tipo.etiqueta,
              activo: _tipo == tipo,
              icono: Icon(tipo.icono, size: 19, color: RBColores.verde),
              onTap: () => setState(() => _tipo = tipo),
            ),
        ],
      ),
    );
  }

  /// Solo "Otro lugar" lleva nombre propio: en los demás lo fija el servidor,
  /// y así el nombre guardado siempre corresponde al ícono.
  Widget _campoNombre() {
    if (!_tipo.nombreLibre) {
      return CampoRotulado(
        rotulo: 'Nombre de la ubicación',
        campo: InputDecorator(
          decoration: const InputDecoration(
            enabled: false,
            helperText: 'El nombre lo define el tipo de lugar',
            fillColor: RBColores.fondo,
          ),
          child: Text(
            _tipo.etiqueta,
            style: const TextStyle(fontSize: 16, color: RBColores.tinta),
          ),
        ),
      );
    }
    return CampoRotulado(
      rotulo: 'Nombre de la ubicación',
      campo: TextField(
        controller: _nombreCtrl,
        maxLength: 60,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Colegio, casa de mis padres…',
          counterText: '',
        ),
      ),
    );
  }

  Widget _radioCobertura() {
    final indice = _radios.indexOf(_radio).clamp(0, _radios.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: Text('Radio de cobertura', style: RBTexto.rotuloCampo)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: RBColores.verde50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _radioTexto(_radio),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: RBColores.verde,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // El slider se mueve por posiciones, no por metros: así solo existen
        // los valores que el servidor acepta y no hay estados intermedios.
        Slider(
          value: indice.toDouble(),
          min: 0,
          max: (_radios.length - 1).toDouble(),
          divisions: _radios.length - 1,
          onChanged: (valor) {
            setState(() => _radio = _radios[valor.round()]);
            _ajustarMapa();
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final metros in _radios)
                Text(
                  _radioTexto(metros),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: metros == _radio ? FontWeight.w700 : FontWeight.w500,
                    color: metros == _radio ? RBColores.verde : RBColores.texto2,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Recibirás alertas de incidentes a menos de $_minutosCaminando '
          'minutos caminando desde esta ubicación.',
          style: const TextStyle(fontSize: 14, height: 1.4, color: RBColores.texto2),
        ),
      ],
    );
  }

  Widget _vistaPrevia() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(RBRadios.tarjeta + 4),
      child: SizedBox(
        height: context.altoRelativo(0.32, minimo: 180, maximo: 260),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _centro,
                initialZoom: _zoomVistaPrevia,
                minZoom: 11,
                maxZoom: 18,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
                ),
                onMapReady: () {
                  _mapaListo = true;
                  _ajustarMapa();
                },
                // El punto está fijo al centro: lo que se mueve es el mapa.
                onPositionChanged: (posicion, hayGesto) {
                  if (!hayGesto) return;
                  setState(() => _centro = posicion.center);
                },
                // Al soltar, se intenta rellenar la dirección del punto.
                onMapEvent: (evento) {
                  if (evento is MapEventMoveEnd) _completarDireccion(_centro);
                },
              ),
              children: [
                capaMapaBase(),
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _centro,
                      radius: _radio.toDouble(),
                      useRadiusInMeter: true,
                      color: RBColores.verde.withValues(alpha: 0.15),
                      borderColor: RBColores.verde,
                      borderStrokeWidth: 2.5,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _centro,
                      width: 44,
                      height: 44,
                      child: Container(
                        decoration: BoxDecoration(
                          color: RBColores.verde,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6),
                          ],
                        ),
                        child: Icon(_tipo.icono, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: _buscandoUbicacion
                  ? const BotonCircular(icono: Icons.more_horiz_rounded, onTap: null, tamano: 46)
                  : BotonCircular(
                      icono: Icons.my_location_rounded,
                      color: RBColores.azul,
                      tamano: 46,
                      tooltip: 'Usar mi ubicación',
                      onTap: () => _usarUbicacionActual(),
                    ),
            ),
            const Positioned(left: 4, bottom: 2, child: AtribucionMapa()),
          ],
        ),
      ),
    );
  }

  Widget _barraAcciones() {
    final altoBoton = context.pantallaBaja || context.pantallaAngosta ? 52.0 : 60.0;
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        14 + MediaQuery.of(context).viewPadding.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: RBColores.linea)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: altoBoton,
              child: OutlinedButton(
                onPressed: _guardando ? null : () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  foregroundColor: RBColores.tinta,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(RBRadios.tarjeta),
                  ),
                ),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Descartar', style: TextStyle(fontSize: 18)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: SizedBox(
              height: altoBoton,
              child: ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  backgroundColor: RBColores.verde,
                  disabledBackgroundColor: RBColores.verde.withValues(alpha: 0.6),
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(RBRadios.tarjeta),
                  ),
                ),
                child: _guardando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _esNueva ? 'Guardar zona' : 'Guardar cambios',
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
