import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/grupo.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Grupos del usuario que contienen el lugar del incidente: se eligen en
/// cuáles compartir el reporte y si queda solo para ellos.
class SeccionGrupos extends StatelessWidget {
  final List<GrupoEnPunto> grupos;
  final Set<int> elegidos;
  final bool soloGrupo;
  final ValueChanged<int> onAlternarGrupo;
  final ValueChanged<bool> onSoloGrupo;

  const SeccionGrupos({
    super.key,
    required this.grupos,
    required this.elegidos,
    required this.soloGrupo,
    required this.onAlternarGrupo,
    required this.onSoloGrupo,
  });

  @override
  Widget build(BuildContext context) {
    // Material y no Container con color: el SwitchListTile pinta su efecto
    // al tocarlo sobre el Material más cercano.
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RBRadios.tarjeta + 4),
        side: const BorderSide(color: RBColores.linea),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'El lugar está dentro de estos grupos. Elige dónde quieres que aparezca.',
              style: TextStyle(fontSize: 14.5, height: 1.4, color: RBColores.texto2),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final grupo in grupos)
                  ChipFiltro(
                    etiqueta: grupo.nombre,
                    activo: elegidos.contains(grupo.id),
                    conCheck: true,
                    icono: const Icon(Icons.groups_rounded, size: 19, color: RBColores.azul),
                    onTap: () => onAlternarGrupo(grupo.id),
                  ),
              ],
            ),
            // La opción de privacidad solo tiene sentido si hay un grupo elegido.
            if (elegidos.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Divider(color: RBColores.linea),
              SwitchListTile(
                value: soloGrupo,
                onChanged: onSoloGrupo,
                contentPadding: EdgeInsets.zero,
                activeThumbColor: Colors.white,
                activeTrackColor: RBColores.verde,
                secondary: const Icon(Icons.lock_outline_rounded, color: RBColores.azul),
                title: const Text(
                  'Solo para el grupo',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: RBColores.tinta),
                ),
                subtitle: Text(
                  soloGrupo
                      ? 'No aparecerá en el mapa ni avisará a otros vecinos de la zona.'
                      : 'También aparecerá en el mapa para toda la comunidad.',
                  style: const TextStyle(fontSize: 14, height: 1.35, color: RBColores.texto2),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
