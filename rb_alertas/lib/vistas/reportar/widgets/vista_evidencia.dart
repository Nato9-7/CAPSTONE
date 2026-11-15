import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/reporte.dart';
import 'package:rb_alertas/tema/rb_tema.dart';

/// Foto adjunta (o el nombre del video) con el botón para quitarla.
class VistaEvidencia extends StatelessWidget {
  final Evidencia evidencia;
  final bool esVideo;
  final VoidCallback onQuitar;

  const VistaEvidencia({
    super.key,
    required this.evidencia,
    required this.esVideo,
    required this.onQuitar,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(RBRadios.tarjeta),
      child: SizedBox(
        width: double.infinity,
        height: 170,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (esVideo)
              Container(
                color: RBColores.azul50,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.videocam_outlined, color: RBColores.azul, size: 34),
                    const SizedBox(height: 6),
                    Text(
                      evidencia.nombreArchivo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, color: RBColores.tinta),
                    ),
                  ],
                ),
              )
            else
              Image.memory(evidencia.bytes, fit: BoxFit.cover),
            Positioned(
              top: 10,
              right: 10,
              child: Material(
                color: Colors.black.withValues(alpha: 0.55),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Quitar evidencia',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                  onPressed: onQuitar,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
