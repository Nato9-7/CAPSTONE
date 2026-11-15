import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/grupo.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/vistas/grupos/widgets/chip_admin.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Tarjeta de un grupo en la lista: nombre, vecinos, área y última actividad.
class FilaGrupo extends StatelessWidget {
  final Grupo grupo;
  final VoidCallback onTap;

  const FilaGrupo({super.key, required this.grupo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final actividad = grupo.ultimoReporte == null
        ? 'Sin reportes todavía'
        : 'Último reporte ${tiempoRelativo(grupo.ultimoReporte)}';
    return TarjetaRB(
      onTap: onTap,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
      child: Row(
        children: [
          Container(
            width: context.escala(56),
            height: context.escala(56),
            decoration: BoxDecoration(
              color: RBColores.azul50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.groups_rounded, color: RBColores.azul, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  grupo.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: RBColores.tinta,
                  ),
                ),
                Text(
                  '${grupo.miembrosTexto} · ${grupo.radioLegible}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15.5, color: RBColores.texto2),
                ),
                const SizedBox(height: 2),
                Text(
                  actividad,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: RBColores.texto2),
                ),
              ],
            ),
          ),
          if (grupo.esAdmin) ...[
            const SizedBox(width: 8),
            const ChipAdmin(),
          ],
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: RBColores.placeholder, size: 26),
        ],
      ),
    );
  }
}
