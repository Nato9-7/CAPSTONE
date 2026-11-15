import 'package:flutter/material.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';

/// Grupo de reportes cercanos: círculo con la cantidad, del color de la
/// categoría que más se repite, y un halo que lo distingue de un pin suelto.
class PinGrupo extends StatelessWidget {
  final int cantidad;
  final String codigoCategoria;
  final String? colorHex;

  const PinGrupo({super.key, required this.cantidad, required this.codigoCategoria, this.colorHex});

  @override
  Widget build(BuildContext context) {
    final color = colorCategoria(codigoCategoria, colorHex: colorHex);
    return Semantics(
      button: true,
      label: '$cantidad reportes en esta zona',
      child: Center(
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.25), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3)),
              ],
            ),
            child: Text(
              cantidad > 99 ? '99+' : '$cantidad',
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }
}
