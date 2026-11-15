import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/zona_segura.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Tarjeta de una zona en la lista: ícono del tipo, nombre, dirección y radio.
class FilaZona extends StatelessWidget {
  final ZonaSegura zona;
  final VoidCallback onTap;

  const FilaZona({super.key, required this.zona, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final direccion = zona.direccion?.trim();
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
              color: RBColores.verde50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(zona.tipo.icono, color: RBColores.verde, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  zona.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: RBColores.tinta),
                ),
                if (direccion != null && direccion.isNotEmpty)
                  Text(
                    direccion,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15.5, color: RBColores.texto2),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: RBColores.verde50,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              zona.radioTexto,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: RBColores.verde),
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: RBColores.placeholder, size: 26),
        ],
      ),
    );
  }
}
