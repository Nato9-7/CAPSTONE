// Mapa de calor sobre flutter_map: cada celda con hechos se dibuja como una
// mancha difusa (amarillo -> naranjo -> rojo) que crece con su peso. Donde se
// juntan varias, el color se acumula y se pone más rojo.
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

  /// Radio de cada mancha en el terreno; con poco zoom nunca baja de
  /// [radioMinimoPx] para que se siga viendo.
  final double radioMetros;
  final double radioMinimoPx;

  const CapaCalor({super.key, required this.puntos, this.radioMetros = 170, this.radioMinimoPx = 22});

  @override
  Widget build(BuildContext context) {
    final camara = MapCamera.of(context);
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _PintorCalor(puntos, camara, radioMetros, radioMinimoPx),
      ),
    );
  }
}

class _PintorCalor extends CustomPainter {
  final List<PuntoCalor> puntos;
  final MapCamera camara;
  final double radioMetros;
  final double radioMinimoPx;

  _PintorCalor(this.puntos, this.camara, this.radioMetros, this.radioMinimoPx);

  @override
  void paint(Canvas canvas, Size size) {
    if (puntos.isEmpty) return;
    final maximo = puntos.map((p) => p.peso).reduce(math.max);
    final pantalla = Offset.zero & size;

    // Metros a píxeles con el zoom actual (se mide en el centro del mapa).
    final centro = camara.center;
    final borde = const Distance().offset(centro, radioMetros, 90);
    final radioBase = math.max(
      radioMinimoPx,
      (camara.getOffsetFromOrigin(borde) - camara.getOffsetFromOrigin(centro)).distance,
    );

    canvas.saveLayer(pantalla, Paint()..color = Colors.white.withValues(alpha: 0.9));
    // Primero los más suaves, para que los más intensos queden encima.
    for (final p in puntos.reversed) {
      final c = camara.getOffsetFromOrigin(LatLng(p.latitud, p.longitud));
      // Raíz: un lugar con 9 hechos no debe tapar con una mancha 9 veces mayor.
      final t = math.sqrt(p.peso / maximo);
      final r = radioBase * (0.85 + 0.9 * t);
      if (!pantalla.inflate(r).contains(c)) continue;
      _mancha(canvas, c, r * 1.35, _amarillo, 0.25 + 0.3 * t);
      _mancha(canvas, c, r, _naranjo, 0.15 + 0.45 * t);
      _mancha(canvas, c, r * 0.55, RBColores.rojo, 0.05 + 0.75 * t);
    }
    canvas.restore();
  }

  void _mancha(Canvas canvas, Offset centro, double radio, Color color, double alfa) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: alfa.clamp(0, 1)), color.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: centro, radius: radio));
    canvas.drawCircle(centro, radio, paint);
  }

  @override
  bool shouldRepaint(_PintorCalor viejo) =>
      viejo.puntos != puntos || viejo.camara != camara || viejo.radioMetros != radioMetros;
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
