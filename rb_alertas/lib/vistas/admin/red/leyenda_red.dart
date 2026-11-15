import 'package:flutter/material.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/lienzo_grafo.dart';

/// Qué significan los colores y grosores del lienzo, según la vista.
class LeyendaRed extends StatelessWidget {
  final String modo;
  final bool porComunidad;

  const LeyendaRed({super.key, required this.modo, required this.porComunidad});

  static const _nota = TextStyle(fontSize: 11, color: RBColores.texto2);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RBColores.linea),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: modo == 'zonas' && !porComunidad
            ? const [
                _Punto(colorAmbarRed, 'Lugar con pocos hechos'),
                _Punto(RBColores.rojo, 'Lugar con más hechos'),
                Text('Más grande = más hechos', style: _nota),
                SizedBox(height: 4),
                Text('Línea del color de la categoría;', style: _nota),
                Text('más gruesa = más hechos ahí', style: _nota),
              ]
            : porComunidad
            ? const [
                Text('Cada color es una comunidad', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                Text('(vecinos conectados entre sí)', style: _nota),
              ]
            : const [
                _Punto(RBColores.verde, 'Vecino confiable'),
                _Punto(colorAmbarRed, 'Dudoso'),
                _Punto(RBColores.rojo, 'Poco confiable o suspendido'),
                SizedBox(height: 4),
                _Linea(RBColores.verde, 'Confirma'),
                _Linea(RBColores.rojo, 'Desmiente'),
                _Linea(RBColores.azul, 'Creó'),
                _Linea(RBColores.petroleo, 'Grupo de vecinos'),
                Text('Más grueso = más veces', style: _nota),
              ],
      ),
    );
  }
}

/// Muestra de un nodo: círculo con borde del color indicado.
class _Punto extends StatelessWidget {
  final Color color;
  final String texto;

  const _Punto(this.color, this.texto);

  @override
  Widget build(BuildContext context) => _Fila(
    muestra: Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 2.5)),
    ),
    texto: texto,
  );
}

/// Muestra de una relación: trazo del color indicado.
class _Linea extends StatelessWidget {
  final Color color;
  final String texto;

  const _Linea(this.color, this.texto);

  @override
  Widget build(BuildContext context) =>
      _Fila(muestra: Container(width: 14, height: 3, color: color), texto: texto);
}

class _Fila extends StatelessWidget {
  final Widget muestra;
  final String texto;

  const _Fila({required this.muestra, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          muestra,
          const SizedBox(width: 6),
          Text(texto, style: const TextStyle(fontSize: 11.5, color: RBColores.tinta)),
        ],
      ),
    );
  }
}
