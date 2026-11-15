import 'package:flutter/material.dart';
import 'package:rb_alertas/config/api_config.dart';
import 'package:rb_alertas/modelos/reporte.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/widgets/boton_voto.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Tarjeta inferior al tocar un pin: foto, categoría, título, descripción y
/// los votos. Al tocarla se abre el detalle completo.
class TarjetaVistaPrevia extends StatelessWidget {
  final ReporteMapa reporte;
  final DetalleReporte? detalle;
  final bool votando;
  final VoidCallback onCerrar;
  final VoidCallback onAbrir;
  final VoidCallback onComentarios;
  final void Function(DetalleReporte, TipoVoto) onVotar;

  /// Panel de administración: en vez de votar se modera el reporte.
  final VoidCallback? onModerar;

  const TarjetaVistaPrevia({
    super.key,
    required this.reporte,
    required this.detalle,
    required this.votando,
    required this.onCerrar,
    required this.onAbrir,
    required this.onComentarios,
    required this.onVotar,
    this.onModerar,
  });

  @override
  Widget build(BuildContext context) {
    final color = colorCategoria(reporte.categoriaCodigo, colorHex: reporte.colorHex);
    final d = detalle;
    final imagen = d != null && d.imagenes.isNotEmpty ? d.imagenes.first : null;
    final esVideo = imagen != null &&
        ['.mp4', '.mov', '.webm'].any((ext) => imagen.toLowerCase().endsWith(ext));
    final tiempo = tiempoCorto(reporte.fechaCreacion);
    final angosta = MediaQuery.sizeOf(context).width < 380;
    final foto = angosta ? 80.0 : 104.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: RBColores.azul.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(26),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onAbrir,
          child: Padding(
            padding: EdgeInsets.all(angosta ? 12 : 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SizedBox(
                        width: foto,
                        height: foto,
                        child: imagen != null && !esVideo
                            ? Image.network(
                                ApiConfig.urlArchivo(imagen),
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => _sinFoto(color),
                              )
                            : _sinFoto(color, video: esVideo),
                      ),
                    ),
                    SizedBox(width: angosta ? 10 : 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(iconoCategoria(reporte.categoriaCodigo), size: 16, color: color),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          tiempo.isEmpty
                                              ? nombreCortoCategoria(reporte.categoriaCodigo, reporte.categoria)
                                              : '${nombreCortoCategoria(reporte.categoriaCodigo, reporte.categoria)} · $tiempo',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: color,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: onCerrar,
                                customBorder: const CircleBorder(),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: const BoxDecoration(
                                    color: RBColores.fondo,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close_rounded, size: 20, color: RBColores.tinta),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tituloReporte(reporte.categoria, reporte.direccion),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                              color: RBColores.tinta,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            reporte.descripcion,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14.5, height: 1.35, color: RBColores.texto2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (onModerar != null)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: RBColores.rojo,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                        ),
                        onPressed: onModerar,
                        icon: const Icon(Icons.shield_outlined, size: 19),
                        label: const Text('Moderar'),
                      )
                    else if (d == null)
                      const SizedBox(
                        height: 48,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else ...[
                      BotonVoto(
                        icono: Icons.thumb_up_outlined,
                        iconoActivo: Icons.thumb_up_rounded,
                        cantidad: d.confirmaciones,
                        marcado: d.miVoto == TipoVoto.confirma,
                        positivo: true,
                        onTap: !d.esAutor && d.activo && !votando
                            ? () => onVotar(d, TipoVoto.confirma)
                            : null,
                      ),
                      const SizedBox(width: 10),
                      BotonVoto(
                        icono: Icons.thumb_down_outlined,
                        iconoActivo: Icons.thumb_down_rounded,
                        cantidad: d.desmentidos,
                        marcado: d.miVoto == TipoVoto.desmiente,
                        positivo: false,
                        onTap: !d.esAutor && d.activo && !votando
                            ? () => onVotar(d, TipoVoto.desmiente)
                            : null,
                      ),
                    ],
                    const Spacer(),
                    // Comentarios del reporte: abre el detalle ya en la conversación.
                    // El resto de la tarjeta abre el detalle desde arriba.
                    Material(
                      color: RBColores.azul,
                      borderRadius: BorderRadius.circular(24),
                      child: InkWell(
                        onTap: onComentarios,
                        borderRadius: BorderRadius.circular(24),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: angosta ? 14 : 20, vertical: 13),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                color: Colors.white,
                                size: 20,
                                semanticLabel: d == null
                                    ? 'Ver comentarios'
                                    : '${d.totalComentarios} comentarios',
                              ),
                              if (d != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '${d.totalComentarios}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sinFoto(Color color, {bool video = false}) {
    return CustomPaint(
      painter: const BordePunteado(color: RBColores.bordeCampo, radio: 18),
      child: Container(
        color: RBColores.azul50.withValues(alpha: 0.6),
        alignment: Alignment.center,
        child: Icon(
          video ? Icons.play_circle_outline_rounded : iconoCategoria(reporte.categoriaCodigo),
          size: 34,
          color: video ? RBColores.azul : color.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
