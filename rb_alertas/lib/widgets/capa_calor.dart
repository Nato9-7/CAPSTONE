// Mapa de calor sobre flutter_map, solo de robos y accidentes de tránsito.
// La API ya junta los hechos cercanos: cada punto es una sola mancha difusa
// (amarillo -> naranjo -> rojo) que se agranda y enrojece con cuántos hechos
// se juntaron ahí, en vez de dibujar cada hecho disperso.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rb_alertas/servicios/reporte_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';

const _amarillo = Color(0xFFF59E0B);
const _naranjo = Color(0xFFEA580C);

class CapaCalor extends StatelessWidget {
  final List<PuntoCalor> puntos;

  /// Con poco zoom la mancha nunca baja de [radioMinimoPx] para que se vea.
  final double radioMinimoPx;

  const CapaCalor({super.key, required this.puntos, this.radioMinimoPx = 22});

  @override
  Widget build(BuildContext context) {
    final camara = MapCamera.of(context);
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _PintorCalor(puntos, camara, radioMinimoPx),
      ),
    );
  }
}

class _PintorCalor extends CustomPainter {
  final List<PuntoCalor> puntos;
  final MapCamera camara;
  final double radioMinimoPx;

  _PintorCalor(this.puntos, this.camara, this.radioMinimoPx);

  @override
  void paint(Canvas canvas, Size size) {
    if (puntos.isEmpty) return;
    final maximo = puntos.map((p) => p.peso).reduce(math.max);
    final pantalla = Offset.zero & size;

    canvas.saveLayer(pantalla, Paint()..color = Colors.white.withValues(alpha: 0.9));
    // Primero las más chicas, para que las más intensas queden encima.
    for (final p in puntos.reversed) {
      final punto = LatLng(p.latitud, p.longitud);
      final c = camara.getOffsetFromOrigin(punto);
      // Metros a píxeles con el zoom actual, en el lugar de la mancha.
      final borde = const Distance().offset(punto, p.radioMetros, 90);
      final r = math.max(radioMinimoPx, (camara.getOffsetFromOrigin(borde) - c).distance);
      if (!pantalla.inflate(r).contains(c)) continue;
      // Raíz: un lugar con 9 hechos no debe ser 9 veces más rojo.
      final t = math.sqrt(p.peso / maximo);
      _mancha(canvas, c, r, t);
    }
    canvas.restore();
  }

  /// Una sola mancha: centro rojo, borde naranjo y amarillo que se desvanece.
  void _mancha(Canvas canvas, Offset centro, double radio, double t) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          RBColores.rojo.withValues(alpha: (0.35 + 0.5 * t).clamp(0, 1)),
          _naranjo.withValues(alpha: (0.3 + 0.35 * t).clamp(0, 1)),
          _amarillo.withValues(alpha: (0.2 + 0.25 * t).clamp(0, 1)),
          _amarillo.withValues(alpha: 0),
        ],
        stops: const [0, 0.4, 0.75, 1],
      ).createShader(Rect.fromCircle(center: centro, radius: radio));
    canvas.drawCircle(centro, radio, paint);
  }

  @override
  bool shouldRepaint(_PintorCalor viejo) => viejo.puntos != puntos || viejo.camara != camara;
}

/// Leyenda chica: de amarillo (pocos) a rojo (muchos).
class LeyendaCalor extends StatelessWidget {
  final String texto;

  const LeyendaCalor({super.key, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: RBColores.azul.withValues(alpha: 0.12), blurRadius: 8)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(texto, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: RBColores.tinta)),
          const SizedBox(height: 5),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Pocos', style: TextStyle(fontSize: 11, color: RBColores.texto2)),
              const SizedBox(width: 6),
              Container(
                width: 90,
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: const LinearGradient(colors: [_amarillo, _naranjo, RBColores.rojo]),
                ),
              ),
              const SizedBox(width: 6),
              const Text('Muchos', style: TextStyle(fontSize: 11, color: RBColores.texto2)),
            ],
          ),
        ],
      ),
    );
  }
}
