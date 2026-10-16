import 'package:flutter/material.dart';
import 'package:rb_alertas/tema/rb_tema.dart';

/// Píldora de voto (pulgar arriba / abajo) con su contador. El voto propio se
/// resalta: verde para confirmar, rojo para desmentir.
class BotonVoto extends StatelessWidget {
  final IconData icono;
  final IconData iconoActivo;
  final int cantidad;
  final bool marcado;
  final bool positivo;
  final VoidCallback? onTap;

  const BotonVoto({
    super.key,
    required this.icono,
    required this.iconoActivo,
    required this.cantidad,
    required this.marcado,
    required this.positivo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final acento = positivo ? RBColores.verde : RBColores.rojo;
    final fondoMarcado = positivo ? RBColores.verde50 : RBColores.rojo50;
    final colorContenido = marcado ? acento : RBColores.tinta;

    return Material(
      color: marcado ? fondoMarcado : Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 46,
          padding: EdgeInsets.symmetric(horizontal: context.pantallaAngosta ? 12 : 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: marcado ? acento : RBColores.bordeCampo,
              width: marcado ? 1.6 : 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(marcado ? iconoActivo : icono, size: 22, color: colorContenido),
              const SizedBox(width: 8),
              Text(
                '$cantidad',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colorContenido,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
