import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rb_alertas/modelos/zona_segura.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/editor_area.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Mapa de solo lectura con todas las zonas del usuario y sus radios.
class MapaZonas extends StatelessWidget {
  final List<ZonaSegura> zonas;

  const MapaZonas({super.key, required this.zonas});

  @override
  Widget build(BuildContext context) {
    const sinGestos = InteractionOptions(flags: InteractiveFlag.none);
    final puntos = [for (final z in zonas) LatLng(z.latitud, z.longitud)];
    // Con varias zonas se encuadran todas; con una o ninguna, se centra.
    final opciones = puntos.length > 1
        ? MapOptions(
            initialCameraFit: CameraFit.coordinates(
              coordinates: puntos,
              padding: const EdgeInsets.all(60),
              maxZoom: 15,
            ),
            interactionOptions: sinGestos,
          )
        : MapOptions(
            initialCenter: puntos.isEmpty ? centroPorDefecto : puntos.first,
            initialZoom: 14,
            interactionOptions: sinGestos,
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(RBRadios.tarjeta + 4),
      child: SizedBox(
        height: context.altoRelativo(0.3, minimo: 170, maximo: 240),
        child: Stack(
          children: [
            FlutterMap(
              options: opciones,
              children: [
                capaMapaBase(),
                CircleLayer(
                  circles: [
                    for (final z in zonas)
                      CircleMarker(
                        point: LatLng(z.latitud, z.longitud),
                        radius: z.radioMetros.toDouble(),
                        useRadiusInMeter: true,
                        color: RBColores.verde.withValues(alpha: 0.15),
                        borderColor: RBColores.verde,
                        borderStrokeWidth: 2.5,
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    for (final z in zonas)
                      Marker(
                        point: LatLng(z.latitud, z.longitud),
                        width: 40,
                        height: 40,
                        child: MarcadorArea(color: RBColores.verde, icono: z.tipo.icono, tamanoIcono: 18),
                      ),
                  ],
                ),
              ],
            ),
            const Positioned(left: 6, bottom: 2, child: AtribucionMapa()),
          ],
        ),
      ),
    );
  }
}
