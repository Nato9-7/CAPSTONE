import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rb_alertas/config/api_config.dart';
import 'package:rb_alertas/modelos/modelos.dart';
import 'package:rb_alertas/servicios/admin_servicio.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/servicios/reporte_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/vistas/admin/comun_admin.dart';
import 'package:rb_alertas/vistas/admin/moderacion_reporte.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Reportes para moderar, pensada para muchos reportes:
/// - abre en "Por revisar": los pendientes, primero los con más denuncias y desmentidos;
/// - contadores por estado, búsqueda por #número o texto, filtros por categoría y fecha;
/// - filas compactas que cargan de a 25 al bajar (sin tope).
class PestanaReportes extends StatefulWidget {
  /// Permite que otra sección (p. ej. el Resumen) abra la lista en un estado.
  final ValueNotifier<String?>? estadoSolicitado;

  const PestanaReportes({super.key, this.estadoSolicitado});

  @override
  State<PestanaReportes> createState() => _PestanaReportesState();
}

class _PestanaReportesState extends State<PestanaReportes> with AutomaticKeepAliveClientMixin {
  /// (estado, etiqueta). "Por revisar" son los pendientes ordenados por prioridad.
  static const _pestanas = [
    ('PENDIENTE', 'Por revisar'),
    ('VALIDADO', 'Validados'),
    ('RESUELTO', 'Resueltos'),
    ('DESCARTADO', 'Descartados'),
    ('EXPIRADO', 'Expirados'),
    (null, 'Todos'),
  ];
  static const _periodos = [
    (null, 'Cualquier fecha'),
    (1, 'Últimas 24 h'),
    (7, 'Últimos 7 días'),
    (30, 'Últimos 30 días'),
  ];

  final _servicio = AdminServicio();
  final _buscador = TextEditingController();
  final _scroll = ScrollController();
  Timer? _esperaBusqueda;

  FiltroReportes _filtro = const FiltroReportes(estado: 'PENDIENTE', orden: 'prioridad');
  int? _diasPeriodo;
  List<CategoriaIncidente> _categorias = const [];

  final List<ReporteAdmin> _reportes = [];
  Map<String, int> _conteos = const {};
  int _total = 0;
  int _pagina = 0;
  bool _hayMas = true;
  bool _cargando = false;
  String? _error;

  /// Descarta respuestas de una búsqueda anterior si el filtro cambió entretanto.
  int _consulta = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _siguientePagina();
    });
    widget.estadoSolicitado?.addListener(_aplicarSolicitud);
    ReporteServicio()
        .obtenerCategorias()
        .then((c) {
          if (mounted) setState(() => _categorias = c);
        })
        .catchError((_) {});
    _reiniciar();
  }

  @override
  void dispose() {
    widget.estadoSolicitado?.removeListener(_aplicarSolicitud);
    _esperaBusqueda?.cancel();
    _buscador.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _aplicarSolicitud() {
    final estado = widget.estadoSolicitado?.value;
    if (estado == null) return; // el valor se limpia antes de cada solicitud
    _cambiarFiltro(_filtro.copiar(estado: () => estado, orden: estado == 'PENDIENTE' ? 'prioridad' : 'recientes'));
  }

  /// Vuelve a la primera página con el filtro actual.
  Future<void> _reiniciar() async {
    final consulta = ++_consulta;
    setState(() {
      _reportes.clear();
      _pagina = 0;
      _hayMas = true;
      _error = null;
    });
    await _siguientePagina(consulta: consulta);
  }

  Future<void> _siguientePagina({int? consulta}) async {
    if (_cargando || !_hayMas) return;
    final id = consulta ?? _consulta;
    setState(() => _cargando = true);
    try {
      final pagina = await _servicio.reportes(filtro: _filtro, pagina: _pagina + 1);
      if (!mounted || id != _consulta) return;
      setState(() {
        _reportes.addAll(pagina.reportes);
        _pagina = pagina.pagina;
        _hayMas = pagina.hayMas;
        _total = pagina.total;
        _conteos = pagina.conteos;
      });
    } catch (e) {
      if (mounted && id == _consulta) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _cambiarFiltro(FiltroReportes filtro) {
    _filtro = filtro;
    _cargando = false;
    _reiniciar();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _buscar(String texto) {
    _esperaBusqueda?.cancel();
    // Espera a que se termine de escribir para no hacer una consulta por letra.
    _esperaBusqueda = Timer(const Duration(milliseconds: 400), () {
      _cambiarFiltro(_filtro.copiar(texto: () => texto.trim().isEmpty ? null : texto.trim()));
    });
  }

  void _elegirPeriodo(int? dias) {
    _diasPeriodo = dias;
    _cambiarFiltro(_filtro.copiar(desde: () => dias == null ? null : DateTime.now().subtract(Duration(days: dias))));
  }

  /// Aplica una acción de moderación y recarga si cambió algo.
  Future<void> _moderar(Future<bool> accion) async {
    if (await accion && mounted) _reiniciar();
  }

  Future<void> _abrir(ReporteAdmin r) async {
    if (await abrirModeracion(context, r.id) && mounted) _reiniciar();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, c) {
        final margen = c.maxWidth < 600 ? 16.0 : 24.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: EdgeInsets.fromLTRB(margen, 10, margen, 0), child: _barraBusqueda()),
            _pestanasEstado(margen),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: margen),
              child: _lineaResultado(),
            ),
            Expanded(child: _lista(margen)),
          ],
        );
      },
    );
  }

  Widget _barraBusqueda() {
    final categoria = _categorias.where((c) => c.codigo == _filtro.categoria).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _buscador,
          onChanged: (texto) {
            setState(() {}); // muestra u oculta el botón para borrar
            _buscar(texto);
          },
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Buscar por #número, descripción o lugar',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _buscador.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Borrar búsqueda',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _buscador.clear();
                      _buscar('');
                    },
                  ),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _Desplegable<String?>(
                icono: categoria == null ? Icons.category_outlined : iconoCategoria(categoria.codigo),
                etiqueta: categoria?.nombre ?? 'Categoría',
                activo: categoria != null,
                opciones: [(null, 'Todas las categorías'), for (final c in _categorias) (c.codigo, c.nombre)],
                alElegir: (codigo) => _cambiarFiltro(_filtro.copiar(categoria: () => codigo)),
              ),
              const SizedBox(width: 8),
              _Desplegable<int?>(
                icono: Icons.event_outlined,
                etiqueta: _periodos.firstWhere((p) => p.$1 == _diasPeriodo).$2,
                activo: _diasPeriodo != null,
                opciones: _periodos,
                alElegir: _elegirPeriodo,
              ),
              const SizedBox(width: 8),
              _Desplegable<String>(
                icono: Icons.sort_rounded,
                etiqueta: _filtro.orden == 'prioridad' ? 'Prioridad' : 'Más recientes',
                activo: false,
                opciones: const [('prioridad', 'Prioridad (denuncias y desmentidos)'), ('recientes', 'Más recientes')],
                alElegir: (orden) => _cambiarFiltro(_filtro.copiar(orden: orden)),
              ),
              if (_filtro.tieneFiltrosExtra) ...[
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () {
                    _buscador.clear();
                    _diasPeriodo = null;
                    _cambiarFiltro(FiltroReportes(estado: _filtro.estado, orden: _filtro.orden));
                  },
                  child: const Text('Limpiar filtros'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _pestanasEstado(double margen) {
    final total = _conteos.values.fold(0, (a, b) => a + b);
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(margen, 8, margen, 4),
        children: [
          for (final (estado, etiqueta) in _pestanas)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('$etiqueta ${estado == null ? total : (_conteos[estado] ?? 0)}'),
                selected: _filtro.estado == estado,
                showCheckmark: false,
                selectedColor: RBColores.azul,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _filtro.estado == estado ? Colors.white : RBColores.tinta,
                ),
                onSelected: (_) => _cambiarFiltro(
                  _filtro.copiar(estado: () => estado, orden: estado == 'PENDIENTE' ? 'prioridad' : 'recientes'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _lineaResultado() {
    final texto = _reportes.isEmpty && _cargando
        ? 'Cargando…'
        : '$_total ${_total == 1 ? 'reporte' : 'reportes'}'
              '${_filtro.estado == 'PENDIENTE' && _filtro.orden == 'prioridad' ? ' · primero los con más denuncias y desmentidos' : ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Text(texto, style: const TextStyle(fontSize: 12.5, color: RBColores.texto2)),
    );
  }

  Widget _lista(double margen) {
    if (_reportes.isEmpty) {
      if (_error != null) return MensajeCentro(_error!, reintentar: _reiniciar);
      if (_cargando) return const Center(child: CircularProgressIndicator(color: RBColores.azul));
      return RefreshIndicator(
        onRefresh: _reiniciar,
        child: MensajeCentro(
          _filtro.estado == 'PENDIENTE' && !_filtro.tieneFiltrosExtra
              ? 'No hay reportes por revisar.'
              : 'No hay reportes con estos filtros.',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _reiniciar,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(margen, 0, margen, 32),
        itemCount: _reportes.length + 1,
        itemBuilder: (_, i) {
          if (i == _reportes.length) return _pie();
          return Padding(padding: const EdgeInsets.only(bottom: 8), child: _fila(_reportes[i]));
        },
      ),
    );
  }

  Widget _pie() {
    if (_error != null) {
      return Center(
        child: TextButton(onPressed: _siguientePagina, child: const Text('Reintentar')),
      );
    }
    if (_hayMas) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(color: RBColores.azul)),
      );
    }
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'No hay más reportes',
        textAlign: TextAlign.center,
        style: TextStyle(color: RBColores.texto2),
      ),
    );
  }

  Widget _fila(ReporteAdmin r) {
    final icono = IconoCategoria(codigo: r.categoriaCodigo, colorHex: r.colorHex, tamano: 44);
    final lugar = r.zona ?? r.direccion;
    return TarjetaRB(
      onTap: () => _abrir(r),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Row(
        children: [
          if (r.imagen != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                ApiConfig.urlArchivo(r.imagen!),
                width: 44,
                height: 44,
                cacheWidth: 132,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => icono,
              ),
            )
          else
            icono,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '#${r.id} ${r.categoria}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: RBColores.tinta),
                      ),
                    ),
                    const SizedBox(width: 6),
                    chipReporte(r.estado),
                    if (r.soloGrupo) ...[const SizedBox(width: 4), const ChipSoloGrupo()],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  r.descripcion,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, color: RBColores.tinta),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      [?lugar, tiempoRelativo(r.fechaCreacion?.toLocal())].join(' · '),
                      style: const TextStyle(fontSize: 12, color: RBColores.texto2),
                    ),
                    _Contador(icono: Icons.thumb_up_alt_outlined, valor: r.confirmaciones, etiqueta: 'confirman'),
                    _Contador(icono: Icons.thumb_down_alt_outlined, valor: r.desmentidos, etiqueta: 'desmienten'),
                    if (r.denunciasPendientes > 0)
                      PildoraAdmin(
                        texto: r.denunciasPendientes == 1 ? '1 denuncia' : '${r.denunciasPendientes} denuncias',
                        fondo: RBColores.rojo50,
                        color: RBColores.rojo,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        tamano: 11.5,
                      ),
                  ],
                ),
              ],
            ),
          ),
          MenuAccionesReporte(reporte: r, alModerar: _moderar),
        ],
      ),
    );
  }
}

class _Contador extends StatelessWidget {
  final IconData icono;
  final int valor;
  final String etiqueta;

  const _Contador({required this.icono, required this.valor, required this.etiqueta});

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$valor $etiqueta',
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 14, color: RBColores.texto2),
          const SizedBox(width: 3),
          Text('$valor', style: const TextStyle(fontSize: 12, color: RBColores.texto2)),
        ],
      ),
    ),
  );
}

/// Botón con menú desplegable para un filtro de la lista.
class _Desplegable<T> extends StatelessWidget {
  final IconData icono;
  final String etiqueta;
  final bool activo;
  final List<(T, String)> opciones;
  final ValueChanged<T> alElegir;

  const _Desplegable({
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
