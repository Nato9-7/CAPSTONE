import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/reporte.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';

/// Grilla de categorías del incidente. Mientras carga muestra un indicador y,
/// si falla, el error con "Reintentar".
class SelectorCategoria extends StatelessWidget {
  /// null mientras se cargan.
  final List<CategoriaIncidente>? categorias;
  final String? error;
  final int? idSeleccionada;
  final ValueChanged<int> onSeleccionar;
  final VoidCallback onReintentar;

  const SelectorCategoria({
    super.key,
    required this.categorias,
    required this.error,
    required this.idSeleccionada,
    required this.onSeleccionar,
    required this.onReintentar,
  });

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Row(
        children: [
          Expanded(
            child: Text(error!, style: const TextStyle(fontSize: 14, color: RBColores.rojo)),
          ),
          TextButton(onPressed: onReintentar, child: const Text('Reintentar')),
        ],
      );
    }

    final categorias = this.categorias;
    if (categorias == null) {
      return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
    }

    // Las categorías vienen de la BD: la grilla se arma con las que existan.
    return LayoutBuilder(
      builder: (context, limites) {
        const separacion = 10.0;
        final columnas = limites.maxWidth >= 330 ? 4 : 3;
        final ancho = (limites.maxWidth - separacion * (columnas - 1)) / columnas;
        return Wrap(
          spacing: separacion,
          runSpacing: separacion,
          children: [
            for (final categoria in categorias)
              SizedBox(
                width: ancho,
                child: _TarjetaCategoria(
                  categoria: categoria,
                  ancho: ancho,
                  activa: categoria.id == idSeleccionada,
                  onTap: () => onSeleccionar(categoria.id),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TarjetaCategoria extends StatelessWidget {
  final CategoriaIncidente categoria;
  final double ancho;
  final bool activa;
  final VoidCallback onTap;

  const _TarjetaCategoria({
    required this.categoria,
    required this.ancho,
    required this.activa,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icono = (ancho * 0.5).clamp(34.0, 44.0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: activa ? RBColores.azul50 : Colors.white,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Container(
              // Ocupa todo el ancho de su columna.
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: activa ? RBColores.azul : RBColores.linea,
                  width: activa ? 2.2 : 1.2,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconoCategoria(codigo: categoria.codigo, colorHex: categoria.colorHex, tamano: icono),
                  const SizedBox(height: 8),
                  // El nombre se achica antes que cortarse ("Sospechoso").
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      nombreCortoCategoria(categoria.codigo, categoria.nombre),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: activa ? FontWeight.w800 : FontWeight.w600,
                        color: activa ? RBColores.azul : RBColores.tinta,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (activa)
          Positioned(
            top: -6,
            right: -6,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: RBColores.azul,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
              ),
              child: const Icon(Icons.check_rounded, size: 15, color: Colors.white),
            ),
          ),
      ],
    );
  }
}
