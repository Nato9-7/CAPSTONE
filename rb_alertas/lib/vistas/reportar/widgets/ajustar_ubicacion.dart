import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:rb_alertas/servicios/ubicacion_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Mapa grande para ajustar el punto del reporte: el pin queda fijo al
/// centro y lo que se mueve es el mapa.
class HojaAjustarUbicacion extends StatefulWidget {
  final LatLng inicial;
  final UbicacionServicio ubicacionServicio;

  const HojaAjustarUbicacion({super.key, required this.inicial, required this.ubicacionServicio});

  @override
  State<HojaAjustarUbicacion> createState() => _HojaAjustarUbicacionState();
}

class _HojaAjustarUbicacionState extends State<HojaAjustarUbicacion> {
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
