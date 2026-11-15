import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/reporte.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';

/// Etiqueta oscura sobre el pin seleccionado: "Accidente · 12 min".
class EtiquetaPin extends StatelessWidget {
  final ReporteMapa reporte;

  const EtiquetaPin({super.key, required this.reporte});

  @override
  Widget build(BuildContext context) {
    final tiempo = tiempoCorto(reporte.fechaCreacion);
    final nombre = nombreCortoCategoria(reporte.categoriaCodigo, reporte.categoria);
    // Varios vecinos reportaron lo mismo: se muestra como un solo incidente.
    final titulo = reporte.totalReportes > 1
        ? '$nombre · ${reporte.totalReportes} reportes'
        : nombre;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: RBColores.tinta,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        tiempo.isEmpty ? titulo : '$titulo · $tiempo',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
