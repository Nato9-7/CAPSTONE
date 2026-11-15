import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:rb_alertas/modelos/reporte.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Mapa fijo (sin gestos) centrado en el lugar del incidente.
class MapaDetalle extends StatelessWidget {
  final DetalleReporte detalle;

  const MapaDetalle({super.key, required this.detalle});

  @override
  Widget build(BuildContext context) {
    final punto = LatLng(detalle.latitud, detalle.longitud);
    return FlutterMap(
      options: MapOptions(
        initialCenter: punto,
        initialZoom: 16.5,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
      ),
      children: [
        capaMapaBase(),
        MarkerLayer(
          markers: [
            Marker(
              point: punto,
              width: 90,
              height: 90,
              child: PinIncidente(
                codigo: detalle.categoriaCodigo,
                colorHex: detalle.colorHex,
                seleccionado: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Categoría, estado, título, hora, distancia y dirección del reporte.
class EncabezadoDetalle extends StatelessWidget {
  final DetalleReporte detalle;

  /// Distancia desde el usuario; null si no dio permiso de ubicación.
  final double? distanciaMetros;

  const EncabezadoDetalle({super.key, required this.detalle, this.distanciaMetros});

  @override
  Widget build(BuildContext context) {
    final d = detalle;
    final color = colorCategoria(d.categoriaCodigo, colorHex: d.colorHex);
    final estado = EstadoVisual.desdeApi(d.estado);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(iconoCategoria(d.categoriaCodigo), size: 17, color: color),
                  const SizedBox(width: 6),
                  Text(
                    nombreCortoCategoria(d.categoriaCodigo, d.categoria),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color),
                  ),
                ],
              ),
            ),
            ChipEstado(
              estado: estado,
              grande: true,
              texto: estado == EstadoVisual.validada ? 'Validada por vecinos' : null,
            ),
            if (d.soloGrupo) const ChipSoloGrupo(grande: true),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          tituloReporte(d.categoria, d.direccion),
          style: TextStyle(
            fontFamily: RBFuentes.titulos,
            fontSize: context.escala(30),
            height: 1.15,
            fontWeight: FontWeight.w800,
            color: RBColores.azul,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 18,
          runSpacing: 6,
          children: [
            if (d.fechaCreacion != null)
              _Meta(Icons.schedule_rounded, tiempoRelativoInicio(d.fechaCreacion)),
            if (distanciaMetros != null)
              _Meta(Icons.place_outlined, 'A ${distanciaLegible(distanciaMetros!)} de ti'),
          ],
        ),
        if (d.direccion != null && d.direccion!.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          _Meta(Icons.signpost_outlined, d.direccion!),
        ],
      ],
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icono;
  final String texto;

  const _Meta(this.icono, this.texto);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 18, color: RBColores.texto2),
        const SizedBox(width: 6),
        Flexible(
          child: Text(texto, style: const TextStyle(fontSize: 15.5, color: RBColores.texto2)),
        ),
      ],
    );
  }
}

/// Autor del reporte. Aparece con un alias de suricata (lo arma la API):
/// su nombre real no se muestra por seguridad.
class AutorDetalle extends StatelessWidget {
  final DetalleReporte detalle;

  /// Abre la denuncia del reporte; null oculta la bandera.
  final VoidCallback? onDenunciar;

  const AutorDetalle({super.key, required this.detalle, this.onDenunciar});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const AvatarSuricata(tamano: 54),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detalle.autor,
                style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w700, color: RBColores.tinta),
              ),
              Text(
                detalle.esAutor
                    ? 'Tú reportaste este incidente · perfil anónimo'
                    : 'Autor del reporte · perfil anónimo',
                style: const TextStyle(fontSize: 14, color: RBColores.texto2),
              ),
            ],
          ),
        ),
        if (onDenunciar != null)
          IconButton(
            tooltip: 'Denunciar reporte',
            onPressed: onDenunciar,
            icon: const Icon(Icons.flag_outlined, color: RBColores.texto2),
          ),
      ],
    );
  }
}
