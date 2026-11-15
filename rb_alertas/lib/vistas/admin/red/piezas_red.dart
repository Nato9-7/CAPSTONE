// Piezas visuales pequeñas que comparten la red, los hallazgos y el detalle.
import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/modelos.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/admin/red/filtros_red.dart';
import 'package:rb_alertas/vistas/admin/red/textos_red.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';
import 'package:rb_alertas/widgets/lienzo_grafo.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Rojo bajo 35, ámbar bajo 65 y verde desde ahí (puntaje de 0 a 100).
Color colorPuntajeRed(num puntaje) =>
    puntaje < 35 ? RBColores.rojo : (puntaje < 65 ? colorAmbarRed : RBColores.verde);

/// Cuadrado de color con el ícono del tipo de elemento.
class IconoNodoRed extends StatelessWidget {
  final NodoGrafo nodo;
  final double tamano;

  const IconoNodoRed(this.nodo, {super.key, required this.tamano});

  @override
  Widget build(BuildContext context) {
    final (icono, color) = estiloNodoRed(nodo);
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(tamano * 0.3)),
      child: Icon(icono, color: Colors.white, size: tamano * 0.55),
    );
  }
}

/// Píldora con el estado de un reporte o una cuenta.
class ChipEstadoRed extends StatelessWidget {
  final String estado;

  const ChipEstadoRed(this.estado, {super.key});

  @override
  Widget build(BuildContext context) {
    final (fondo, color) = switch (estado) {
      'ACTIVO' || 'RESUELTO' || 'VALIDADO' => (RBColores.verde50, RBColores.verde),
      'SUSPENDIDO' || 'DESCARTADO' => (RBColores.rojo50, RBColores.rojo),
      _ => (RBColores.azul50, RBColores.azul),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(20)),
      child: Text(
        textoEstadoRed(estado),
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

/// "Resolver" y "Descartar" de un incidente.
class BotonesIncidenteRed extends StatelessWidget {
  final int idIncidente;

  /// Recibe el id y el estado nuevo (RESUELTO o DESCARTADO).
  final void Function(int id, String estado) alModerar;

  const BotonesIncidenteRed({super.key, required this.idIncidente, required this.alModerar});

  @override
  Widget build(BuildContext context) {
    const relleno = EdgeInsets.symmetric(horizontal: 10, vertical: 14);
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: RBColores.verde, padding: relleno),
            onPressed: () => alModerar(idIncidente, 'RESUELTO'),
            child: const Text('Resolver', maxLines: 1),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: RBColores.rojo,
              side: const BorderSide(color: RBColores.rojo, width: 1.4),
              padding: relleno,
            ),
            onPressed: () => alModerar(idIncidente, 'DESCARTADO'),
            child: const Text('Descartar', maxLines: 1),
          ),
        ),
      ],
    );
  }
}

/// Chips "Todas", "Robos" y "Accidentes". Se usa en la barra, en la hoja de
/// filtros del celular y arriba del ranking de zonas.
class FiltroCategoriasRed extends StatelessWidget {
  final String? categoria;
  final List<CategoriaIncidente> disponibles;
  final ValueChanged<String?> alElegir;

  const FiltroCategoriasRed({
    super.key,
    required this.categoria,
    required this.disponibles,
    required this.alElegir,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ChipFiltro(etiqueta: 'Todas', activo: categoria == null, onTap: () => alElegir(null)),
        for (final c in disponibles)
          if (categoriasFiltrablesRed.contains(c.codigo.toUpperCase()))
            ChipFiltro(
              etiqueta: etiquetaCortaCategoria(c.codigo, c.nombre),
              icono: Icon(
                iconoCategoria(c.codigo),
                size: 16,
                color: categoria == c.codigo ? Colors.white : colorCategoria(c.codigo, colorHex: c.colorHex),
              ),
              activo: categoria == c.codigo,
              onTap: () => alElegir(c.codigo),
            ),
      ],
    );
  }
}

/// "¿Por qué?": los votos exactos que hacen sospechoso al grupo.
class EvidenciaSospechosoRed extends StatelessWidget {
  final GrupoSospechoso grupo;

  const EvidenciaSospechosoRed(this.grupo, {super.key});

  @override
  Widget build(BuildContext context) {
    final g = grupo;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: RBColores.rojo50, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dieron ${g.confirmacionesInternas} confirmaciones entre ellas y '
            '${g.confirmacionesAfuera} a otros vecinos:',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: RBColores.tinta),
          ),
          const SizedBox(height: 6),
          for (final e in g.evidencia.take(8))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_rounded, size: 15, color: RBColores.verde),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${e.votante} confirmó el reporte #${e.reporte} (${e.categoria}) de ${e.autor}',
                      style: const TextStyle(fontSize: 12.5, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          if (g.evidencia.length > 8)
            Text('… y ${g.evidencia.length - 8} más', style: const TextStyle(fontSize: 12.5, color: RBColores.texto2)),
        ],
      ),
    );
  }
}

/// Franja sobre el lienzo con lo que se está resaltando y un botón para quitarla.
class AvisoSobreRed extends StatelessWidget {
  final IconData icono;
  final String texto;
  final VoidCallback alCerrar;
  final Color color;

  const AvisoSobreRed({
    super.key,
    required this.icono,
    required this.texto,
    required this.alCerrar,
    this.color = RBColores.tinta,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(14),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  texto,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Quitar',
                visualDensity: VisualDensity.compact,
                onPressed: alCerrar,
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botón redondo sobre el lienzo (encuadrar, colorear, leyenda).
class BotonFlotanteRed extends StatelessWidget {
  final IconData icono;
  final String ayuda;
  final VoidCallback alTocar;
  final bool activo;

  const BotonFlotanteRed({
    super.key,
    required this.icono,
    required this.ayuda,
    required this.alTocar,
    this.activo = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: ayuda,
      child: Material(
        color: activo ? RBColores.azul : Colors.white,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: alTocar,
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Icon(icono, size: 22, color: activo ? Colors.white : RBColores.azul),
          ),
        ),
      ),
    );
  }
}
