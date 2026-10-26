import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rb_alertas/servicios/grupos_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/servicios/ubicacion_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/fondo_acceso.dart' show CampoRotulado;
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Crea o edita un grupo vecinal. Se muestra como panel inferior, igual que
/// el editor de zonas seguras; devuelve el grupo guardado o null si se cerró.
class GrupoFormularioVista extends StatefulWidget {
  final Grupo? grupo;
  final List<int> radiosPermitidos;

  const GrupoFormularioVista({
    super.key,
    this.grupo,
    required this.radiosPermitidos,
  });

  static Future<Grupo?> abrir(
    BuildContext context, {
    Grupo? grupo,
    required List<int> radiosPermitidos,
  }) {
    return showModalBottomSheet<Grupo>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      builder: (_) => GrupoFormularioVista(grupo: grupo, radiosPermitidos: radiosPermitidos),
    );
  }

  @override
  State<GrupoFormularioVista> createState() => _GrupoFormularioVistaState();
}

class _GrupoFormularioVistaState extends State<GrupoFormularioVista> {
  /// Centro del mapa cuando no hay grupo ni GPS: plaza de armas de Puerto Montt.
  static const _centroPorDefecto = LatLng(-41.4717, -72.9369);

  /// Velocidad a pie para traducir el radio a minutos de caminata (4 km/h).
  static const _metrosPorMinutoCaminando = 66.7;

  final _servicio = GruposServicio();
  final _ubicacionServicio = UbicacionServicio();
  final _mapController = MapController();
  bool _mapaListo = false;
  final _nombreCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();

  late LatLng _centro;
  late int _radio;
  bool _guardando = false;
  bool _buscandoUbicacion = false;

  /// Mientras el usuario mueve el mapa no se le pisa lo que escribió a mano.
  bool _direccionEditadaAMano = false;

  bool get _esNuevo => widget.grupo == null;

  List<int> get _radios => widget.radiosPermitidos.isEmpty
      ? const [500, 1000, 2000]
      : widget.radiosPermitidos;

  @override
  void initState() {
    super.initState();
    final grupo = widget.grupo;
    _centro = grupo != null ? LatLng(grupo.latitud, grupo.longitud) : _centroPorDefecto;
    _radio = grupo != null && _radios.contains(grupo.radioMetros)
        ? grupo.radioMetros
        : _radios[_radios.length ~/ 2];
    _nombreCtrl.text = grupo?.nombre ?? '';
    _descripcionCtrl.text = grupo?.descripcion ?? '';
    _direccionCtrl.text = grupo?.direccion ?? '';
    if (grupo == null) _usarUbicacionActual(silencioso: true);
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descripcionCtrl.dispose();
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
  /// un grupo nuevo: si no hay permiso, el usuario igual puede mover el mapa.
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

  Future<void> _completarDireccion(LatLng punto) async {
    if (_direccionEditadaAMano) return;
    final direccion = await _ubicacionServicio.obtenerDireccion(punto);
    if (!mounted || direccion == null || _direccionEditadaAMano) return;
    setState(() => _direccionCtrl.text = direccion);
  }

  int get _minutosCaminando => (_radio / _metrosPorMinutoCaminando).round();

  double get _zoomVistaPrevia => _radio >= 2000 ? 13 : (_radio >= 1000 ? 14 : 15);

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
      _mostrarMensaje('Inicia sesión para crear un grupo');
      return;
    }
    if (_nombreCtrl.text.trim().isEmpty) {
      _mostrarMensaje('Escribe un nombre para el grupo');
      return;
    }

    setState(() => _guardando = true);
    try {
      final Grupo grupo;
      if (_esNuevo) {
        grupo = await _servicio.crear(
          token: token,
          nombre: _nombreCtrl.text,
          descripcion: _descripcionCtrl.text,
          latitud: _centro.latitude,
          longitud: _centro.longitude,
          radioMetros: _radio,
          direccion: _direccionCtrl.text,
        );
      } else {
        grupo = await _servicio.actualizar(
          token: token,
          idGrupo: widget.grupo!.id,
          nombre: _nombreCtrl.text,
          descripcion: _descripcionCtrl.text,
          latitud: _centro.latitude,
          longitud: _centro.longitude,
          radioMetros: _radio,
          direccion: _direccionCtrl.text,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, grupo);
    } on GruposServicioException catch (e) {
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
                        _esNuevo ? 'Nuevo grupo' : 'Editar grupo',
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
                      onTap: _guardando ? null : () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                  children: [
                    CampoRotulado(
                      rotulo: 'Nombre del grupo',
                      campo: TextField(
                        controller: _nombreCtrl,
                        maxLength: 60,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Junta de vecinos Villa Los Notros',
                          counterText: '',
                          prefixIcon: Icon(Icons.groups_outlined, color: RBColores.azul),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    CampoRotulado(
                      rotulo: 'Descripción (opcional)',
                      campo: TextField(
                        controller: _descripcionCtrl,
                        maxLength: 255,
                        minLines: 1,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Para avisarnos entre vecinos del pasaje',
                          counterText: '',
                        ),
                      ),
                    ),
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
                    const Text('Área del grupo', style: RBTexto.rotuloCampo),
                    const SizedBox(height: 4),
                    const Text(
                      'Mueve el mapa hasta dejar el punto en el centro del sector.',
                      style: TextStyle(fontSize: 14, color: RBColores.texto2),
                    ),
                    const SizedBox(height: 10),
                    _vistaPrevia(),
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

  Widget _radioCobertura() {
    final indice = _radios.indexOf(_radio).clamp(0, _radios.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: Text('Radio del grupo', style: RBTexto.rotuloCampo)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: RBColores.verde50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                radioTexto(_radio),
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
        // Igual que en las zonas: solo existen los radios que acepta el servidor.
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
                  radioTexto(metros),
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
          'Los vecinos podrán compartir en el grupo los incidentes a menos de '
          '$_minutosCaminando minutos caminando desde el centro.',
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
                      color: RBColores.azul.withValues(alpha: 0.12),
                      borderColor: RBColores.azul,
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
                      child: const MarcadorGrupo(),
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
                onPressed: _guardando ? null : () => Navigator.pop(context),
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
                          _esNuevo ? 'Crear grupo' : 'Guardar cambios',
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

/// Círculo azul marino con el ícono de grupo: centro del área en los mapas.
class MarcadorGrupo extends StatelessWidget {
  const MarcadorGrupo({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: RBColores.azul,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6),
        ],
      ),
      child: const Icon(Icons.groups_rounded, color: Colors.white, size: 20),
    );
  }
}
