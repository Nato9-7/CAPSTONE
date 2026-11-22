import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/modelos.dart';
import 'package:rb_alertas/servicios/admin_servicio.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/admin/analisis/graficos_analisis.dart';
import 'package:rb_alertas/vistas/admin/analisis/tarjetas_analisis.dart';
import 'package:rb_alertas/vistas/admin/comun_admin.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';
import 'package:rb_alertas/widgets/dialogos.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Análisis de los hechos sobre el grafo de Neo4j: cuántos hay por día, en qué
/// calles y sectores se concentran, cómo cambian frente al período anterior y
/// qué categorías se repiten en cada lugar.
///
/// Un solo juego de filtros (período, categoría, comuna) gobierna toda la sección.
class SeccionAnalisis extends StatefulWidget {
  const SeccionAnalisis({super.key});

  @override
  State<SeccionAnalisis> createState() => _SeccionAnalisisState();
}

class _SeccionAnalisisState extends State<SeccionAnalisis> with AutomaticKeepAliveClientMixin {
  static const _periodos = [7, 30, 90];

  final _servicio = AdminServicio();

  int _dias = 30;
  String? _categoria;
  int? _comuna;
  int? _sector;
  String _nivelRed = 'calle';

  FiltrosDisponibles? _filtros;
  SerieDiaria? _serie;
  RankingCalles? _calles;
  SectoresEnElTiempo? _sectores;
  RedGrafo? _red;
  String? _error;
  bool _sincronizando = false;

  /// true mientras haya un dedo sobre la red (ver [TarjetaRedLugares.alTocarRed]).
  bool _gestoEnRed = false;

  /// Cada carga lleva un número: si el usuario cambia los filtros a medio
  /// camino, las respuestas de la carga anterior se descartan.
  int _carga = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _servicio
        .filtrosAnalisis()
        .then((f) {
          if (mounted) setState(() => _filtros = f);
        })
        .catchError((_) {});
    _cargar();
  }

  Future<void> _cargar() async {
    final carga = ++_carga;
    setState(() {
      _error = null;
      _serie = null;
      _calles = null;
      _sectores = null;
      _red = null;
    });
    void aplicar(VoidCallback cambio) {
      if (mounted && carga == _carga) setState(cambio);
    }

    try {
      // Las cuatro consultas van en paralelo; cada tarjeta aparece cuando llega lo suyo.
      await Future.wait([
        _servicio
            .hechosPorDia(dias: _dias, categoria: _categoria, comuna: _comuna, sector: _sector)
            .then((s) => aplicar(() => _serie = s)),
        _servicio
            .rankingCalles(dias: _dias, categoria: _categoria, comuna: _comuna, sector: _sector)
            .then((c) => aplicar(() => _calles = c)),
        _servicio
            .sectores(dias: _dias, categoria: _categoria, comuna: _comuna, sector: _sector)
            .then((s) => aplicar(() => _sectores = s)),
        _cargarRed(carga),
      ]);
    } catch (e) {
      aplicar(() => _error = mensajeDeError(e));
    }
  }

  Future<void> _cargarRed(int carga) async {
    final red = await _servicio.redDeLugares(dias: _dias, categoria: _categoria, sector: _sector, nivel: _nivelRed);
    if (mounted && carga == _carga) setState(() => _red = red);
  }

  void _cambiarNivel(String nivel) {
    setState(() {
      _nivelRed = nivel;
      _red = null;
    });
    _cargarRed(_carga).catchError((e) {
      if (mounted) mostrarAviso(context, mensajeDeError(e));
    });
  }

  void _filtrar({int? dias, String? Function()? categoria, int? Function()? comuna, int? Function()? sector}) {
    setState(() {
      if (dias != null) _dias = dias;
      if (categoria != null) _categoria = categoria();
      if (comuna != null) {
        _comuna = comuna();
        // Un sector de otra comuna dejaría el análisis vacío: se limpia.
        final sectorActual = _filtros?.sectores.where((x) => x.id == _sector).firstOrNull;
        if (_comuna != null && sectorActual != null && sectorActual.idComuna != _comuna) _sector = null;
      }
      if (sector != null) _sector = sector();
    });
    _cargar();
  }

  Future<void> _sincronizar() async {
    setState(() => _sincronizando = true);
    final ok = await ejecutarAccionAdmin(context, _servicio.sincronizarGrafo, 'Datos actualizados');
    if (!mounted) return;
    setState(() => _sincronizando = false);
    if (ok) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, c) {
        final ancho = c.maxWidth >= 1100;
        final margen = c.maxWidth < 600 ? 16.0 : 24.0;
        return RefreshIndicator(
          onRefresh: _cargar,
          child: ListView(
            // Con un dedo sobre la red, la página no se desplaza: así el gesto
            // (mover o acercar con dos dedos) es de la red y no de la página.
            physics: _gestoEnRed ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(margen, 8, margen, 32),
            children: [
              _barraFiltros(),
              const SizedBox(height: 14),
              if (_error != null)
                MensajeCentro(_error!, reintentar: _cargar)
              else ...[
                _indicadores(c.maxWidth),
                const SizedBox(height: 16),
                TarjetaAnalisis(
                  titulo: 'Hechos por día',
                  subtitulo:
                      'Un hecho reportado por varios vecinos cuenta una vez. '
                      'La línea verde es el promedio diario.',
                  child: _serie == null
                      ? const SizedBox(
                          height: 210,
                          child: Center(child: CircularProgressIndicator(color: RBColores.azul)),
                        )
                      : BarrasPorDia(dias: _serie!.dias, promedio: _serie!.promedioDiario),
                ),
                const SizedBox(height: 16),
                if (ancho)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _tarjetaCalles()),
                      const SizedBox(width: 16),
                      Expanded(child: TarjetaSectores(datos: _sectores)),
                    ],
                  )
                else ...[
                  _tarjetaCalles(),
                  const SizedBox(height: 16),
                  TarjetaSectores(datos: _sectores),
                ],
                const SizedBox(height: 16),
                TarjetaRedLugares(
                  red: _red,
                  nivel: _nivelRed,
                  alCambiarNivel: _cambiarNivel,
                  alTocarRed: (tocando) {
                    if (tocando != _gestoEnRed) setState(() => _gestoEnRed = tocando);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _tarjetaCalles() =>
      TarjetaCalles(ranking: _calles, alTocar: (calle) => mostrarDetalleCalle(context, calle, _dias));

  Widget _barraFiltros() {
    final filtros = _filtros;
    final categoria = filtros?.categorias.where((c) => c.codigo == _categoria).firstOrNull;
    final comuna = filtros?.comunas.where((c) => c.id == _comuna).firstOrNull;
    final sector = filtros?.sectores.where((x) => x.id == _sector).firstOrNull;
    // Solo los sectores de la comuna elegida (o todos, si no hay comuna).
    final sectores = [
      for (final x in filtros?.sectores ?? const <({int id, String nombre, int? idComuna})>[])
        if (_comuna == null || x.idComuna == _comuna) x,
    ];
    final sincronizado = _serie?.sincronizadoEn;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [for (final d in _periodos) ButtonSegment(value: d, label: Text('$d días'))],
          selected: {_dias},
          onSelectionChanged: (s) => _filtrar(dias: s.first),
        ),
        const SizedBox(height: 10),
        // Una sola fila deslizable: en el celular los filtros no se apilan.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: 8,
            children: [
              _MenuFiltro<String?>(
                icono: categoria == null ? Icons.category_outlined : iconoCategoria(categoria.codigo),
                etiqueta: categoria?.nombre ?? 'Todas las categorías',
                activo: categoria != null,
                opciones: [
                  (null, 'Todas las categorías'),
                  for (final c in filtros?.categorias ?? const <CategoriaAnalisis>[]) (c.codigo, c.nombre),
                ],
                alElegir: (codigo) => _filtrar(categoria: () => codigo),
              ),
              if ((filtros?.comunas.length ?? 0) > 1)
                _MenuFiltro<int?>(
                  icono: Icons.location_city_rounded,
                  etiqueta: comuna?.nombre ?? 'Todas las comunas',
                  activo: comuna != null,
                  opciones: [(null, 'Todas las comunas'), for (final c in filtros!.comunas) (c.id, c.nombre)],
                  alElegir: (id) => _filtrar(comuna: () => id),
                ),
              if (sectores.length > 1 || sector != null)
                _MenuFiltro<int?>(
                  icono: Icons.place_rounded,
                  etiqueta: sector?.nombre ?? 'Todos los sectores',
                  activo: sector != null,
                  opciones: [(null, 'Todos los sectores'), for (final x in sectores) (x.id, x.nombre)],
                  alElegir: (id) => _filtrar(sector: () => id),
                ),
              TextButton.icon(
                onPressed: _sincronizando ? null : _sincronizar,
                icon: _sincronizando
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync_rounded, size: 18),
                label: Text(
                  sincronizado == null
                      ? 'Actualizar datos'
                      : 'Datos de las ${sincronizado.hour.toString().padLeft(2, '0')}:'
                            '${sincronizado.minute.toString().padLeft(2, '0')}',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _indicadores(double ancho) {
    final s = _serie;
    final columnas = ancho >= 900 ? 4 : 2;
    final tarjetas = [
      _Indicador(
        titulo: 'Hechos en $_dias días',
        valor: s == null ? '–' : '${s.total}',
        pie: s == null ? null : InsigniaTendencia(tendencia: s.tendencia, variacion: s.variacion),
        detalle: s == null ? '' : '${s.anterior} en los $_dias días anteriores',
      ),
      _Indicador(
        titulo: 'Promedio diario',
        valor: s == null ? '–' : s.promedioDiario.toStringAsFixed(1).replaceAll('.', ','),
        detalle: 'hechos por día',
      ),
      _Indicador(
        titulo: 'Día con más hechos',
        valor: s?.diaPico == null ? '–' : diaCorto(s!.diaPico!.dia),
        detalle: s?.diaPico == null ? 'sin hechos' : '${s!.diaPico!.total} hechos',
      ),
      _Indicador(
        titulo: 'Calles con hechos',
        valor: _calles == null ? '–' : '${_calles!.totalCalles}',
        detalle: _calles?.calles.firstOrNull == null ? '' : 'Más: ${_calles!.calles.first.nombre}',
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        const separacion = 12.0;
        final anchoTarjeta = (c.maxWidth - separacion * (columnas - 1)) / columnas;
        return Wrap(
          spacing: separacion,
          runSpacing: separacion,
          children: [for (final t in tarjetas) SizedBox(width: anchoTarjeta, child: t)],
        );
      },
    );
  }
}

class _Indicador extends StatelessWidget {
  final String titulo;
  final String valor;
  final String detalle;
  final Widget? pie;

  const _Indicador({required this.titulo, required this.valor, required this.detalle, this.pie});

  @override
  Widget build(BuildContext context) {
    return TarjetaRB(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: RBColores.texto2),
          ),
          const SizedBox(height: 4),
          // Wrap: en celulares angostos la tendencia baja a la línea siguiente.
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                valor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: RBFuentes.titulos,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: RBColores.azul,
                ),
              ),
              ?pie,
            ],
          ),
          const SizedBox(height: 2),
          Text(
            detalle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: RBColores.texto2),
          ),
        ],
      ),
    );
  }
}

/// Botón con menú desplegable para elegir un filtro.
class _MenuFiltro<T> extends StatelessWidget {
  final IconData icono;
  final String etiqueta;
  final bool activo;
  final List<(T, String)> opciones;
  final ValueChanged<T> alElegir;

  const _MenuFiltro({
    required this.icono,
    required this.etiqueta,
    required this.activo,
    required this.opciones,
    required this.alElegir,
  });

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, menu, _) => ChipFiltro(
        etiqueta: etiqueta,
        activo: activo,
        icono: Icon(icono, size: 18, color: activo ? Colors.white : RBColores.azul),
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
      ),
      menuChildren: [
        for (final (valor, texto) in opciones) MenuItemButton(onPressed: () => alElegir(valor), child: Text(texto)),
      ],
    );
  }
}
