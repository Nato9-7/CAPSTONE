// Editor de un área circular en el mapa (zonas seguras y grupos vecinales):
// estado común, panel inferior, selector de radio y vista previa.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rb_alertas/servicios/ubicacion_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/widgets/dialogos.dart';
import 'package:rb_alertas/widgets/fondo_acceso.dart' show CampoRotulado;
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Centro de los mapas sin punto conocido: plaza de armas de Puerto Montt.
const centroPorDefecto = LatLng(-41.4717, -72.9369);

/// Radios que se usan si la API no informa los permitidos.
const radiosPorDefecto = [500, 1000, 2000];

/// Velocidad a pie para traducir el radio a minutos de caminata (4 km/h).
const _metrosPorMinutoCaminando = 66.7;

/// Minutos a pie desde el centro hasta el borde de un área de [radio] metros.
int minutosCaminando(int radio) => (radio / _metrosPorMinutoCaminando).round();

/// Zoom al que un círculo de [radio] metros entra completo en la vista previa.
double zoomParaRadio(int radio) => radio >= 2000 ? 13 : (radio >= 1000 ? 14 : 15);

/// Estado compartido por los editores de un área: centro, radio, dirección de
/// referencia y el mapa de vista previa.
mixin EditorArea<T extends StatefulWidget> on State<T> {
  final _ubicacionServicio = UbicacionServicio();
  final _controladorMapa = MapController();
  final direccionCtrl = TextEditingController();

  late LatLng centro;
  late int radio;
  late List<int> radios;
  bool buscandoUbicacion = false;
  bool _mapaListo = false;

  /// Mientras el usuario mueve el mapa no se le pisa lo que escribió a mano.
  bool _direccionEditadaAMano = false;

  /// Se llama en initState. Sin [centroInicial] se intenta partir desde el GPS.
  void iniciarArea({
    required List<int> radiosPermitidos,
    LatLng? centroInicial,
    int? radioInicial,
    String? direccion,
  }) {
    radios = radiosPermitidos.isEmpty ? radiosPorDefecto : radiosPermitidos;
    centro = centroInicial ?? centroPorDefecto;
    // Si el radio guardado ya no está entre los permitidos, se usa el del medio.
    radio = radioInicial != null && radios.contains(radioInicial)
        ? radioInicial
        : radios[radios.length ~/ 2];
    direccionCtrl.text = direccion ?? '';
    if (centroInicial == null) usarUbicacionActual(silencioso: true);
  }

  /// Se llama en dispose.
  void liberarArea() {
    direccionCtrl.dispose();
    _controladorMapa.dispose();
  }

  /// Centra el mapa en el GPS. [silencioso] evita el aviso de error al abrir
  /// un área nueva: si no hay permiso, el usuario igual puede mover el mapa.
  Future<void> usarUbicacionActual({bool silencioso = false}) async {
    setState(() => buscandoUbicacion = true);
    try {
      final punto = await _ubicacionServicio.obtenerUbicacionActual();
      if (!mounted) return;
      setState(() => centro = punto);
      _ajustarMapa();
      _completarDireccion(punto);
    } on UbicacionServicioException catch (e) {
      if (!silencioso) mostrarAviso(context, e.mensaje);
    } catch (_) {
      if (!silencioso) mostrarAviso(context, 'No se pudo obtener tu ubicación');
    } finally {
      if (mounted) setState(() => buscandoUbicacion = false);
    }
  }

  /// Rellena la dirección con geocodificación inversa, salvo que el usuario
  /// ya haya escrito la suya.
  Future<void> _completarDireccion(LatLng punto) async {
    if (_direccionEditadaAMano) return;
    final direccion = await _ubicacionServicio.obtenerDireccion(punto);
    if (!mounted || direccion == null || _direccionEditadaAMano) return;
    setState(() => direccionCtrl.text = direccion);
  }

  /// Lleva el mapa al punto y al zoom actuales. El move va después del frame
  /// porque el controlador no acepta órdenes mientras se está construyendo.
  void _ajustarMapa() {
    if (!_mapaListo) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapaListo) return;
      _controladorMapa.move(centro, zoomParaRadio(radio));
    });
  }

  Widget campoDireccion() {
    return CampoRotulado(
      rotulo: 'Dirección de referencia',
      campo: TextField(
        controller: direccionCtrl,
        maxLength: 255,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => _direccionEditadaAMano = true,
        decoration: const InputDecoration(
          hintText: 'Av. Presidente Ibáñez 1234',
          counterText: '',
          prefixIcon: Icon(Icons.place_outlined, color: RBColores.azul),
        ),
      ),
    );
  }

  /// [alcance] arma el texto bajo el slider a partir de los minutos a pie.
  Widget selectorRadio({required String titulo, required String Function(int minutos) alcance}) {
    return SelectorRadio(
      titulo: titulo,
      radios: radios,
      radio: radio,
      alcance: alcance(minutosCaminando(radio)),
      onCambio: (metros) {
        setState(() => radio = metros);
        _ajustarMapa();
      },
    );
  }

  Widget vistaPrevia({required Color color, required double opacidad, required IconData icono}) {
    return VistaPreviaArea(
      controlador: _controladorMapa,
      centro: centro,
      radio: radio,
      color: color,
      opacidad: opacidad,
      icono: icono,
      buscandoUbicacion: buscandoUbicacion,
      onListo: () {
        _mapaListo = true;
        _ajustarMapa();
      },
      onMovido: (punto) => setState(() => centro = punto),
      onSoltado: () => _completarDireccion(centro),
      onUsarUbicacion: () => usarUbicacionActual(),
    );
  }
}

/// Panel inferior del editor: título con botón de cerrar, contenido
/// desplazable y la barra "Descartar / Guardar".
class PanelEditorArea extends StatelessWidget {
  final String titulo;
  final String textoGuardar;
  final bool guardando;
  final VoidCallback onCerrar;
  final VoidCallback onGuardar;
  final List<Widget> children;

  const PanelEditorArea({
    super.key,
    required this.titulo,
    required this.textoGuardar,
    required this.guardando,
    required this.onCerrar,
    required this.onGuardar,
    required this.children,
  });

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
                        titulo,
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
                      onTap: guardando ? null : onCerrar,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                  children: children,
                ),
              ),
              _barraAcciones(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barraAcciones(BuildContext context) {
    final altoBoton = context.pantallaBaja || context.pantallaAngosta ? 52.0 : 60.0;
    final forma = RoundedRectangleBorder(borderRadius: BorderRadius.circular(RBRadios.tarjeta));
    return Container(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + MediaQuery.of(context).viewPadding.bottom),
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
                onPressed: guardando ? null : onCerrar,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  foregroundColor: RBColores.tinta,
                  shape: forma,
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
                onPressed: guardando ? null : onGuardar,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  backgroundColor: RBColores.verde,
                  disabledBackgroundColor: RBColores.verde.withValues(alpha: 0.6),
                  disabledForegroundColor: Colors.white,
                  shape: forma,
                ),
                child: guardando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(textoGuardar, style: const TextStyle(fontSize: 18)),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slider del radio del área. Se mueve por posiciones, no por metros: así
/// solo existen los valores que acepta el servidor.
class SelectorRadio extends StatelessWidget {
  final String titulo;
  final List<int> radios;
  final int radio;

  /// Texto bajo el slider que explica qué cubre el radio elegido.
  final String alcance;
  final ValueChanged<int> onCambio;

  const SelectorRadio({
    super.key,
    required this.titulo,
    required this.radios,
    required this.radio,
    required this.alcance,
    required this.onCambio,
  });

  @override
  Widget build(BuildContext context) {
    final indice = radios.indexOf(radio).clamp(0, radios.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(titulo, style: RBTexto.rotuloCampo)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: RBColores.verde50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                textoRadio(radio),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: RBColores.verde),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Slider(
          value: indice.toDouble(),
          min: 0,
          max: (radios.length - 1).toDouble(),
          divisions: radios.length - 1,
          onChanged: (valor) => onCambio(radios[valor.round()]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final metros in radios)
                Text(
                  textoRadio(metros),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: metros == radio ? FontWeight.w700 : FontWeight.w500,
                    color: metros == radio ? RBColores.verde : RBColores.texto2,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(alcance, style: const TextStyle(fontSize: 14, height: 1.4, color: RBColores.texto2)),
      ],
    );
  }
}

/// Mapa con el círculo del área. El punto queda fijo al centro: lo que se
/// mueve es el mapa.
class VistaPreviaArea extends StatelessWidget {
  final MapController controlador;
  final LatLng centro;
  final int radio;
  final Color color;

  /// Opacidad del relleno del círculo.
  final double opacidad;
  final IconData icono;
  final bool buscandoUbicacion;
  final VoidCallback onListo;

  /// El usuario arrastró el mapa: [punto] es el nuevo centro.
  final ValueChanged<LatLng> onMovido;

  /// El usuario soltó el mapa.
  final VoidCallback onSoltado;
  final VoidCallback onUsarUbicacion;

  const VistaPreviaArea({
    super.key,
    required this.controlador,
    required this.centro,
    required this.radio,
    required this.color,
    required this.opacidad,
    required this.icono,
    required this.buscandoUbicacion,
    required this.onListo,
    required this.onMovido,
    required this.onSoltado,
    required this.onUsarUbicacion,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(RBRadios.tarjeta + 4),
      child: SizedBox(
        height: context.altoRelativo(0.32, minimo: 180, maximo: 260),
        child: Stack(
          children: [
            FlutterMap(
              mapController: controlador,
              options: MapOptions(
                initialCenter: centro,
                initialZoom: zoomParaRadio(radio),
                minZoom: 11,
                maxZoom: 18,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
                ),
                onMapReady: onListo,
                onPositionChanged: (posicion, hayGesto) {
                  if (hayGesto) onMovido(posicion.center);
                },
                onMapEvent: (evento) {
                  if (evento is MapEventMoveEnd) onSoltado();
                },
              ),
              children: [
                capaMapaBase(),
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: centro,
                      radius: radio.toDouble(),
                      useRadiusInMeter: true,
                      color: color.withValues(alpha: opacidad),
                      borderColor: color,
                      borderStrokeWidth: 2.5,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: centro,
                      width: 44,
                      height: 44,
                      child: MarcadorArea(color: color, icono: icono),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: buscandoUbicacion
                  ? const BotonCircular(icono: Icons.more_horiz_rounded, onTap: null, tamano: 46)
                  : BotonCircular(
                      icono: Icons.my_location_rounded,
                      color: RBColores.azul,
                      tamano: 46,
                      tooltip: 'Usar mi ubicación',
                      onTap: onUsarUbicacion,
                    ),
            ),
            const Positioned(left: 4, bottom: 2, child: AtribucionMapa()),
          ],
        ),
      ),
    );
  }
}

/// Círculo de color con un ícono blanco: el centro de un área en los mapas.
class MarcadorArea extends StatelessWidget {
  final Color color;
  final IconData icono;
  final double tamanoIcono;

  const MarcadorArea({super.key, required this.color, required this.icono, this.tamanoIcono = 20});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6)],
      ),
      child: Icon(icono, color: Colors.white, size: tamanoIcono),
    );
  }
}

/// Botón con borde punteado para agregar un área ("Crear grupo", "Añadir
/// ubicación"). Nunca se oculta: en el tope se ve gris y al tocarlo la
/// pantalla explica el motivo.
class BotonAgregarArea extends StatelessWidget {
  final String texto;
  final bool habilitado;
  final VoidCallback onTap;

  const BotonAgregarArea({super.key, required this.texto, required this.habilitado, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = habilitado ? RBColores.azul : RBColores.texto2;
    return CustomPaint(
      painter: const BordePunteado(color: RBColores.placeholder, radio: RBRadios.tarjeta + 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(RBRadios.tarjeta + 4),
          onTap: onTap,
          child: SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, color: color, size: 28),
                const SizedBox(width: 10),
                Text(texto, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
