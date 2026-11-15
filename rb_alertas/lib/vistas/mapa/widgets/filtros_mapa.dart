import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/reporte.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';

/// Botón único de filtros. Muestra la categoría elegida para que se note que
/// el mapa está filtrado.
class BotonFiltrar extends StatelessWidget {
  final CategoriaIncidente? categoria;
  final bool abierto;
  final VoidCallback onTap;

  const BotonFiltrar({super.key, required this.categoria, required this.abierto, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final filtrado = categoria != null;
    final activo = abierto || filtrado;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: RBColores.azul.withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: activo ? RBColores.azul : Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 40,
            padding: const EdgeInsets.only(left: 12, right: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (filtrado)
                  IconoCategoria(codigo: categoria!.codigo, colorHex: categoria!.colorHex, tamano: 22)
                else
                  Icon(Icons.tune_rounded, size: 20, color: activo ? Colors.white : RBColores.azul),
                const SizedBox(width: 8),
                Text(
                  filtrado
                      ? etiquetaCortaCategoria(categoria!.codigo, categoria!.nombre)
                      : 'Filtrar',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: activo ? Colors.white : RBColores.azul,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  abierto ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 20,
                  color: activo ? Colors.white : RBColores.azul,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Panel que se despliega bajo "Filtrar" con todas las categorías a la vista,
/// en varias líneas, con chips compactos para no tapar el mapa.
class PanelFiltros extends StatelessWidget {
  final List<CategoriaIncidente> categorias;
  final String? codigoSeleccionado;
  final ValueChanged<String?> onSeleccionar;

  const PanelFiltros({
    super.key,
    required this.categorias,
    required this.codigoSeleccionado,
    required this.onSeleccionar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: RBColores.azul.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text('Mostrar en el mapa', style: RBTexto.etiqueta),
          ),
          if (categorias.isEmpty)
            const Padding(
              padding: EdgeInsets.all(4),
              child: Text(
                'No se pudieron cargar las categorías.',
                style: TextStyle(fontSize: 13, color: RBColores.texto2),
              ),
            ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(
                etiqueta: 'Todos',
                activo: codigoSeleccionado == null,
                onTap: () => onSeleccionar(null),
              ),
              for (final categoria in categorias)
                _chip(
                  etiqueta: etiquetaCortaCategoria(categoria.codigo, categoria.nombre),
                  activo: codigoSeleccionado == categoria.codigo,
                  onTap: () => onSeleccionar(categoria.codigo),
                  icono: IconoCategoria(
                    codigo: categoria.codigo,
                    colorHex: categoria.colorHex,
                    tamano: 20,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String etiqueta,
    required bool activo,
    required VoidCallback onTap,
    Widget? icono,
  }) {
    return Material(
      color: activo ? RBColores.azul : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: activo ? RBColores.azul : RBColores.linea),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (activo && icono == null) ...[
                const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                const SizedBox(width: 4),
              ] else if (icono != null) ...[
                icono,
                const SizedBox(width: 6),
              ],
              Text(
                etiqueta,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: activo ? Colors.white : RBColores.tinta,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
