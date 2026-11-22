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
    final encabezado = Column(
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
    );
    return TarjetaRB(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Angosto (celular): el selector baja bajo el título en vez de apretarlo.
          LayoutBuilder(
            builder: (context, c) => accion == null
                ? encabezado
                : c.maxWidth < 480
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [encabezado, const SizedBox(height: 10), accion!],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Expanded(child: encabezado), const SizedBox(width: 12), accion!],
                  ),
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

class TarjetaCalles extends StatefulWidget {
  final RankingCalles? ranking;
  final ValueChanged<CalleAnalisis>? alTocar;

  const TarjetaCalles({super.key, required this.ranking, this.alTocar});

  @override
  State<TarjetaCalles> createState() => _TarjetaCallesState();
}

class _TarjetaCallesState extends State<TarjetaCalles> {
  /// Por sector (cada sector con sus calles) o todas las calles en un solo ranking.
  bool _porSector = true;

  @override
  Widget build(BuildContext context) {
    final r = widget.ranking;
    return TarjetaAnalisis(
      titulo: 'Calles con más hechos',
      subtitulo: _porSector
          ? 'Cada sector con sus calles. Una calle que cruza varios sectores aparece en cada uno.'
          : 'Tramos de calle ordenados por hechos. La etiqueta compara con el período anterior.',
      accion: SegmentedButton<bool>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment(value: true, label: Text('Por sector')),
          ButtonSegment(value: false, label: Text('Todas')),
        ],
        selected: {_porSector},
        onSelectionChanged: (s) => setState(() => _porSector = s.first),
      ),
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
                if (_porSector)
                  for (final (i, grupo) in r.porSector.indexed)
                    _GrupoSector(grupo: grupo, abierto: i == 0, alTocar: widget.alTocar)
                else
                  for (final (i, calle) in r.calles.indexed) ...[
                    if (i > 0) const Divider(height: 1, color: RBColores.linea),
                    _FilaCalle(
                      posicion: i + 1,
                      calle: calle,
                      maximo: r.calles.first.total,
                      alTocar: widget.alTocar,
                      conSector: true,
                    ),
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

/// Un sector desplegable: su total y, adentro, sus calles con más hechos.
class _GrupoSector extends StatelessWidget {
  final GrupoSector grupo;
  final bool abierto;
  final ValueChanged<CalleAnalisis>? alTocar;

  const _GrupoSector({required this.grupo, required this.abierto, this.alTocar});

  @override
  Widget build(BuildContext context) {
    final g = grupo;
    final maximo = g.calles.isEmpty ? 1 : g.calles.first.total;
    final restantes = g.totalCalles - g.calles.length;
    return Theme(
      // Sin las líneas que ExpansionTile dibuja arriba y abajo al abrirse.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: abierto,
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: const EdgeInsets.only(left: 8, bottom: 6),
        leading: Icon(
          g.id == null ? Icons.help_outline_rounded : Icons.place_rounded,
          color: g.id == null ? RBColores.texto2 : RBColores.azul,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                g.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: RBColores.tinta),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${g.total}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: RBColores.tinta),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              InsigniaTendencia(tendencia: g.tendencia, variacion: g.variacion),
              Text(
                '${g.totalCalles} ${g.totalCalles == 1 ? 'calle' : 'calles'}'
                '${g.comuna != null && g.comuna != g.nombre ? ' · ${g.comuna}' : ''}',
                style: const TextStyle(fontSize: 12.5, color: RBColores.texto2),
              ),
            ],
          ),
        ),
        children: [
          for (final (i, calle) in g.calles.indexed) ...[
            if (i > 0) const Divider(height: 1, color: RBColores.linea),
            _FilaCalle(posicion: i + 1, calle: calle, maximo: maximo, alTocar: alTocar),
          ],
          if (restantes > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 26),
              child: Text(
                restantes == 1 ? '1 calle más con menos hechos' : '$restantes calles más con menos hechos',
                style: const TextStyle(fontSize: 12, color: RBColores.texto2),
              ),
            ),
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

  /// En el ranking general se muestra el sector de cada tramo; dentro de un sector, no hace falta.
  final bool conSector;

  const _FilaCalle({
    required this.posicion,
    required this.calle,
    required this.maximo,
    this.alTocar,
    this.conSector = false,
  });

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
                      if (conSector && calle.lugar != null)
                        Text(calle.lugar!, style: const TextStyle(fontSize: 12, color: RBColores.texto2)),
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
            if (calle.lugar != null) Text(calle.lugar!, style: const TextStyle(color: RBColores.texto2)),
            if (calle.sector != null && calle.puestoEnSector != null && (calle.callesEnSector ?? 0) > 1) ...[
              const SizedBox(height: 6),
              Text(
                calle.puestoEnSector == 1
                    ? 'La calle con más hechos de ${calle.sector} (de ${calle.callesEnSector}).'
                    : 'Puesto ${calle.puestoEnSector} de ${calle.callesEnSector} calles en ${calle.sector}.',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: RBColores.azul),
              ),
            ],
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

/// Categorías (o lugares) conectados a [nodo], con cuántos hechos, de más a menos.
List<(NodoGrafo, int)> conexionesDe(RedGrafo red, NodoGrafo nodo) {
  final porClave = {for (final n in red.nodos) n.clave: n};
  final lista = <(NodoGrafo, int)>[];
  for (final a in red.aristas) {
    final otro = a.origen == nodo.clave ? a.destino : (a.destino == nodo.clave ? a.origen : null);
    final n = otro == null ? null : porClave[otro];
    if (n != null) lista.add((n, (a.datos['peso'] as num?)?.toInt() ?? 0));
  }
  return lista..sort((a, b) => b.$2.compareTo(a.$2));
}

/// El nodo elegido y lo conectado a él: el resto de la red se atenúa. Un sector
/// resalta además lo que pasó en sus calles (dos pasos: sector → calle → categoría).
Set<String>? resaltadosDe(RedGrafo red, NodoGrafo? nodo) {
  if (nodo == null) return null;
  final directos = [for (final (n, _) in conexionesDe(red, nodo)) n];
  return {
    nodo.clave,
    for (final n in directos) n.clave,
    if (nodo.tipo == 'Localidad')
      for (final calle in directos)
        for (final (n, _) in conexionesDe(red, calle)) n.clave,
  };
}

class TarjetaRedLugares extends StatefulWidget {
  final RedGrafo? red;
  final String nivel;
  final ValueChanged<String> alCambiarNivel;

  /// true mientras haya un dedo sobre la red: la página que la contiene debe
  /// dejar de desplazarse, o se queda con el gesto y no se puede acercar ni mover la red.
  final ValueChanged<bool>? alTocarRed;

  const TarjetaRedLugares({
    super.key,
    required this.red,
    required this.nivel,
    required this.alCambiarNivel,
    this.alTocarRed,
  });

  @override
  State<TarjetaRedLugares> createState() => _TarjetaRedLugaresState();
}

class _TarjetaRedLugaresState extends State<TarjetaRedLugares> {
  final _controlador = ControladorLienzo();
  final Set<int> _dedos = {};
  NodoGrafo? _seleccion;

  @override
  void didUpdateWidget(TarjetaRedLugares viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.red != widget.red) _seleccion = null;
  }

  void _dedoAbajo(PointerDownEvent e) {
    _dedos.add(e.pointer);
    if (_dedos.length == 1) widget.alTocarRed?.call(true);
  }

  void _dedoArriba(PointerEvent e) {
    if (_dedos.remove(e.pointer) && _dedos.isEmpty) widget.alTocarRed?.call(false);
  }

  Future<void> _pantallaCompleta(RedGrafo red) async {
    final elegido = await Navigator.of(context).push<NodoGrafo?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PantallaRedCompleta(red: red, seleccion: _seleccion),
      ),
    );
    if (mounted) setState(() => _seleccion = elegido);
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
                Listener(
                  onPointerDown: _dedoAbajo,
                  onPointerUp: _dedoArriba,
                  onPointerCancel: _dedoArriba,
                  child: ClipRRect(
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
                            resaltados: resaltadosDe(red, _seleccion),
                            controlador: _controlador,
                            alSeleccionar: (n) => setState(() => _seleccion = n),
                            alTocarFondo: () => setState(() => _seleccion = null),
                          ),
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: Column(
                              spacing: 10,
                              children: [
                                BotonCircular(
                                  icono: Icons.open_in_full_rounded,
                                  tooltip: 'Ver en pantalla completa',
                                  tamano: 44,
                                  onTap: () => _pantallaCompleta(red),
                                ),
                                BotonCircular(
                                  icono: Icons.center_focus_strong_rounded,
                                  tooltip: 'Encuadrar la red',
                                  tamano: 44,
                                  onTap: _controlador.encuadrar,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _DetalleNodo(
                  nodo: _seleccion,
                  conexiones: _seleccion == null ? const [] : conexionesDe(red, _seleccion!),
                ),
              ],
            ),
    );
  }
}

/// La red ocupando toda la pantalla: sin una página que se desplace alrededor,
/// los gestos de acercar y mover son todos de la red. Devuelve el nodo elegido.
class _PantallaRedCompleta extends StatefulWidget {
  final RedGrafo red;
  final NodoGrafo? seleccion;

  const _PantallaRedCompleta({required this.red, required this.seleccion});

  @override
  State<_PantallaRedCompleta> createState() => _PantallaRedCompletaState();
}

class _PantallaRedCompletaState extends State<_PantallaRedCompleta> {
  final _controlador = ControladorLienzo();
  late NodoGrafo? _seleccion = widget.seleccion;

  @override
  Widget build(BuildContext context) {
    final red = widget.red;
    return PopScope<NodoGrafo?>(
      canPop: false,
      onPopInvokedWithResult: (salio, _) {
        if (!salio) Navigator.of(context).pop(_seleccion);
      },
      child: Scaffold(
        backgroundColor: RBColores.fondo,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          title: const Text('Red de lugares y categorías'),
          actions: [
            IconButton(
              tooltip: 'Encuadrar la red',
              icon: const Icon(Icons.center_focus_strong_rounded),
              onPressed: _controlador.encuadrar,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: LienzoGrafo(
                  nodos: red.nodos,
                  aristas: red.aristas,
                  seleccion: _seleccion?.clave,
                  resaltados: resaltadosDe(red, _seleccion),
                  controlador: _controlador,
                  alSeleccionar: (n) => setState(() => _seleccion = n),
                  alTocarFondo: () => setState(() => _seleccion = null),
                ),
              ),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: _DetalleNodo(
                  nodo: _seleccion,
                  conexiones: _seleccion == null ? const [] : conexionesDe(red, _seleccion!),
                ),
              ),
            ],
          ),
        ),
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
