import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rb_alertas/servicios/admin_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/lienzo_grafo.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Nombre visible de cada tipo de elemento.
String nombreTipoRed(String tipo) => switch (tipo) {
  'Usuario' => 'Vecino',
  'Reporte' => 'Reporte',
  'Categoria' => 'Categoría',
  'Comuna' => 'Comuna',
  'Localidad' => 'Localidad',
  'ZonaSegura' => 'Zona segura',
  'Coordinacion' => 'Cuentas coordinadas',
  'Incidente' => 'Incidente',
  'Grupo' => 'Grupo de vecinos',
  _ => tipo,
};

String _textoEstado(String? estado) => switch (estado) {
  'PENDIENTE' => 'Pendiente',
  'VALIDADO' => 'Validado',
  'RESUELTO' => 'Resuelto',
  'DESCARTADO' => 'Descartado',
  'EXPIRADO' => 'Expirado',
  'ACTIVO' => 'Cuenta activa',
  'SUSPENDIDO' => 'Suspendida',
  _ => estado ?? '',
};

/// Períodos de la línea de tiempo (null = toda la historia).
const _periodos = <(int?, String)>[
  (7, '7 días'),
  (30, '30 días'),
  (90, '3 meses'),
  (365, '1 año'),
  (null, 'Todo'),
];

const _capasDisponibles = <(String, String, IconData)>[
  ('lugares', 'Lugares', Icons.place_rounded),
  ('categorias', 'Categorías', Icons.category_rounded),
  ('incidentes', 'Incidentes', Icons.layers_rounded),
  ('sospechosos', 'Grupos sospechosos', Icons.gpp_maybe_rounded),
  ('grupos', 'Grupos de vecinos', Icons.groups_rounded),
  ('zonas', 'Zonas seguras', Icons.shield_rounded),
];

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
  final _servicio = AdminServicio();
  final _lienzo = ControladorLienzo();

  // La red que se está mirando (se amplía sin perder lo anterior).
  List<NodoGrafo> _nodos = [];
  List<AristaGrafo> _aristas = [];
  NodoGrafo? _seleccion;
  Set<String>? _resaltados;
  String? _avisoResaltado;

  // Filtros.
  String _modo = 'vecinos';
  int _periodo = _periodos.length - 1;
  final Set<String> _capas = {'lugares', 'incidentes', 'sospechosos', 'grupos'};
  bool _comunidades = false;

  /// Pantalla angosta (celular): filtros en una hoja aparte y leyenda plegada.
  bool _compacto = false;
  bool _verLeyenda = false;

  // "¿Cómo se conecta con…?": el primer elemento elegido.
  NodoGrafo? _caminoDesde;

  // Hallazgos.
  ResumenGrafo? _resumen;
  int _seccion = 0;
  List<GrupoSospechoso>? _sospechosos;
  List<VecinoReputacion>? _reputacion;
  List<IncidenteGrafo>? _incidentes;
  bool _reputacionAlta = false;

  bool _cargando = false;
  String? _error;

  /// En celular: 0 = hallazgos, 1 = red.
  int _vistaMovil = 0;

  @override
  bool get wantKeepAlive => true;

  String get _token => Sesion.token ?? '';

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  // ---------------------------------------------------------------------------
  // Datos

  Future<void> _ejecutar(Future<void> Function() accion) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await accion();
    } on AdminServicioException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo conectar con el servidor');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarTodo() => _ejecutar(() async {
    await Future.wait([_cargarRedSinAviso(), _cargarHallazgos()]);
  });

  Future<void> _cargarRed() => _ejecutar(_cargarRedSinAviso);

  Future<void> _cargarRedSinAviso() async {
    final red = await _servicio.red(
      _token,
      modo: _modo,
      dias: _periodos[_periodo].$1,
      capas: _capas,
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
    final resumen = await _servicio.resumenGrafo(_token);
    if (mounted) setState(() => _resumen = resumen);
    await _cargarSeccion();
  }

  Future<void> _cargarSeccion() async {
    switch (_seccion) {
      case 0:
        final g = await _servicio.cuentasSospechosas(_token);
        if (mounted) setState(() => _sospechosos = g);
      case 1:
        final v = await _servicio.reputacion(_token, orden: _reputacionAlta ? 'alta' : 'baja');
        if (mounted) setState(() => _reputacion = v);
      default:
        final i = await _servicio.incidentes(_token);
        if (mounted) setState(() => _incidentes = i);
    }
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
    await _servicio.sincronizarGrafo(_token);
    await Future.wait([_cargarRedSinAviso(), _cargarHallazgos()]);
    if (mounted) _avisar('Red actualizada con los datos de ahora');
  });

  void _avisar(String mensaje, {SnackBarAction? accion}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje), action: accion));
  }

  // ---------------------------------------------------------------------------
  // Interacción con la red

  void _alSeleccionar(NodoGrafo n) {
    if (_caminoDesde != null && _caminoDesde!.clave != n.clave) {
      _calcularCamino(_caminoDesde!, n);
      return;
    }
    setState(() => _seleccion = n);
  }

  /// Doble toque o "Ampliar": suma sus conexiones sin perder lo que se ve.
  Future<void> _ampliar(NodoGrafo n) => _ejecutar(() async {
    final foco = await _servicio.focoGrafo(_token, n);
    if (!mounted) return;
    setState(() {
      _mezclar(foco.nodos, foco.aristas);
      _seleccion = foco.nodoFoco;
    });
  });

  /// "Ver solo sus conexiones": la red pasa a ser solo ese elemento y su entorno.
  Future<void> _soloConexiones(NodoGrafo n) => _ejecutar(() async {
    final foco = await _servicio.focoGrafo(_token, n);
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
    final foco = await _servicio.focoGrafo(_token, n);
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

  Future<void> _calcularCamino(NodoGrafo desde, NodoGrafo hasta) => _ejecutar(() async {
    setState(() => _caminoDesde = null);
    try {
      final camino = await _servicio.camino(_token, desde, hasta);
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
    } on AdminServicioException catch (e) {
      if (mounted) _avisar(e.mensaje);
    }
  });

  void _quitarResaltado() => setState(() {
    _resaltados = null;
    _avisoResaltado = null;
  });

  // ---------------------------------------------------------------------------
  // Moderación (con "Deshacer" en las suspensiones)

  Future<bool> _confirmar(String titulo, String texto, {Color color = RBColores.rojo}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _despuesDeModerar() async {
    await _servicio.sincronizarGrafo(_token);
    await Future.wait([_cargarRedSinAviso(), _cargarHallazgos()]);
  }

  Future<void> _reactivar(List<int> ids) => _ejecutar(() async {
    for (final id in ids) {
      await _servicio.cambiarEstadoUsuario(_token, id, 'ACTIVO');
    }
    await _despuesDeModerar();
    if (mounted) _avisar(ids.length == 1 ? 'Cuenta reactivada' : '${ids.length} cuentas reactivadas');
  });

  Future<void> _cambiarCuenta(NodoGrafo n) async {
    final suspender = n.estado != 'SUSPENDIDO';
    if (!await _confirmar(
      suspender ? 'Suspender a ${n.etiqueta}' : 'Reactivar a ${n.etiqueta}',
      suspender
          ? 'No podrá entrar a la app y se cerrarán sus sesiones. Podrás deshacerlo.'
          : 'Podrá volver a entrar a la app.',
      color: suspender ? RBColores.rojo : RBColores.verde,
    )) {
      return;
    }
    await _ejecutar(() async {
      await _servicio.cambiarEstadoUsuario(_token, n.id, suspender ? 'SUSPENDIDO' : 'ACTIVO');
      await _despuesDeModerar();
      if (!mounted) return;
      _avisar(
        suspender ? 'Cuenta suspendida' : 'Cuenta reactivada',
        accion: suspender
            ? SnackBarAction(label: 'Deshacer', onPressed: () => _reactivar([n.id]))
            : null,
      );
    });
  }

  Future<void> _suspenderGrupo(GrupoSospechoso g) async {
    final activos = g.miembros.where((m) => m.estado != 'SUSPENDIDO').length;
    if (!await _confirmar(
      'Suspender $activos cuentas',
      'Ninguna podrá entrar a la app y se cerrarán sus sesiones. Podrás deshacerlo.',
    )) {
      return;
    }
    await _ejecutar(() async {
      final ids = await _servicio.suspenderGrupoSospechoso(_token, g.id);
      await _despuesDeModerar();
      if (!mounted) return;
      _avisar(
        '${ids.length} cuentas suspendidas',
        accion: ids.isEmpty
            ? null
            : SnackBarAction(label: 'Deshacer', onPressed: () => _reactivar(ids)),
      );
    });
  }

  Future<void> _descartarReporte(NodoGrafo n) async {
    if (!await _confirmar('Descartar reporte ${n.etiqueta}', 'Dejará de mostrarse en el mapa.')) return;
    await _ejecutar(() async {
      await _servicio.cambiarEstadoReporte(_token, n.id, 'DESCARTADO', motivo: 'Descartado desde la red');
      await _despuesDeModerar();
      if (mounted) _avisar('Reporte ${n.etiqueta} descartado');
    });
  }

  Future<void> _moderarIncidente(int id, String estado) async {
    final resolver = estado == 'RESUELTO';
    if (!await _confirmar(
      resolver ? 'Resolver el incidente' : 'Descartar el incidente',
      resolver
          ? 'Todos sus reportes vigentes se marcarán como resueltos.'
          : 'Todos sus reportes vigentes dejarán de mostrarse en el mapa.',
      color: resolver ? RBColores.verde : RBColores.rojo,
    )) {
      return;
    }
    await _ejecutar(() async {
      await _servicio.cambiarEstadoIncidente(
        _token,
        id,
        estado,
        motivo: resolver ? 'Resuelto desde la red' : 'Descartado desde la red',
      );
      await _despuesDeModerar();
      if (mounted) _avisar(resolver ? 'Incidente resuelto' : 'Incidente descartado');
    });
  }

  // ---------------------------------------------------------------------------
  // Pantalla

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, c) {
        final ancho = c.maxWidth;
        _compacto = ancho < 1100;
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
                  Expanded(
                    child: ChipFiltro(
                      etiqueta: 'Hallazgos',
                      icono: Icon(
                        Icons.insights_rounded,
                        size: 18,
                        color: _vistaMovil == 0 ? Colors.white : RBColores.azul,
                      ),
                      activo: _vistaMovil == 0,
                      onTap: () => setState(() => _vistaMovil = 0),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChipFiltro(
                      etiqueta: 'Red',
                      icono: Icon(
                        Icons.hub_rounded,
                        size: 18,
                        color: _vistaMovil == 1 ? Colors.white : RBColores.azul,
                      ),
                      activo: _vistaMovil == 1,
                      onTap: () => setState(() => _vistaMovil = 1),
                    ),
                  ),
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
                          child: Material(
                            color: Colors.white,
                            elevation: 8,
                            child: _panelDetalle(),
                          ),
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

  // -- Barra de herramientas y lienzo -----------------------------------------

  Widget _zonaRed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _barraHerramientas(),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  color: RBColores.fondo,
                  child: _nodos.isEmpty && !_cargando
                      ? EstadoVacio(
                          icono: Icons.hub_outlined,
                          titulo: _error ?? 'No hay actividad en este período',
                          detalle: _error == null
                              ? 'Prueba con un período más largo en la línea de tiempo.'
                              : 'Toca ⟳ para volver a intentarlo.',
                        )
                      : LienzoGrafo(
                          nodos: _nodos,
                          aristas: _aristas,
                          seleccion: _seleccion?.clave,
                          resaltados: _resaltados,
                          colorPorComunidad: _comunidades,
                          controlador: _lienzo,
                          alSeleccionar: _alSeleccionar,
                          alAmpliar: _ampliar,
                          alTocarFondo: () => setState(() => _seleccion = null),
                        ),
                ),
              ),
              if (_caminoDesde != null)
                _aviso(
                  Icons.route_rounded,
                  'Elige el segundo elemento (tócalo o búscalo) para ver cómo se conecta con '
                  '${_caminoDesde!.etiqueta}',
                  alCerrar: () => setState(() => _caminoDesde = null),
                  color: RBColores.azul,
                )
              else if (_avisoResaltado != null)
                _aviso(Icons.highlight_rounded, _avisoResaltado!, alCerrar: _quitarResaltado),
              if (!_compacto || _verLeyenda) Positioned(left: 12, bottom: 12, child: _leyenda()),
              Positioned(
                right: 12,
                bottom: 12,
                child: Column(
                  children: [
                    if (_compacto) ...[
                      _botonFlotante(
                        Icons.info_outline_rounded,
                        _verLeyenda ? 'Ocultar la leyenda' : 'Ver la leyenda',
                        () => setState(() => _verLeyenda = !_verLeyenda),
                        activo: _verLeyenda,
                      ),
                      const SizedBox(height: 8),
                    ],
                    _botonFlotante(Icons.fit_screen_rounded, 'Encuadrar', _lienzo.encuadrar),
                    const SizedBox(height: 8),
                    _botonFlotante(
                      Icons.palette_outlined,
                      _comunidades ? 'Colorear por riesgo' : 'Colorear por comunidad',
                      () => setState(() => _comunidades = !_comunidades),
                      activo: _comunidades,
                    ),
                  ],
                ),
              ),
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

  Widget _aviso(IconData icono, String texto, {required VoidCallback alCerrar, Color color = RBColores.tinta}) {
    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: Center(
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
      ),
    );
  }

  Widget _botonFlotante(IconData icono, String ayuda, VoidCallback alTocar, {bool activo = false}) {
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

  Widget _barraHerramientas() {
    if (_compacto) {
      return Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          children: [
            Expanded(child: _buscador()),
            IconButton(
              tooltip: 'Filtros',
              onPressed: _abrirFiltros,
              icon: const Icon(Icons.tune_rounded, color: RBColores.azul),
            ),
            IconButton(
              tooltip: 'Actualizar con los datos de ahora',
              onPressed: _cargando ? null : _sincronizar,
              icon: const Icon(Icons.sync_rounded, color: RBColores.azul),
            ),
          ],
        ),
      );
    }
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _buscador()),
              const SizedBox(width: 8),
              _menuCapas(),
              IconButton(
                tooltip: 'Actualizar con los datos de ahora',
                onPressed: _cargando ? null : _sincronizar,
                icon: const Icon(Icons.sync_rounded, color: RBColores.azul),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChipFiltro(
                etiqueta: 'Quién apoya a quién',
                activo: _modo == 'vecinos',
                onTap: () {
                  setState(() => _modo = 'vecinos');
                  _cargarRed();
                },
              ),
              ChipFiltro(
                etiqueta: 'Red completa',
                activo: _modo == 'completa',
                onTap: () {
                  setState(() => _modo = 'completa');
                  _cargarRed();
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          _lineaTiempo(),
        ],
      ),
    );
  }

  /// Celular: vista, línea de tiempo y capas en una hoja que sube desde abajo.
  Future<void> _abrirFiltros() async {
    final antes = (_modo, _periodo, {..._capas});
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, actualizar) {
          void cambiar(VoidCallback cambio) {
            setState(cambio);
            actualizar(() {});
          }

          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                const Text('Vista', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChipFiltro(
                      etiqueta: 'Quién apoya a quién',
                      activo: _modo == 'vecinos',
                      onTap: () => cambiar(() => _modo = 'vecinos'),
                    ),
                    ChipFiltro(
                      etiqueta: 'Red completa',
                      activo: _modo == 'completa',
                      onTap: () => cambiar(() => _modo = 'completa'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Línea de tiempo', style: TextStyle(fontWeight: FontWeight.w800)),
                Slider(
                  value: _periodo.toDouble(),
                  min: 0,
                  max: (_periodos.length - 1).toDouble(),
                  divisions: _periodos.length - 1,
                  label: _periodos[_periodo].$2,
                  activeColor: RBColores.azul,
                  onChanged: (v) => cambiar(() => _periodo = v.round()),
                ),
                Text('Mostrando: ${_periodos[_periodo].$2}', style: const TextStyle(color: RBColores.texto2)),
                if (_modo == 'completa') ...[
                  const SizedBox(height: 16),
                  const Text('Capas', style: TextStyle(fontWeight: FontWeight.w800)),
                  for (final (clave, nombre, icono) in _capasDisponibles)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(icono, color: RBColores.texto2),
                      title: Text(nombre),
                      value: _capas.contains(clave),
                      onChanged: (_) => cambiar(
                        () => _capas.contains(clave) ? _capas.remove(clave) : _capas.add(clave),
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Listo')),
              ],
            ),
          );
        },
      ),
    );
    final despues = (_modo, _periodo, _capas);
    if (antes.$1 != despues.$1 || antes.$2 != despues.$2 || !antes.$3.containsAll(despues.$3) ||
        !despues.$3.containsAll(antes.$3)) {
      _cargarRed();
    }
  }

  /// Línea de tiempo: cuánta historia mostrar (de 7 días a todo).
  Widget _lineaTiempo() {
    return Row(
      children: [
        const Icon(Icons.history_rounded, size: 18, color: RBColores.texto2),
        const SizedBox(width: 4),
        Expanded(
          child: Slider(
            value: _periodo.toDouble(),
            min: 0,
            max: (_periodos.length - 1).toDouble(),
            divisions: _periodos.length - 1,
            label: _periodos[_periodo].$2,
            activeColor: RBColores.azul,
            onChanged: (v) => setState(() => _periodo = v.round()),
            onChangeEnd: (_) => _cargarRed(),
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(
            _periodos[_periodo].$2,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: RBColores.tinta),
          ),
        ),
      ],
    );
  }

  Widget _menuCapas() {
    return PopupMenuButton<String>(
      tooltip: 'Capas de la red completa',
      enabled: _modo == 'completa',
      icon: Icon(Icons.layers_outlined, color: _modo == 'completa' ? RBColores.azul : RBColores.placeholder),
      onSelected: (capa) {
        setState(() => _capas.contains(capa) ? _capas.remove(capa) : _capas.add(capa));
        _cargarRed();
      },
      itemBuilder: (_) => [
        for (final (clave, nombre, icono) in _capasDisponibles)
          CheckedPopupMenuItem(
            value: clave,
            checked: _capas.contains(clave),
            child: Row(
              children: [
                Icon(icono, size: 18, color: RBColores.texto2),
                const SizedBox(width: 8),
                Text(nombre),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buscador() {
    return RawAutocomplete<NodoGrafo>(
      displayStringForOption: (n) => n.etiqueta,
      optionsBuilder: (valor) async {
        final texto = valor.text.trim();
        if (texto.length < 2) return const [];
        try {
          return await _servicio.buscarEnGrafo(_token, texto);
        } catch (_) {
          return const [];
        }
      },
      onSelected: (n) {
        FocusScope.of(context).unfocus();
        if (_caminoDesde != null) {
          _calcularCamino(_caminoDesde!, n);
        } else {
          _mostrarEnRed(n);
        }
      },
      fieldViewBuilder: (context, controlador, foco, alEnviar) => TextField(
        controller: controlador,
        focusNode: foco,
        onSubmitted: (_) => alEnviar(),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Buscar vecino, #reporte o lugar',
          prefixIcon: const Icon(Icons.search_rounded, color: RBColores.texto2),
          filled: true,
          fillColor: RBColores.fondo,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(RBRadios.campo),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      optionsViewBuilder: (context, alElegir, opciones) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320, maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              shrinkWrap: true,
              children: [
                for (final n in opciones)
                  ListTile(
                    dense: true,
                    leading: _iconoNodo(n, 30),
                    title: Text(n.etiqueta, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(nombreTipoRed(n.tipo)),
                    onTap: () => alElegir(n),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _leyenda() {
    Widget punto(Color c, String t) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c, width: 2.5)),
          ),
          const SizedBox(width: 6),
          Text(t, style: const TextStyle(fontSize: 11.5, color: RBColores.tinta)),
        ],
      ),
    );
    Widget linea(Color c, String t) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 14, height: 3, color: c),
          const SizedBox(width: 6),
          Text(t, style: const TextStyle(fontSize: 11.5, color: RBColores.tinta)),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RBColores.linea),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: _comunidades
            ? [
                const Text('Cada color es una comunidad', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                const Text('(vecinos conectados entre sí)', style: TextStyle(fontSize: 11, color: RBColores.texto2)),
              ]
            : [
                punto(RBColores.verde, 'Vecino confiable'),
                punto(colorAmbarRed, 'Dudoso'),
                punto(RBColores.rojo, 'Poco confiable o suspendido'),
                const SizedBox(height: 4),
                linea(RBColores.verde, 'Confirma'),
                linea(RBColores.rojo, 'Desmiente'),
                linea(RBColores.azul, 'Creó'),
                linea(RBColores.petroleo, 'Grupo de vecinos'),
                const Text('Más grueso = más veces', style: TextStyle(fontSize: 11, color: RBColores.texto2)),
              ],
      ),
    );
  }

  // -- Panel de detalle ---------------------------------------------------------

  Widget _iconoNodo(NodoGrafo n, double tamano) {
    final (icono, color) = estiloNodoRed(n);
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(tamano * 0.3)),
      child: Icon(icono, color: Colors.white, size: tamano * 0.55),
    );
  }

  Widget _panelDetalle() {
    final n = _seleccion;
    if (n == null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          Icon(Icons.touch_app_outlined, size: 40, color: RBColores.placeholder),
          SizedBox(height: 12),
          Text(
            'Toca un elemento de la red',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: RBColores.tinta),
          ),
          SizedBox(height: 8),
          Text(
            'Verás qué es, por qué tiene ese color y lo que puedes hacer.\n\n'
            '• Doble toque: ampliar sus conexiones.\n'
            '• Rueda del mouse o dos dedos: acercar y alejar.\n'
            '• Arrastra el fondo para moverte.',
            style: TextStyle(fontSize: 14, height: 1.45, color: RBColores.texto2),
          ),
        ],
      );
    }
    final conexiones = _aristas.where((a) => a.origen == n.clave || a.destino == n.clave).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
      children: [
        Row(
          children: [
            _iconoNodo(n, 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nombreTipoRed(n.tipo).toUpperCase(), style: RBTexto.etiqueta),
                  Text(
                    n.etiqueta,
                    style: const TextStyle(
                      fontFamily: RBFuentes.titulos,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: RBColores.azul,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Cerrar',
              onPressed: () => setState(() => _seleccion = null),
              icon: const Icon(Icons.close_rounded, color: RBColores.texto2),
            ),
          ],
        ),
        if (n.estado != null) ...[
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: _chipEstado(n.estado!)),
        ],
        const SizedBox(height: 14),
        ..._contenidoDetalle(n),
        const SizedBox(height: 6),
        Text(
          '$conexiones conexiones en la red que estás viendo',
          style: const TextStyle(fontSize: 13, color: RBColores.texto2),
        ),
        const SizedBox(height: 14),
        _accionRed(Icons.unfold_more_rounded, 'Ampliar sus conexiones', () => _ampliar(n)),
        _accionRed(Icons.center_focus_strong_rounded, 'Ver solo sus conexiones', () => _soloConexiones(n)),
        _accionRed(Icons.route_rounded, '¿Cómo se conecta con…?', () {
          setState(() {
            _caminoDesde = n;
            _vistaMovil = 1;
          });
        }),
        const SizedBox(height: 10),
        ..._accionesModeracion(n),
      ],
    );
  }

  Widget _accionRed(IconData icono, String texto, VoidCallback alTocar) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      onPressed: alTocar,
      icon: Icon(icono, size: 19),
      label: Text(texto),
    ),
  );

  Widget _chipEstado(String estado) {
    final (fondo, color) = switch (estado) {
      'ACTIVO' || 'RESUELTO' || 'VALIDADO' => (RBColores.verde50, RBColores.verde),
      'SUSPENDIDO' || 'DESCARTADO' => (RBColores.rojo50, RBColores.rojo),
      _ => (RBColores.azul50, RBColores.azul),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(20)),
      child: Text(_textoEstado(estado), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
    );
  }

  /// Barra de 0 a 1 con su explicación (para el desglose de la reputación).
  Widget _barra(String titulo, double valor, String explicacion) {
    final color = valor < 0.35 ? RBColores.rojo : (valor < 0.65 ? colorAmbarRed : RBColores.verde);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(titulo, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
              Text('${(valor * 100).round()}', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: valor, minHeight: 8, backgroundColor: RBColores.linea, color: color),
          ),
          const SizedBox(height: 3),
          Text(explicacion, style: const TextStyle(fontSize: 12.5, height: 1.35, color: RBColores.texto2)),
        ],
      ),
    );
  }

  List<Widget> _contenidoDetalle(NodoGrafo n) {
    final d = n.datos;
    int entero(String c) => (d[c] as num?)?.toInt() ?? 0;
    double decimal(String c) => (d[c] as num?)?.toDouble() ?? 0.5;
    switch (n.tipo) {
      case 'Usuario':
        final puntaje = (d['reputacion'] as num?)?.round();
        if (puntaje == null) return const [];
        final color = puntaje < 35 ? RBColores.rojo : (puntaje < 65 ? colorAmbarRed : RBColores.verde);
        return [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$puntaje',
                style: TextStyle(fontFamily: RBFuentes.titulos, fontSize: 40, height: 1, fontWeight: FontWeight.w800, color: color),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 6, bottom: 5),
                child: Text('/ 100 de reputación', style: TextStyle(color: RBColores.texto2)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('¿Por qué este puntaje?', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _barra(
            'Respaldo de la comunidad',
            decimal('respaldo'),
            '${entero('confirmaciones_recibidas')} confirmaciones y ${entero('desmentidos_recibidos')} '
            'desmentidos recibidos. Pesa más la confirmación de un vecino confiable.',
          ),
          _barra(
            'Historial de sus reportes',
            decimal('historial'),
            '${entero('reportes_buenos')} validados o resueltos y ${entero('reportes_descartados')} descartados.',
          ),
        ];
      case 'Reporte':
        return [
          if (d['categoria'] != null) Text('${d['categoria']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          if (d['descripcion'] != null) ...[
            const SizedBox(height: 4),
            Text('«${d['descripcion']}»', style: const TextStyle(height: 1.4)),
          ],
          const SizedBox(height: 6),
          Text(
            '${entero('confirmaciones')} confirman · ${entero('desmentidos')} desmienten',
            style: const TextStyle(color: RBColores.texto2),
          ),
          if (d['fecha_creacion'] != null)
            Text(
              tiempoRelativoInicio(DateTime.tryParse(d['fecha_creacion'].toString())),
              style: const TextStyle(color: RBColores.texto2),
            ),
          const SizedBox(height: 8),
        ];
      case 'Coordinacion':
        final grupo = _sospechosos?.where((g) => g.id == n.id).firstOrNull;
        return [
          Text(
            'El ${((d['reciprocidad'] as num? ?? 0) * 100).round()} % de las confirmaciones que dan '
            'se quedan dentro del grupo.',
            style: const TextStyle(height: 1.4),
          ),
          if (grupo != null) ...[const SizedBox(height: 10), _evidencia(grupo)],
          const SizedBox(height: 8),
        ];
      case 'Incidente':
        return [
          Text('${entero('total')} reportes del mismo hecho · ${d['categoria'] ?? ''}'),
          const SizedBox(height: 4),
          const Text(
            'Misma categoría, a menos de 300 m y con menos de 3 horas de diferencia.',
            style: TextStyle(fontSize: 13, color: RBColores.texto2),
          ),
          const SizedBox(height: 8),
        ];
      case 'ZonaSegura':
        return [if (d['radio'] != null) Text('Radio de ${d['radio']} m'), const SizedBox(height: 8)];
      case 'Grupo':
        // Miembros y reportes compartidos según lo que se ve en la red.
        final miembros = _aristas.where((a) => a.tipo == 'INTEGRA' && a.destino == n.clave).length;
        final compartidos = _aristas.where((a) => a.tipo == 'COMPARTIDO_EN' && a.destino == n.clave).length;
        return [
          Text(
            d['activo'] == false ? 'Grupo cerrado' : 'Grupo activo',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '$miembros ${miembros == 1 ? 'miembro' : 'miembros'} y $compartidos '
            '${compartidos == 1 ? 'reporte compartido' : 'reportes compartidos'} en esta vista'
            '${d['radio'] != null ? ' · área de ${d['radio']} m' : ''}.',
            style: const TextStyle(color: RBColores.texto2, height: 1.4),
          ),
          const SizedBox(height: 4),
          const Text(
            'Usa «Ampliar sus conexiones» para ver todos sus miembros y reportes.',
            style: TextStyle(fontSize: 12.5, color: RBColores.texto2),
          ),
          const SizedBox(height: 8),
        ];
      default:
        return const [];
    }
  }

  List<Widget> _accionesModeracion(NodoGrafo n) {
    if (n.tipo == 'Usuario' && n.datos['es_admin'] != true) {
      final suspendido = n.estado == 'SUSPENDIDO';
      return [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: suspendido ? RBColores.verde : RBColores.rojo),
          onPressed: () => _cambiarCuenta(n),
          icon: Icon(suspendido ? Icons.lock_open_rounded : Icons.block_rounded, size: 18),
          label: Text(suspendido ? 'Reactivar cuenta' : 'Suspender cuenta'),
        ),
      ];
    }
    if (n.tipo == 'Reporte' && n.estado != 'DESCARTADO') {
      return [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: RBColores.rojo),
          onPressed: () => _descartarReporte(n),
          icon: const Icon(Icons.block_rounded, size: 18),
          label: const Text('Descartar reporte'),
        ),
      ];
    }
    if (n.tipo == 'Coordinacion') {
      final grupo = _sospechosos?.where((g) => g.id == n.id).firstOrNull;
      if (grupo == null) return const [];
      return [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: RBColores.rojo),
          onPressed: () => _suspenderGrupo(grupo),
          icon: const Icon(Icons.block_rounded, size: 18),
          label: const Text('Suspender el grupo'),
        ),
      ];
    }
    if (n.tipo == 'Incidente') return [_botonesIncidente(n.id)];
    return const [];
  }

  Widget _botonesIncidente(int id) {
    const relleno = EdgeInsets.symmetric(horizontal: 10, vertical: 14);
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: RBColores.verde, padding: relleno),
            onPressed: () => _moderarIncidente(id, 'RESUELTO'),
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
            onPressed: () => _moderarIncidente(id, 'DESCARTADO'),
            child: const Text('Descartar', maxLines: 1),
          ),
        ),
      ],
    );
  }

  // -- Panel de hallazgos -------------------------------------------------------

  static const _secciones = [
    ('Sospechosos', Icons.gpp_maybe_rounded),
    ('Reputación', Icons.verified_user_rounded),
    ('Incidentes', Icons.layers_rounded),
  ];

  static const _explicaciones = [
    'Cuentas que se confirman los reportes entre ellas mucho más que a los demás. '
        'Puede ser una persona con varias cuentas inflando sus reportes.',
    'De 0 a 100. Sube si lo confirman vecinos confiables y si sus reportes terminan '
        'validados; baja con desmentidos y reportes descartados.',
    'Reportes del mismo hecho (misma categoría, a menos de 300 m y 3 horas) que la app '
        'muestra como un solo incidente.',
  ];

  Widget _panelHallazgos() {
    final r = _resumen;
    final contadores = [r?.sospechosos, r?.bajaReputacion, r?.incidentesAbiertos];
    return Container(
      color: Colors.white,
      child: RefreshIndicator(
        onRefresh: () => _ejecutar(_cargarHallazgos),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            const Text(
              'Hallazgos',
              style: TextStyle(fontFamily: RBFuentes.titulos, fontSize: 22, fontWeight: FontWeight.w800, color: RBColores.azul),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final (i, (nombre, icono)) in _secciones.indexed) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(child: _botonSeccion(i, nombre, icono, contadores[i])),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(_explicaciones[_seccion], style: const TextStyle(fontSize: 13.5, height: 1.4, color: RBColores.texto2)),
            const SizedBox(height: 12),
            ...switch (_seccion) {
              0 => _listaSospechosos(),
              1 => _listaReputacion(),
              _ => _listaIncidentes(),
            },
          ],
        ),
      ),
    );
  }

  Widget _botonSeccion(int i, String nombre, IconData icono, int? contador) {
    final activa = _seccion == i;
    return Material(
      color: activa ? RBColores.azul : RBColores.fondo,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: activa
            ? null
            : () {
                setState(() => _seccion = i);
                _ejecutar(_cargarSeccion);
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            children: [
              Icon(icono, size: 20, color: activa ? Colors.white : RBColores.azul),
              const SizedBox(height: 3),
              Text(
                nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: activa ? Colors.white : RBColores.tinta),
              ),
              if (contador != null && contador > 0)
                Text(
                  '$contador',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: activa ? Colors.white : (i == 2 ? RBColores.azul : RBColores.rojo),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vacio(String texto) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30),
    child: Column(
      children: [
        const Icon(Icons.check_circle_outline_rounded, size: 36, color: RBColores.verde),
        const SizedBox(height: 8),
        Text(texto, textAlign: TextAlign.center, style: const TextStyle(color: RBColores.texto2)),
      ],
    ),
  );

  Widget get _cargandoLista => const Padding(
    padding: EdgeInsets.symmetric(vertical: 30),
    child: Center(child: CircularProgressIndicator(color: RBColores.azul)),
  );

  /// "¿Por qué?": los votos exactos que hacen sospechoso al grupo.
  Widget _evidencia(GrupoSospechoso g) {
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

  List<Widget> _listaSospechosos() {
    final grupos = _sospechosos;
    if (grupos == null) return [_cargandoLista];
    if (grupos.isEmpty) return [_vacio('No hay cuentas que se confirmen entre ellas.')];
    return [
      for (final g in grupos)
        TarjetaRB(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          colorBorde: g.nivel == 'ALTO' ? RBColores.rojo : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.gpp_maybe_rounded, color: RBColores.rojo),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${g.miembros.length} cuentas coordinadas',
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    g.nivel == 'ALTO' ? 'Sospecha alta' : 'Sospecha media',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: g.nivel == 'ALTO' ? RBColores.rojo : RBColores.texto2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [for (final m in g.miembros) m.etiqueta].join(' · '),
                style: const TextStyle(fontSize: 13, color: RBColores.texto2),
              ),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: const Text('¿Por qué?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: RBColores.azul)),
                  children: [_evidencia(g)],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _mostrarEnRed(g.nodo, aviso: 'Resaltado: el grupo y sus votos entre ellas'),
                      icon: const Icon(Icons.hub_outlined, size: 18),
                      label: const Text('Ver en la red'),
                    ),
                  ),
                  if (g.miembros.any((m) => m.estado != 'SUSPENDIDO')) ...[
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Suspender el grupo',
                      style: IconButton.styleFrom(backgroundColor: RBColores.rojo),
                      onPressed: () => _suspenderGrupo(g),
                      icon: const Icon(Icons.block_rounded),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _listaReputacion() {
    final vecinos = _reputacion;
    return [
      Row(
        children: [
          ChipFiltro(
            etiqueta: 'Menos confiables',
            activo: !_reputacionAlta,
            onTap: () {
              setState(() {
                _reputacionAlta = false;
                _reputacion = null;
              });
              _ejecutar(_cargarSeccion);
            },
          ),
          const SizedBox(width: 8),
          ChipFiltro(
            etiqueta: 'Más confiables',
            activo: _reputacionAlta,
            onTap: () {
              setState(() {
                _reputacionAlta = true;
                _reputacion = null;
              });
              _ejecutar(_cargarSeccion);
            },
          ),
        ],
      ),
      const SizedBox(height: 10),
      if (vecinos == null)
        _cargandoLista
      else if (vecinos.isEmpty)
        _vacio('Todavía no hay vecinos con reportes o votos.')
      else
        for (final v in vecinos)
          TarjetaRB(
            onTap: () => _mostrarEnRed(v.nodo),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: v.puntaje / 100,
                        strokeWidth: 4.5,
                        backgroundColor: RBColores.linea,
                        color: v.puntaje < 35
                            ? RBColores.rojo
                            : (v.puntaje < 65 ? colorAmbarRed : RBColores.verde),
                      ),
                      Text('${v.puntaje}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(v.nodo.etiqueta, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          if (v.sospechoso) ...[
                            const SizedBox(width: 4),
                            const Tooltip(
                              message: 'Está en un grupo sospechoso',
                              child: Icon(Icons.gpp_maybe_rounded, size: 16, color: RBColores.rojo),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '${v.reportes} reportes · ${v.confirmaciones} confirmaciones · '
                        '${v.descartados} descartados',
                        style: const TextStyle(fontSize: 12.5, color: RBColores.texto2),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: RBColores.placeholder),
              ],
            ),
          ),
    ];
  }

  List<Widget> _listaIncidentes() {
    final lista = _incidentes;
    if (lista == null) return [_cargandoLista];
    if (lista.isEmpty) return [_vacio('No hay incidentes abiertos con más de un reporte.')];
    return [
      for (final i in lista)
        TarjetaRB(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _iconoNodo(i.nodo, 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i.categoria, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                        Text(
                          [
                            '${i.reportes.length} reportes',
                            if (i.lugar != null) i.lugar!,
                            if (i.ultimo != null) tiempoRelativoInicio(i.ultimo),
                          ].join(' · '),
                          style: const TextStyle(fontSize: 12.5, color: RBColores.texto2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                onPressed: () => _mostrarEnRed(i.nodo, aviso: 'Resaltado: los reportes del mismo hecho'),
                icon: const Icon(Icons.hub_outlined, size: 18),
                label: const Text('Ver en la red'),
              ),
              _botonesIncidente(i.id),
            ],
          ),
        ),
    ];
  }
}
