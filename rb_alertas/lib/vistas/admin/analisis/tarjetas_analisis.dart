// Tarjetas de la sección Análisis: calles con más hechos, sectores en el tiempo
// y la red de calles y categorías (Neo4j).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/modelos.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/vistas/admin/analisis/graficos_analisis.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';
import 'package:rb_alertas/widgets/lienzo_grafo.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Tarjeta con título, subtítulo explicativo y contenido.
class TarjetaAnalisis extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final Widget child;
  final Widget? accion;

  const TarjetaAnalisis({super.key, required this.titulo, required this.subtitulo, required this.child, this.accion});

  @override
  Widget build(BuildContext context) {
    return TarjetaRB(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        titulo,
                        style: const TextStyle(
                          fontFamily: RBFuentes.titulos,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: RBColores.azul,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitulo, style: const TextStyle(fontSize: 13, height: 1.35, color: RBColores.texto2)),
                  ],
                ),
              ),
              ?accion,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Texto gris centrado para una tarjeta sin datos.
class SinDatosAnalisis extends StatelessWidget {
  final String texto;

  const SinDatosAnalisis(this.texto, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Text(
      texto,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 14, color: RBColores.texto2),
    ),
  );
}

// -----------------------------------------------------------------------------
// Calles con más hechos

class TarjetaCalles extends StatelessWidget {
  final RankingCalles? ranking;
  final ValueChanged<CalleAnalisis>? alTocar;

  const TarjetaCalles({super.key, required this.ranking, this.alTocar});

  @override
  Widget build(BuildContext context) {
    final r = ranking;
    final maximo = r == null || r.calles.isEmpty ? 1 : r.calles.first.total;
    return TarjetaAnalisis(
      titulo: 'Calles con más hechos',
      subtitulo: 'Ordenadas por hechos del período. La etiqueta compara con el período anterior.',
      child: r == null
          ? const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator(color: RBColores.azul)),
            )
          : r.calles.isEmpty
          ? const SinDatosAnalisis('No hay hechos con calle identificada en este período.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, calle) in r.calles.indexed) ...[
                  if (i > 0) const Divider(height: 1, color: RBColores.linea),
                  _FilaCalle(posicion: i + 1, calle: calle, maximo: maximo, alTocar: alTocar),
                ],
                if (r.reportesSinCalle > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${r.reportesSinCalle} ${r.reportesSinCalle == 1 ? 'reporte no tiene' : 'reportes no tienen'} '
                    'calle identificada y no aparecen aquí.',
                    style: const TextStyle(fontSize: 12, color: RBColores.texto2),
                  ),
                ],
              ],
            ),
    );
  }
}

class _FilaCalle extends StatelessWidget {
  final int posicion;
  final CalleAnalisis calle;
  final int maximo;
  final ValueChanged<CalleAnalisis>? alTocar;

  const _FilaCalle({required this.posicion, required this.calle, required this.maximo, this.alTocar});

  @override
  Widget build(BuildContext context) {
    final principal = calle.porCategoria.firstOrNull?.categoria;
    final colorBarra = principal == null ? RBColores.azul : colorCategoria(principal.codigo, colorHex: principal.color);
    return InkWell(
      onTap: alTocar == null ? null : () => alTocar!(calle),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '$posicion',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: RBColores.texto2),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          calle.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: RBColores.tinta),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${calle.total}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: RBColores.tinta),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  BarraProporcion(fraccion: calle.total / maximo, color: colorBarra),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      InsigniaTendencia(tendencia: calle.tendencia, variacion: calle.variacion),
                      for (final c in calle.porCategoria.take(3))
                        _ChipCategoria(
                          nombre: c.categoria.nombre,
                          total: c.total,
                          codigo: c.categoria.codigo,
                          color: c.categoria.color,
                        ),
                      if (calle.comuna != null)
                        Text(calle.comuna!, style: const TextStyle(fontSize: 12, color: RBColores.texto2)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipCategoria extends StatelessWidget {
  final String nombre;
  final int total;
  final String codigo;
  final String? color;

  const _ChipCategoria({required this.nombre, required this.total, required this.codigo, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = colorCategoria(codigo, colorHex: color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconoCategoria(codigo), size: 13, color: c),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$nombre · $total',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: RBColores.tinta),
            ),
          ),
        ],
      ),
    );
  }
}

/// Detalle de una calle (al tocarla en el ranking).
Future<void> mostrarDetalleCalle(BuildContext context, CalleAnalisis calle, int dias) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              calle.nombre,
              style: const TextStyle(
                fontFamily: RBFuentes.titulos,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: RBColores.azul,
              ),
            ),
            if (calle.comuna != null) Text(calle.comuna!, style: const TextStyle(color: RBColores.texto2)),
            const SizedBox(height: 14),
            Text(
              '${calle.total} ${calle.total == 1 ? 'hecho' : 'hechos'} en los últimos $dias días '
              '(${calle.reportes} ${calle.reportes == 1 ? 'reporte' : 'reportes'}); '
              '${calle.anterior} en los $dias días anteriores.',
              style: const TextStyle(fontSize: 14, height: 1.4, color: RBColores.tinta),
            ),
            if (calle.ultimo != null) ...[
              const SizedBox(height: 4),
              Text(
                'Último hecho: ${fechaHora(calle.ultimo)}',
                style: const TextStyle(fontSize: 13, color: RBColores.texto2),
              ),
            ],
            const SizedBox(height: 14),
            for (final c in calle.porCategoria)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    IconoCategoria(codigo: c.categoria.codigo, colorHex: c.categoria.color, tamano: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(c.categoria.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Text('${c.total}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
// Sectores en el tiempo

class TarjetaSectores extends StatelessWidget {
  final SectoresEnElTiempo? datos;

  const TarjetaSectores({super.key, required this.datos});

  @override
  Widget build(BuildContext context) {
    final d = datos;
    return TarjetaAnalisis(
      titulo: 'Sectores en el tiempo',
      subtitulo: 'Cómo se repartieron los hechos de cada sector en el período y si van en alza.',
      child: d == null
          ? const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator(color: RBColores.azul)),
            )
          : d.sectores.isEmpty
          ? const SinDatosAnalisis('No hay hechos en este período.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in [Tendencia.nueva, Tendencia.sube, Tendencia.baja, Tendencia.igual])
                      _ContadorTendencia(tendencia: t, total: d.resumen[t] ?? 0),
                  ],
                ),
                if (d.tramos.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Serie de ${diaCorto(d.tramos.first.desde)} a ${diaCorto(d.tramos.last.hasta)}, '
                    'en ${d.tramos.length} tramos.',
                    style: const TextStyle(fontSize: 12, color: RBColores.texto2),
                  ),
                ],
                const SizedBox(height: 6),
                for (final (i, s) in d.sectores.indexed) ...[
                  if (i > 0) const Divider(height: 1, color: RBColores.linea),
                  _FilaSector(sector: s),
                ],
              ],
            ),
    );
  }
}

class _ContadorTendencia extends StatelessWidget {
  final Tendencia tendencia;
  final int total;

  const _ContadorTendencia({required this.tendencia, required this.total});

  @override
  Widget build(BuildContext context) {
    final (_, color, icono) = estiloTendencia(tendencia, null);
    final etiqueta = switch (tendencia) {
      Tendencia.nueva => total == 1 ? 'nuevo' : 'nuevos',
      Tendencia.sube => 'en alza',
      Tendencia.baja => 'a la baja',
      Tendencia.igual => total == 1 ? 'estable' : 'estables',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: RBColores.fondo, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '$total $etiqueta',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: RBColores.tinta),
          ),
        ],
      ),
    );
  }
}

class _FilaSector extends StatelessWidget {
  final SectorAnalisis sector;

  const _FilaSector({required this.sector});

  @override
  Widget build(BuildContext context) {
    final (_, color, _) = estiloTendencia(sector.tendencia, sector.variacion);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sector.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: RBColores.tinta),
                ),
                const SizedBox(height: 4),
                Text(
                  '${sector.total} ahora · ${sector.anterior} antes'
                  '${sector.comuna != null && sector.comuna != sector.nombre ? ' · ${sector.comuna}' : ''}',
                  style: const TextStyle(fontSize: 12.5, color: RBColores.texto2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          MiniSerie(
            serie: sector.serie,
            color: sector.tendencia == Tendencia.igual ? RBColores.azul : color,
            ancho: MediaQuery.sizeOf(context).width < 400 ? 56 : 88,
          ),
          const SizedBox(width: 10),
          InsigniaTendencia(tendencia: sector.tendencia, variacion: sector.variacion),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Red de calles y categorías

class TarjetaRedLugares extends StatefulWidget {
  final RedGrafo? red;
  final String nivel;
  final ValueChanged<String> alCambiarNivel;

  const TarjetaRedLugares({super.key, required this.red, required this.nivel, required this.alCambiarNivel});

  @override
  State<TarjetaRedLugares> createState() => _TarjetaRedLugaresState();
}

class _TarjetaRedLugaresState extends State<TarjetaRedLugares> {
  final _controlador = ControladorLienzo();
  NodoGrafo? _seleccion;

  @override
  void didUpdateWidget(TarjetaRedLugares viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.red != widget.red) _seleccion = null;
  }

  /// Categorías (o lugares) conectados al nodo elegido, con cuántos hechos.
  List<(NodoGrafo, int)> _conexiones(RedGrafo red, NodoGrafo nodo) {
    final porClave = {for (final n in red.nodos) n.clave: n};
    final lista = <(NodoGrafo, int)>[];
    for (final a in red.aristas) {
      final otro = a.origen == nodo.clave ? a.destino : (a.destino == nodo.clave ? a.origen : null);
      final n = otro == null ? null : porClave[otro];
      if (n != null) lista.add((n, (a.datos['peso'] as num?)?.toInt() ?? 0));
    }
    return lista..sort((a, b) => b.$2.compareTo(a.$2));
  }

  @override
  Widget build(BuildContext context) {
    final red = widget.red;
    final alto = math.min(MediaQuery.sizeOf(context).height * 0.55, 440.0);
    return TarjetaAnalisis(
      titulo: 'Red de lugares y categorías',
      subtitulo:
          'Cada lugar se une a lo que pasó ahí. Nodo más grande = más hechos; '
          'línea más gruesa = más hechos de esa categoría.',
      accion: SegmentedButton<String>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment(value: 'calle', label: Text('Calles')),
          ButtonSegment(value: 'sector', label: Text('Sectores')),
        ],
        selected: {widget.nivel},
        onSelectionChanged: (s) => widget.alCambiarNivel(s.first),
      ),
      child: red == null
          ? SizedBox(
              height: alto,
              child: const Center(child: CircularProgressIndicator(color: RBColores.azul)),
            )
          : red.nodos.isEmpty
          ? const SinDatosAnalisis('No hay hechos para dibujar la red en este período.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    height: alto,
                    color: RBColores.fondo,
                    child: Stack(
                      children: [
                        LienzoGrafo(
                          nodos: red.nodos,
                          aristas: red.aristas,
                          seleccion: _seleccion?.clave,
                          controlador: _controlador,
                          alSeleccionar: (n) => setState(() => _seleccion = n),
                          alTocarFondo: () => setState(() => _seleccion = null),
                        ),
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: BotonCircular(
                            icono: Icons.center_focus_strong_rounded,
                            tooltip: 'Encuadrar la red',
                            onTap: _controlador.encuadrar,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _DetalleNodo(
                  nodo: _seleccion,
                  conexiones: _seleccion == null ? const [] : _conexiones(red, _seleccion!),
                ),
              ],
            ),
    );
  }
}

class _DetalleNodo extends StatelessWidget {
  final NodoGrafo? nodo;
  final List<(NodoGrafo, int)> conexiones;

  const _DetalleNodo({required this.nodo, required this.conexiones});

  @override
  Widget build(BuildContext context) {
    final n = nodo;
    if (n == null) {
      return const Text(
        'Toca un nodo para ver su detalle. Arrastra para moverte y usa dos dedos o la rueda para acercar.',
        style: TextStyle(fontSize: 12.5, color: RBColores.texto2),
      );
    }
    final total = (n.datos['total'] as num?)?.toInt() ?? 0;
    final comuna = n.datos['comuna']?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${n.etiqueta}${comuna != null && comuna != n.etiqueta ? ' · $comuna' : ''}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: RBColores.tinta),
        ),
        const SizedBox(height: 2),
        Text(
          '$total ${total == 1 ? 'hecho' : 'hechos'}${n.tipo == 'Categoria' ? ' en los lugares de la red' : ''}',
          style: const TextStyle(fontSize: 13, color: RBColores.texto2),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (otro, peso) in conexiones.take(8))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: RBColores.fondo, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  '${otro.etiqueta} · $peso',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
