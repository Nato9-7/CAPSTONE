// Zonas de riesgo en el mapa: círculos donde se repiten robos o accidentes,
// su tarjeta con la recomendación y el aviso cuando el usuario está dentro.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rb_alertas/servicios/reporte_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';

const _ambar = Color(0xFFB45309);
const _ambarFondo = Color(0xFFFFF4E5);

/// Igual que tipo_riesgo() de la API: 'SEGURIDAD', 'VIAL' o null.
String? tipoRiesgoCategoria(String codigo) {
  final c = codigo.toUpperCase();
  const seguridad = ['ROBO', 'ASALTO', 'HURTO', 'SOSPECH', 'VANDAL', 'VIOLEN', 'RINA', 'DROGA', 'AGRESION'];
  const vial = ['ACCIDENTE', 'VIAL', 'CHOQUE', 'ATROPELL'];
  if (seguridad.any(c.contains)) return 'SEGURIDAD';
  if (vial.any(c.contains)) return 'VIAL';
  return null;
}

/// Rojo para seguridad de nivel alto, naranjo para el resto de seguridad y
/// ámbar para las zonas viales.
Color colorZona(ZonaRiesgo z) {
  if (!z.esSeguridad) return _ambar;
  return z.esAlto ? RBColores.rojo : const Color(0xFFD9480F);
}

IconData iconoZona(ZonaRiesgo z) =>
    z.esSeguridad ? Icons.gpp_maybe_rounded : Icons.car_crash_rounded;

String tituloZona(ZonaRiesgo z) {
  if (z.esSeguridad) return z.esAlto ? 'Zona de riesgo alto' : 'Zona de precaución';
  return 'Zona de riesgo vial';
}

bool zonaContiene(ZonaRiesgo z, LatLng punto) =>
    const Distance().as(LengthUnit.Meter, LatLng(z.latitud, z.longitud), punto) <= z.radioMetros;

/// Círculos en metros: crecen y se achican con el zoom como el resto del mapa.
CircleLayer capaZonasRiesgo(List<ZonaRiesgo> zonas) => CircleLayer(
      circles: [
        for (final z in zonas)
          CircleMarker(
            point: LatLng(z.latitud, z.longitud),
            radius: z.radioMetros,
            useRadiusInMeter: true,
            color: colorZona(z).withValues(alpha: z.esAlto ? 0.22 : 0.15),
            borderColor: colorZona(z).withValues(alpha: 0.75),
            borderStrokeWidth: 2,
          ),
      ],
    );

/// Insignia en el centro de la zona, para tocarla aunque el círculo sea chico.
Marker marcadorZona(ZonaRiesgo z, VoidCallback onTap) => Marker(
      point: LatLng(z.latitud, z.longitud),
      width: 34,
      height: 34,
      child: GestureDetector(
        onTap: onTap,
        child: Semantics(
          button: true,
          label: tituloZona(z),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: colorZona(z), width: 2.5),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6)],
            ),
            child: Icon(iconoZona(z), size: 19, color: colorZona(z)),
          ),
        ),
      ),
    );

/// "5 robos" / "2 accidentes y 1 problema en la vía".
String resumenCategoriasZona(ZonaRiesgo z) {
  String una(({String codigo, String nombre, String? colorHex, int total}) c) {
    final nombre = nombreCortoCategoria(c.codigo, c.nombre).toLowerCase();
    if (c.total == 1) return '1 $nombre';
    final plural = nombre.endsWith('l') || nombre.endsWith('n') ? '${nombre}es' : '${nombre}s';
    return '${c.total} $plural';
  }

  final partes = z.porCategoria.map(una).toList();
  if (partes.length <= 1) return partes.join();
  return '${partes.sublist(0, partes.length - 1).join(', ')} y ${partes.last}';
}

/// Botón junto a "Filtrar" para mostrar u ocultar las zonas.
class BotonZonasRiesgo extends StatelessWidget {
  final bool activo;
  final int cantidad;
  final VoidCallback onTap;

  const BotonZonasRiesgo({super.key, required this.activo, required this.cantidad, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = activo ? Colors.white : RBColores.rojo;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: RBColores.azul.withValues(alpha: 0.14), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Material(
        color: activo ? RBColores.rojo : Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.gpp_maybe_rounded, size: 20, color: color),
                const SizedBox(width: 6),
                Text(
                  cantidad > 0 && activo ? 'Zonas de riesgo · $cantidad' : 'Zonas de riesgo',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Panel: deja el mapa de calor a la vista a cualquier zoom.
class BotonMapaCalor extends StatelessWidget {
  final bool activo;
  final VoidCallback onTap;

  const BotonMapaCalor({super.key, required this.activo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const naranjo = Color(0xFFEA580C);
    final color = activo ? Colors.white : naranjo;
    return Material(
      color: activo ? naranjo : Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      shadowColor: RBColores.azul.withValues(alpha: 0.3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.blur_on_rounded, size: 20, color: color),
              const SizedBox(width: 6),
              Text('Mapa de calor', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aviso arriba del mapa cuando la ubicación del usuario cae en una zona.
class AvisoZonaRiesgo extends StatelessWidget {
  final ZonaRiesgo zona;
  final VoidCallback onTap;

  const AvisoZonaRiesgo({super.key, required this.zona, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = colorZona(zona);
    return Material(
      color: zona.esSeguridad ? RBColores.rojo50 : _ambarFondo,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(iconoZona(zona), color: color, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: zona.esSeguridad ? 'Estás en una zona con robos frecuentes. ' : 'Estás en una zona con accidentes frecuentes. ',
                      style: TextStyle(fontWeight: FontWeight.w800, color: color),
                    ),
                    TextSpan(
                      text: zona.esSeguridad ? 'Toca para ver cómo cuidarte.' : 'Toca para ver más.',
                      style: const TextStyle(color: RBColores.tinta),
                    ),
                  ]),
                  style: const TextStyle(fontSize: 13.5, height: 1.3),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: RBColores.texto2),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta inferior de una zona: qué pasa ahí y qué se recomienda.
class TarjetaZonaRiesgo extends StatelessWidget {
  final ZonaRiesgo zona;
  final int dias;
  final VoidCallback onCerrar;

  /// Interruptor "Avisarme al pasar por zonas de riesgo"; sin él no se muestra.
  final ValueListenable<bool?>? avisoActivo;
  final ValueChanged<bool>? onCambiarAviso;

  const TarjetaZonaRiesgo({
    super.key,
    required this.zona,
    required this.dias,
    required this.onCerrar,
    this.avisoActivo,
    this.onCambiarAviso,
  });

  @override
  Widget build(BuildContext context) {
    final color = colorZona(zona);
    final ultimo = zona.ultimoIncidente;
    final hace = ultimo == null ? null : DateTime.now().difference(ultimo).inDays;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(color: RBColores.azul.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 8)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(iconoZona(zona), color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tituloZona(zona),
                        style: RBTexto.titulo.copyWith(fontSize: 18, color: color),
                      ),
                      Text(
                        '${resumenCategoriasZona(zona)} en los últimos $dias días',
                        style: const TextStyle(fontSize: 13.5, color: RBColores.texto2),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: onCerrar,
                  icon: const Icon(Icons.close_rounded, color: RBColores.texto2),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: zona.esSeguridad ? RBColores.rojo50 : _ambarFondo,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.directions_walk_rounded, size: 20, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        zona.recomendacion,
                        style: const TextStyle(fontSize: 14, height: 1.35, color: RBColores.tinta, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                if (zona.incidentesDeNoche > 0)
                  _dato(Icons.nightlight_round, '${zona.incidentesDeNoche} de ${zona.totalIncidentes} de noche'),
                if (hace != null) _dato(Icons.schedule_rounded, hace == 0 ? 'El último fue hoy' : 'El último hace $hace ${hace == 1 ? 'día' : 'días'}'),
              ],
            ),
            if (avisoActivo != null && onCambiarAviso != null)
              ValueListenableBuilder<bool?>(
                valueListenable: avisoActivo!,
                // Material propio: el fondo de la tarjeta taparía el toque.
                builder: (context, activo, _) => Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.only(right: 8),
                    dense: true,
                    value: activo == true,
                    onChanged: onCambiarAviso,
                    secondary: const Icon(Icons.notifications_active_outlined, color: RBColores.texto2),
                    title: const Text(
                      'Avisarme al pasar por zonas de riesgo',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: RBColores.tinta),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _dato(IconData icono, String texto) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 15, color: RBColores.texto2),
          const SizedBox(width: 4),
          Text(texto, style: const TextStyle(fontSize: 12.5, color: RBColores.texto2)),
        ],
      );
}
