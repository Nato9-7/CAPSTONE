import 'package:flutter/material.dart';
import 'package:rb_alertas/config/api_config.dart';
import 'package:rb_alertas/modelos/reporte.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/widgets/boton_voto.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';
import 'package:url_launcher/url_launcher.dart';

/// Primera foto del reporte, o un acceso al video si la evidencia es un video.
class MediaDetalle extends StatelessWidget {
  final String url;

  const MediaDetalle({super.key, required this.url});

  bool get _esVideo {
    final u = url.toLowerCase();
    return u.endsWith('.mp4') || u.endsWith('.mov') || u.endsWith('.webm');
  }

  @override
  Widget build(BuildContext context) {
    final radio = BorderRadius.circular(RBRadios.tarjeta);

    if (_esVideo) {
      return Material(
        color: RBColores.azul50,
        borderRadius: radio,
        child: InkWell(
          borderRadius: radio,
          onTap: () => launchUrl(Uri.parse(ApiConfig.urlArchivo(url))),
          child: const SizedBox(
            height: 180,
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_circle_outline_rounded, size: 54, color: RBColores.azul),
                SizedBox(height: 6),
                Text('Ver video adjunto', style: TextStyle(fontWeight: FontWeight.w700, color: RBColores.azul)),
              ],
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: radio,
      child: Image.network(
        ApiConfig.urlArchivo(url),
        width: double.infinity,
        height: 220,
        fit: BoxFit.cover,
        loadingBuilder: (context, hijo, progreso) => progreso == null
            ? hijo
            : Container(
                height: 220,
                color: RBColores.azul50,
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
        errorBuilder: (context, error, pila) => Container(
          height: 160,
          color: RBColores.azul50,
          child: const Center(child: Icon(Icons.broken_image_outlined, size: 40, color: RBColores.texto2)),
        ),
      ),
    );
  }
}

/// Otros vecinos reportaron el mismo hecho: la API los junta en un solo
/// incidente (misma categoría, cerca y casi a la misma hora).
class MismoIncidente extends StatelessWidget {
  final DetalleReporte detalle;
  final void Function(int idReporte) onAbrir;

  const MismoIncidente({super.key, required this.detalle, required this.onAbrir});

  @override
  Widget build(BuildContext context) {
    final otros = detalle.reportesDelIncidente.where((r) => !r.esEste).toList();
    return TarjetaRB(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: RBColores.azul50, shape: BoxShape.circle),
                child: const Icon(Icons.groups_rounded, size: 20, color: RBColores.azul),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Lo reportaron ${detalle.reportesDelIncidente.length} vecinos',
                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: RBColores.tinta),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Es el mismo incidente: se muestra una sola vez en el mapa y no se '
            'repite la alerta a quien ya la recibió.',
            style: TextStyle(fontSize: 14, height: 1.4, color: RBColores.texto2),
          ),
          const SizedBox(height: 6),
          for (final r in otros) _FilaOtroReporte(reporte: r, onTap: () => onAbrir(r.id)),
        ],
      ),
    );
  }
}

class _FilaOtroReporte extends StatelessWidget {
  final ReporteDelIncidente reporte;
  final VoidCallback onTap;

  const _FilaOtroReporte({required this.reporte, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = reporte;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const AvatarSuricata(tamano: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [r.autor, if (r.fechaCreacion != null) tiempoRelativoInicio(r.fechaCreacion)].join(' · '),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: RBColores.tinta),
                  ),
                  if (r.descripcion.isNotEmpty)
                    Text(
                      r.descripcion,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, color: RBColores.texto2),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: RBColores.placeholder),
          ],
        ),
      ),
    );
  }
}

/// Confirmar o desmentir (CU-16). El autor no vota su propio reporte: ve
/// solo el recuento.
class VotosDetalle extends StatelessWidget {
  final DetalleReporte detalle;

  /// Mientras se registra un voto, los botones quedan deshabilitados.
  final bool votando;
  final void Function(TipoVoto voto) onVotar;

  const VotosDetalle({super.key, required this.detalle, required this.votando, required this.onVotar});

  @override
  Widget build(BuildContext context) {
    final d = detalle;
    final puedeVotar = d.esAutor == false && d.activo;
    final habilitado = puedeVotar && !votando;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '¿Es confiable este reporte?',
                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: RBColores.tinta),
              ),
            ),
            BotonVoto(
              icono: Icons.thumb_up_outlined,
              iconoActivo: Icons.thumb_up_rounded,
              cantidad: d.confirmaciones,
              marcado: d.miVoto == TipoVoto.confirma,
              positivo: true,
              onTap: habilitado ? () => onVotar(TipoVoto.confirma) : null,
            ),
            const SizedBox(width: 10),
            BotonVoto(
              icono: Icons.thumb_down_outlined,
              iconoActivo: Icons.thumb_down_rounded,
              cantidad: d.desmentidos,
              marcado: d.miVoto == TipoVoto.desmiente,
              positivo: false,
              onTap: habilitado ? () => onVotar(TipoVoto.desmiente) : null,
            ),
          ],
        ),
        if (!puedeVotar) ...[
          const SizedBox(height: 6),
          Text(
            d.esAutor ? 'Así responde la comunidad a tu reporte.' : 'Este reporte ya no admite votos.',
            style: const TextStyle(fontSize: 13.5, color: RBColores.texto2),
          ),
        ],
      ],
    );
  }
}

/// Botón del autor para marcar el reporte como resuelto. Si ya no está
/// vigente se muestra deshabilitado con el motivo.
class BotonResuelto extends StatelessWidget {
  final DetalleReporte detalle;
  final bool resolviendo;
  final VoidCallback onResolver;

  const BotonResuelto({super.key, required this.detalle, required this.resolviendo, required this.onResolver});

  @override
  Widget build(BuildContext context) {
    final resuelto = !detalle.activo;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton.icon(
        onPressed: resuelto || resolviendo ? null : onResolver,
        style: OutlinedButton.styleFrom(
          foregroundColor: RBColores.verde,
          disabledForegroundColor: RBColores.verde.withValues(alpha: 0.75),
          backgroundColor: RBColores.verde50,
          disabledBackgroundColor: RBColores.verde50,
          side: BorderSide(color: RBColores.verde.withValues(alpha: resuelto ? 0.35 : 0.7), width: 1.4),
        ),
        icon: resolviendo
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: RBColores.verde),
              )
            : const Icon(Icons.check_circle_outline_rounded, size: 22),
        label: Text(
          detalle.estado == 'RESUELTO'
              ? 'Incidente resuelto'
              : resuelto
                  ? 'Este reporte ya no está vigente'
                  : 'Marcar como resuelto',
        ),
      ),
    );
  }
}
