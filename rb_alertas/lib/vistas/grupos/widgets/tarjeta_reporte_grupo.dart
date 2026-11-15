import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/grupo.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Un reporte en el chat del grupo: quién lo compartió y cuándo, arriba, y la
/// tarjeta del incidente debajo, como un mensaje.
class TarjetaReporteGrupo extends StatelessWidget {
  final ReporteGrupo reporte;
  final VoidCallback onTap;

  const TarjetaReporteGrupo({super.key, required this.reporte, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final comentarios = reporte.totalComentarios == 1 ? '1 comentario' : '${reporte.totalComentarios} comentarios';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Row(
              children: [
                const AvatarSuricata(tamano: 26),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    reporte.esMio ? 'Tú' : reporte.autor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: RBColores.tinta),
                  ),
                ),
                Text(
                  ' · ${tiempoRelativo(reporte.fecha)}',
                  style: const TextStyle(fontSize: 14, color: RBColores.texto2),
                ),
              ],
            ),
          ),
          TarjetaRB(
            onTap: onTap,
            padding: const EdgeInsets.fromLTRB(16, 16, 14, 14),
            colorBorde: reporte.esMio ? RBColores.verde50 : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconoCategoria(
                  codigo: reporte.categoriaCodigo,
                  colorHex: reporte.colorHex,
                  tamano: context.escala(52),
                ),
                SizedBox(width: context.pantallaAngosta ? 12 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tituloReporte(reporte.categoria, reporte.direccion),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16.5,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                          color: RBColores.tinta,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        reporte.descripcion,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14.5, height: 1.35, color: RBColores.texto2),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ChipEstado(estado: EstadoVisual.desdeApi(reporte.estado)),
                          if (reporte.soloGrupo) const ChipSoloGrupo(),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.chat_bubble_outline_rounded, size: 16, color: RBColores.texto2),
                              const SizedBox(width: 4),
                              Text(comentarios, style: const TextStyle(fontSize: 14, color: RBColores.texto2)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: RBColores.placeholder, size: 26),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
