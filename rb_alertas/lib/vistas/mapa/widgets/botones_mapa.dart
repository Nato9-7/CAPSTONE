import 'package:flutter/material.dart';
import 'package:rb_alertas/tema/rb_tema.dart';

/// Botón flotante con ícono y texto ("Emergencias", "Reportar").
class BotonPildora extends StatelessWidget {
  final String texto;
  final IconData icono;
  final Color fondo;
  final Color color;
  final double alto;
  final VoidCallback onTap;

  const BotonPildora({
    super.key,
    required this.texto,
    required this.icono,
    required this.fondo,
    required this.color,
    required this.alto,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(23),
        boxShadow: [
          BoxShadow(
            color: (fondo == Colors.white ? RBColores.azul : fondo).withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: fondo,
        borderRadius: BorderRadius.circular(23),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(23),
          child: Container(
            height: alto,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icono, color: color, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    texto,
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón flotante cuadrado (centrar en mi ubicación).
class BotonCuadrado extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double tamano;

  const BotonCuadrado({super.key, required this.child, required this.onTap, required this.tamano});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: RBColores.azul.withValues(alpha: 0.16),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(width: tamano, height: tamano, child: Center(child: child)),
        ),
      ),
    );
  }
}
