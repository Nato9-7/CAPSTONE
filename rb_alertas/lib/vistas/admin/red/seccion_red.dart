import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/modelos.dart';
import 'package:rb_alertas/servicios/admin_servicio.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/servicios/reporte_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/admin/red/barra_herramientas_red.dart';
import 'package:rb_alertas/vistas/admin/red/filtros_red.dart';
import 'package:rb_alertas/vistas/admin/red/hallazgos_red.dart';
import 'package:rb_alertas/vistas/admin/red/leyenda_red.dart';
import 'package:rb_alertas/vistas/admin/red/panel_detalle_red.dart';
import 'package:rb_alertas/vistas/admin/red/piezas_red.dart';
import 'package:rb_alertas/widgets/dialogos.dart';
import 'package:rb_alertas/widgets/lienzo_grafo.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Sección "Red" del panel: explorador de la red de vecinos guardada en Neo4j.
///
/// En computador: hallazgos a la izquierda, la red al centro y el detalle del
/// elemento elegido a la derecha. En celular se alterna entre hallazgos y red.
class SeccionRed extends StatefulWidget {
  const SeccionRed({super.key});

  @override
  State<SeccionRed> createState() => _SeccionRedState();
}

class _SeccionRedState extends State<SeccionRed> with AutomaticKeepAliveClientMixin {
  /// Índice de la sección "Zonas" de los hallazgos, que depende de los filtros.
  static const _seccionZonas = 3;

  final _servicio = AdminServicio();
  final _lienzo = ControladorLienzo();

  // La red que se está mirando (se amplía sin perder lo anterior).
  List<NodoGrafo> _nodos = [];
  List<AristaGrafo> _aristas = [];
  NodoGrafo? _seleccion;
  Set<String>? _resaltados;
  String? _avisoResaltado;

  FiltrosRed _filtros = const FiltrosRed();
  bool _comunidades = false;
  List<CategoriaIncidente> _categoriasDisponibles = [];

  /// Pantalla angosta (celular): filtros en una hoja aparte y leyenda plegada.
  bool _compacto = false;
  bool _verLeyenda = false;

  /// "¿Cómo se conecta con…?": el primer elemento elegido.
  NodoGrafo? _caminoDesde;

  // Hallazgos.
  ResumenGrafo? _resumen;
  int _seccion = 0;
  List<GrupoSospechoso>? _sospechosos;
  List<VecinoReputacion>? _reputacion;
  List<IncidenteGrafo>? _incidentes;
  List<NodoGrafo>? _zonas;
  bool _reputacionAlta = false;

  bool _cargando = false;
  String? _error;

  /// En celular: 0 = hallazgos, 1 = red.
  int _vistaMovil = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _ejecutar(_cargarRedYHallazgos);
    _cargarCategorias();
  }

  /// Para el filtro de categorías. Si falla, solo queda la opción "Todas".
  Future<void> _cargarCategorias() async {
    try {
      final categorias = await ReporteServicio().obtenerCategorias();
      if (mounted) setState(() => _categoriasDisponibles = categorias);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Datos

  /// Corre [accion] con la barra de progreso y muestra su error sobre la red.
  Future<void> _ejecutar(Future<void> Function() accion) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await accion();
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarRedYHallazgos() => Future.wait([_cargarRed(), _cargarHallazgos()]);

  /// Pide la red según los filtros y conserva la selección si sigue visible.
  Future<void> _cargarRed() async {
    final red = await _servicio.red(
      modo: _filtros.modo,
      dias: _filtros.dias,
      capas: _filtros.capas,
      categoria: _filtros.categoria,
    );
    if (!mounted) return;
    setState(() {
      _nodos = red.nodos;
      _aristas = red.aristas;
      _resaltados = null;
      _avisoResaltado = null;
      if (_seleccion != null && !_nodos.any((n) => n.clave == _seleccion!.clave)) {
        _seleccion = null;
      }
    });
  }

  Future<void> _cargarHallazgos() async {
    final resumen = await _servicio.resumenGrafo();
    if (mounted) setState(() => _resumen = resumen);
    await _cargarSeccion();
  }

  Future<void> _cargarSeccion() async {
    switch (_seccion) {
      case 0:
        final g = await _servicio.cuentasSospechosas();
        if (mounted) setState(() => _sospechosos = g);
      case 1:
        final v = await _servicio.reputacion(orden: _reputacionAlta ? 'alta' : 'baja');
        if (mounted) setState(() => _reputacion = v);
      case 2:
        final i = await _servicio.incidentes();
        if (mounted) setState(() => _incidentes = i);
      default:
        final z = await _servicio.zonasCalientes(categoria: _filtros.categoria, dias: _filtros.dias);
        if (mounted) setState(() => _zonas = z);
    }
  }

  /// Aplica filtros nuevos: rehace la red y, si cambió el período o la
  /// categoría, también el ranking de zonas.
  void _aplicarFiltros(FiltrosRed nuevos, {FiltrosRed? anteriores}) {
    final antes = anteriores ?? _filtros;
    setState(() => _filtros = nuevos);
    if (antes == nuevos) return;
    final cambiaRanking = antes.periodo != nuevos.periodo || antes.categoria != nuevos.categoria;
    _ejecutar(() async {
      await Future.wait([
        _cargarRed(),
        if (_seccion == _seccionZonas && cambiaRanking) _cargarSeccion(),
      ]);
    });
  }

  void _elegirCategoria(String? codigo) => _aplicarFiltros(_filtros.conCategoria(codigo));

  /// Al soltar la línea de tiempo, el período ya quedó en [_filtros].
  void _soltarPeriodo() {
    _ejecutar(_cargarRed);
    if (_seccion == _seccionZonas) _ejecutar(_cargarSeccion);
  }

  Future<void> _abrirFiltros() async {
    final antes = _filtros;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => HojaFiltrosRed(
        inicial: _filtros,
        categorias: _categoriasDisponibles,
        alCambiar: (nuevos) => setState(() => _filtros = nuevos),
      ),
    );
    _aplicarFiltros(_filtros, anteriores: antes);
  }

  void _elegirSeccion(int seccion) {
    setState(() => _seccion = seccion);
    _ejecutar(_cargarSeccion);
  }

  void _ordenarReputacion(bool alta) {
    setState(() {
      _reputacionAlta = alta;
      _reputacion = null;
    });
    _ejecutar(_cargarSeccion);
  }

  /// Suma a la red lo que no estaba (sin repetir nodos ni relaciones).
  void _mezclar(List<NodoGrafo> nodos, List<AristaGrafo> aristas) {
    final claves = {for (final n in _nodos) n.clave};
    final relaciones = {for (final a in _aristas) '${a.origen}|${a.tipo}|${a.destino}'};
    _nodos = [..._nodos, for (final n in nodos) if (claves.add(n.clave)) n];
    _aristas = [
      ..._aristas,
      for (final a in aristas)
        if (relaciones.add('${a.origen}|${a.tipo}|${a.destino}')) a,
    ];
  }

  Future<void> _sincronizar() => _ejecutar(() async {
    await _servicio.sincronizarGrafo();
    await _cargarRedYHallazgos();
    if (mounted) mostrarAviso(context, 'Red actualizada con los datos de ahora');
  });

  // ---------------------------------------------------------------------------
  // Interacción con la red

  void _alSeleccionar(NodoGrafo n) {
    if (_caminoDesde != null && _caminoDesde!.clave != n.clave) {
      _calcularCamino(_caminoDesde!, n);
      return;
    }
    setState(() => _seleccion = n);
  }

  /// Desde el buscador: completa el camino pendiente o lleva el elemento a la red.
  void _alElegirResultado(NodoGrafo n) =>
      _caminoDesde != null ? _calcularCamino(_caminoDesde!, n) : _mostrarEnRed(n);

  /// Doble toque o "Ampliar": suma sus conexiones sin perder lo que se ve.
  Future<void> _ampliar(NodoGrafo n) => _ejecutar(() async {
    final foco = await _servicio.focoGrafo(n);
    if (!mounted) return;
    setState(() {
      _mezclar(foco.nodos, foco.aristas);
      _seleccion = foco.nodoFoco;
    });
  });

  /// "Ver solo sus conexiones": la red pasa a ser solo ese elemento y su entorno.
  Future<void> _soloConexiones(NodoGrafo n) => _ejecutar(() async {
    final foco = await _servicio.focoGrafo(n);
    if (!mounted) return;
    setState(() {
      _nodos = foco.nodos;
      _aristas = foco.aristas;
      _seleccion = foco.nodoFoco;
      _resaltados = null;
      _avisoResaltado = 'Mostrando solo las conexiones de ${n.etiqueta}';
    });
  });

  /// Desde los hallazgos o el buscador: lo trae a la red y lo resalta.
  Future<void> _mostrarEnRed(NodoGrafo n, {String? aviso}) => _ejecutar(() async {
    final foco = await _servicio.focoGrafo(n);
    if (!mounted) return;
    setState(() {
      _mezclar(foco.nodos, foco.aristas);
      _seleccion = foco.nodoFoco;
      _resaltados = {for (final x in foco.nodos) if (x.anillo <= 1) x.clave};
      _avisoResaltado = aviso ?? 'Resaltado: ${n.etiqueta} y lo conectado directamente';
      _vistaMovil = 1;
    });
    _lienzo.encuadrar();
  });

  void _empezarCamino(NodoGrafo desde) => setState(() {
    _caminoDesde = desde;
    _vistaMovil = 1;
  });

  /// El error del camino se avisa abajo, sin reemplazar la red que se ve.
  Future<void> _calcularCamino(NodoGrafo desde, NodoGrafo hasta) => _ejecutar(() async {
    setState(() => _caminoDesde = null);
    try {
      final camino = await _servicio.camino(desde, hasta);
      if (!mounted) return;
      setState(() {
        _mezclar(camino.nodos, camino.aristas);
        _resaltados = {for (final n in camino.nodos) n.clave};
        _seleccion = hasta;
        _avisoResaltado =
            '${desde.etiqueta} y ${hasta.etiqueta} se conectan en '
            '${camino.pasos} ${camino.pasos == 1 ? 'paso' : 'pasos'}';
        _vistaMovil = 1;
      });
    } on ApiException catch (e) {
      if (mounted) mostrarAviso(context, e.mensaje);
    }
  });

  void _quitarResaltado() => setState(() {
    _resaltados = null;
    _avisoResaltado = null;
  });

  // ---------------------------------------------------------------------------
  // Moderación (con "Deshacer" en las suspensiones)

  /// Confirma, aplica [cambio], vuelve a copiar los datos a Neo4j y recarga.
  /// [alTerminar] recibe el resultado del cambio para armar el aviso.
  Future<void> _moderar<T>({
    required String titulo,
    required String mensaje,
    /// false para acciones que restauran (botón verde).
    bool peligro = true,
    required Future<T> Function() cambio,
    required void Function(T resultado) alTerminar,
  }) async {
    final confirmado = await confirmar(
      context,
      titulo: titulo,
      mensaje: mensaje,
      color: peligro ? RBColores.rojo : RBColores.verde,
    );
    if (!confirmado) return;
    await _ejecutar(() async {
      final resultado = await cambio();
      await _servicio.sincronizarGrafo();
      await _cargarRedYHallazgos();
      if (mounted) alTerminar(resultado);
    });
  }

  SnackBarAction _deshacerSuspension(List<int> ids) =>
      SnackBarAction(label: 'Deshacer', onPressed: () => _reactivar(ids));

  Future<void> _reactivar(List<int> ids) => _ejecutar(() async {
    for (final id in ids) {
      await _servicio.cambiarEstadoUsuario(id, 'ACTIVO');
    }
    await _servicio.sincronizarGrafo();
    await _cargarRedYHallazgos();
    if (mounted) mostrarAviso(context, ids.length == 1 ? 'Cuenta reactivada' : '${ids.length} cuentas reactivadas');
  });

  Future<void> _cambiarCuenta(NodoGrafo n) {
    final suspender = n.estado != 'SUSPENDIDO';
    return _moderar<void>(
      titulo: suspender ? 'Suspender a ${n.etiqueta}' : 'Reactivar a ${n.etiqueta}',
      mensaje: suspender
          ? 'No podrá entrar a la app y se cerrarán sus sesiones. Podrás deshacerlo.'
          : 'Podrá volver a entrar a la app.',
      peligro: suspender,
      cambio: () => _servicio.cambiarEstadoUsuario(n.id, suspender ? 'SUSPENDIDO' : 'ACTIVO'),
      alTerminar: (_) => mostrarAviso(
        context,
        suspender ? 'Cuenta suspendida' : 'Cuenta reactivada',
        accion: suspender ? _deshacerSuspension([n.id]) : null,
      ),
    );
  }

  Future<void> _suspenderGrupo(GrupoSospechoso g) {
    final activos = g.miembros.where((m) => m.estado != 'SUSPENDIDO').length;
    return _moderar<List<int>>(
      titulo: 'Suspender $activos cuentas',
      mensaje: 'Ninguna podrá entrar a la app y se cerrarán sus sesiones. Podrás deshacerlo.',
      cambio: () => _servicio.suspenderGrupoSospechoso(g.id),
      alTerminar: (ids) => mostrarAviso(
        context,
        '${ids.length} cuentas suspendidas',
        accion: ids.isEmpty ? null : _deshacerSuspension(ids),
      ),
    );
  }

  Future<void> _descartarReporte(NodoGrafo n) => _moderar<void>(
    titulo: 'Descartar reporte ${n.etiqueta}',
    mensaje: 'Dejará de mostrarse en el mapa.',
    cambio: () => _servicio.cambiarEstadoReporte(n.id, 'DESCARTADO', motivo: 'Descartado desde la red'),
    alTerminar: (_) => mostrarAviso(context, 'Reporte ${n.etiqueta} descartado'),
  );

  Future<void> _moderarIncidente(int id, String estado) {
    final resolver = estado == 'RESUELTO';
    return _moderar<void>(
      titulo: resolver ? 'Resolver el incidente' : 'Descartar el incidente',
      mensaje: resolver
          ? 'Todos sus reportes vigentes se marcarán como resueltos.'
          : 'Todos sus reportes vigentes dejarán de mostrarse en el mapa.',
      peligro: !resolver,
      cambio: () => _servicio.cambiarEstadoIncidente(
        id,
        estado,
        motivo: resolver ? 'Resuelto desde la red' : 'Descartado desde la red',
      ),
      alTerminar: (_) => mostrarAviso(context, resolver ? 'Incidente resuelto' : 'Incidente descartado'),
    );
  }

  // ---------------------------------------------------------------------------
  // Pantalla

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, c) {
        _compacto = c.maxWidth < 1100;
        if (!_compacto) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 330, child: _panelHallazgos()),
              const VerticalDivider(width: 1, color: RBColores.linea),
              Expanded(child: _zonaRed()),
              const VerticalDivider(width: 1, color: RBColores.linea),
              SizedBox(width: 340, child: _panelDetalle()),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(child: _chipVistaMovil(0, 'Hallazgos', Icons.insights_rounded)),
                  const SizedBox(width: 8),
                  Expanded(child: _chipVistaMovil(1, 'Red', Icons.hub_rounded)),
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _vistaMovil,
                children: [
                  _panelHallazgos(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _zonaRed()),
                      if (_seleccion != null)
                        ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: c.maxHeight * 0.38),
                          child: Material(color: Colors.white, elevation: 8, child: _panelDetalle()),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Celular: alterna entre hallazgos (0) y red (1).
  Widget _chipVistaMovil(int vista, String etiqueta, IconData icono) {
    final activo = _vistaMovil == vista;
    return ChipFiltro(
      etiqueta: etiqueta,
      icono: Icon(icono, size: 18, color: activo ? Colors.white : RBColores.azul),
      activo: activo,
      onTap: () => setState(() => _vistaMovil = vista),
    );
  }

  Widget _filtroCategorias() => FiltroCategoriasRed(
    categoria: _filtros.categoria,
    disponibles: _categoriasDisponibles,
    alElegir: _elegirCategoria,
  );

  Widget _panelHallazgos() => PanelHallazgosRed(
    resumen: _resumen,
    seccion: _seccion,
    sospechosos: _sospechosos,
    reputacion: _reputacion,
    reputacionAlta: _reputacionAlta,
    incidentes: _incidentes,
    zonas: _zonas,
    filtroCategorias: _filtroCategorias(),
    alRecargar: () => _ejecutar(_cargarHallazgos),
    alElegirSeccion: _elegirSeccion,
    alOrdenarReputacion: _ordenarReputacion,
    alMostrarEnRed: _mostrarEnRed,
    alSuspenderGrupo: _suspenderGrupo,
    alModerarIncidente: _moderarIncidente,
  );

  Widget _panelDetalle() => PanelDetalleRed(
    nodo: _seleccion,
    aristas: _aristas,
    sospechosos: _sospechosos,
    filtros: _filtros,
    alCerrar: () => setState(() => _seleccion = null),
    alAmpliar: _ampliar,
    alVerSoloConexiones: _soloConexiones,
    alBuscarCamino: _empezarCamino,
    alCambiarCuenta: _cambiarCuenta,
    alDescartarReporte: _descartarReporte,
    alSuspenderGrupo: _suspenderGrupo,
    alModerarIncidente: _moderarIncidente,
  );

  /// Barra de herramientas y lienzo con sus avisos, leyenda y botones flotantes.
  Widget _zonaRed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BarraHerramientasRed(
          compacto: _compacto,
          cargando: _cargando,
          filtros: _filtros,
          categorias: _categoriasDisponibles,
          buscar: _servicio.buscarEnGrafo,
          alElegirResultado: _alElegirResultado,
          alCambiar: _aplicarFiltros,
          alMoverPeriodo: (p) => setState(() => _filtros = _filtros.conPeriodo(p)),
          alSoltarPeriodo: _soltarPeriodo,
          alAbrirFiltros: _abrirFiltros,
          alSincronizar: _sincronizar,
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: Container(color: RBColores.fondo, child: _lienzoOVacio())),
              if (_caminoDesde != null)
                _arriba(
                  AvisoSobreRed(
                    icono: Icons.route_rounded,
                    texto: 'Elige el segundo elemento (tócalo o búscalo) para ver cómo se conecta con '
                        '${_caminoDesde!.etiqueta}',
                    alCerrar: () => setState(() => _caminoDesde = null),
                    color: RBColores.azul,
                  ),
                )
              else if (_avisoResaltado != null)
                _arriba(
                  AvisoSobreRed(icono: Icons.highlight_rounded, texto: _avisoResaltado!, alCerrar: _quitarResaltado),
                ),
              if (!_compacto || _verLeyenda)
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: LeyendaRed(modo: _filtros.modo, porComunidad: _comunidades),
                ),
              Positioned(right: 12, bottom: 12, child: _botonesFlotantes()),
              if (_cargando)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 3, color: RBColores.azul),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _arriba(Widget aviso) => Positioned(top: 12, left: 12, right: 12, child: aviso);

  Widget _lienzoOVacio() {
    if (_nodos.isEmpty && !_cargando) {
      return EstadoVacio(
        icono: Icons.hub_outlined,
        titulo: _error ?? 'No hay actividad en este período',
        detalle: _error == null
            ? 'Prueba con un período más largo en la línea de tiempo.'
            : 'Toca ⟳ para volver a intentarlo.',
      );
    }
    return LienzoGrafo(
      nodos: _nodos,
      aristas: _aristas,
      seleccion: _seleccion?.clave,
      resaltados: _resaltados,
      colorPorComunidad: _comunidades,
      controlador: _lienzo,
      alSeleccionar: _alSeleccionar,
      alAmpliar: _ampliar,
      alTocarFondo: () => setState(() => _seleccion = null),
    );
  }

  Widget _botonesFlotantes() {
    return Column(
      children: [
        if (_compacto) ...[
          BotonFlotanteRed(
            icono: Icons.info_outline_rounded,
            ayuda: _verLeyenda ? 'Ocultar la leyenda' : 'Ver la leyenda',
            alTocar: () => setState(() => _verLeyenda = !_verLeyenda),
            activo: _verLeyenda,
          ),
          const SizedBox(height: 8),
        ],
        BotonFlotanteRed(icono: Icons.fit_screen_rounded, ayuda: 'Encuadrar', alTocar: _lienzo.encuadrar),
        const SizedBox(height: 8),
        BotonFlotanteRed(
          icono: Icons.palette_outlined,
          ayuda: _comunidades ? 'Colorear por riesgo' : 'Colorear por comunidad',
          alTocar: () => setState(() => _comunidades = !_comunidades),
          activo: _comunidades,
        ),
      ],
    );
  }
}
