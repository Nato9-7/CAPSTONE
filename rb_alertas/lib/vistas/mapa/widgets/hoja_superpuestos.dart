import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/reporte.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Lista de los reportes que están en el mismo punto. Devuelve el reporte
/// elegido, o null si se cierra sin elegir.
Future<ReporteMapa?> elegirReporteSuperpuesto(BuildContext context, List<ReporteMapa> reportes) {
  // El más reciente primero.
  final ordenados = [...reportes]
    ..sort((a, b) => (b.fechaCreacion ?? DateTime(0)).compareTo(a.fechaCreacion ?? DateTime(0)));
  return showModalBottomSheet<ReporteMapa>(
    context: context,
    isScrollControlled: true,
    builder: (hoja) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(hoja).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text('${reportes.length} reportes en este lugar', style: RBTexto.titulo),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Elige uno para ver su detalle',
                style: TextStyle(fontSize: 14, color: RBColores.texto2),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                children: [
                  for (final r in ordenados)
                    FilaIncidente(
                      codigoCategoria: r.categoriaCodigo,
                      colorHex: r.colorHex,
                      titulo: tituloReporte(r.categoria, r.direccion),
                      detalle: tiempoRelativoInicio(r.fechaCreacion),
                      estado: EstadoVisual.desdeApi(r.estado),
                      contador: r.totalReportes > 1 ? '${r.totalReportes} reportes' : null,
                      onTap: () => Navigator.pop(hoja, r),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
