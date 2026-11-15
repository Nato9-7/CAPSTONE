import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:rb_alertas/config/mapa_config.dart';
import 'package:rb_alertas/modelos/modelos.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/servicios/aviso_zonas_riesgo.dart';
import 'package:rb_alertas/servicios/estado_alertas_servicio.dart';
import 'package:rb_alertas/servicios/reporte_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/servicios/ubicacion_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/detalle/detalle_incidente_vista.dart';
import 'package:rb_alertas/vistas/mapa/agrupacion_pines.dart';
import 'package:rb_alertas/vistas/mapa/aviso_zonas_dialogo.dart';
import 'package:rb_alertas/vistas/mapa/widgets/botones_mapa.dart';
import 'package:rb_alertas/vistas/mapa/widgets/etiqueta_pin.dart';
import 'package:rb_alertas/vistas/mapa/widgets/filtros_mapa.dart';
import 'package:rb_alertas/vistas/mapa/widgets/hoja_superpuestos.dart';
import 'package:rb_alertas/vistas/mapa/widgets/pin_grupo.dart';
import 'package:rb_alertas/vistas/mapa/widgets/tarjeta_vista_previa.dart';
import 'package:rb_alertas/vistas/reportar/reportar_incidente_vista.dart';
import 'package:rb_alertas/widgets/barra_navegacion_inferior.dart';
import 'package:rb_alertas/widgets/capa_calor.dart';
import 'package:rb_alertas/widgets/dialogos.dart';
import 'package:rb_alertas/widgets/panel_emergencias.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';
import 'package:rb_alertas/widgets/zonas_riesgo_mapa.dart';

/// Mapa principal: reportes vigentes, zonas de riesgo y mapa de calor.
class MapaVista extends StatefulWidget {
  /// Punto donde se abre el mapa (por ejemplo, el reporte recién enviado).
  final LatLng? centrarEn;

  /// Panel de administración: el mapa se ve igual que para los vecinos, pero
  /// sin reportar ni votar, y la tarjeta ofrece moderar el reporte. Devuelve
  /// true si se cambió algo, para recargar los pines.
  final Future<bool> Function(int idReporte)? alModerar;

  const MapaVista({super.key, this.centrarEn, this.alModerar});

  @override
  State<MapaVista> createState() => _MapaVistaState();
}

class _MapaVistaState extends State<MapaVista> {
  // Puerto Montt, Chile (referencia del mockup).

  final _reporteServicio = ReporteServicio();
  final _ubicacionServicio = UbicacionServicio();
  final _mapController = MapController();
  bool _mapaListo = false;

  List<ReporteMapa> _reportes = [];
  // Las categorías salen de la BD: el filtro muestra todas las que existan.
  List<CategoriaIncidente> _categorias = [];
  String? _codigoFiltro;

  LatLng? _miUbicacion;
  bool _buscandoUbicacion = false;

  /// Ubicación en vivo mientras el mapa está abierto, para avisar al entrar
  /// a una zona de riesgo.
  StreamSubscription<Position>? _seguimiento;
  ZonaRiesgo? _zonaActual;

  /// Panel de filtros desplegado bajo el botón "Filtrar".
  bool _filtrosAbiertos = false;

  /// Pin tocado: muestra su etiqueta y la tarjeta de vista previa.
  ReporteMapa? _seleccionado;

  /// Reportes superpuestos abiertos en abanico alrededor de su centro.
  GrupoPines? _abanico;

  /// Grupos calculados para un zoom (redondeado a [_pasoZoomGrupos]) y una
  /// lista de reportes; se recalculan solo si cambia alguno de los dos.
  static const _pasoZoomGrupos = 0.25;
  List<GrupoPines> _grupos = const [];
  ({double zoom, List<ReporteMapa> reportes})? _claveGrupos;
  DetalleReporte? _vistaPrevia;
  bool _votando = false;

  /// Lugares donde se repiten robos o accidentes, en los últimos [_diasZonas].
  static const _diasZonas = 60;
  List<ZonaRiesgo> _zonas = [];
  bool _verZonas = true;
  ZonaRiesgo? _zonaSeleccionada;

  /// Mapa de calor: de lejos (zoom menor a [_zoomCalor]) se ve el calor y de
  /// cerca los círculos con su recomendación. En el panel se puede dejar el
  /// calor siempre a la vista con su botón.
  static const _zoomCalor = 14.0;
  List<PuntoCalor> _calor = [];
  late double _zoom = widget.centrarEn != null ? 16 : 14.5;
  bool _calorSiempre = false;

  bool get _modoAdmin => widget.alModerar != null;

  @override
  void initState() {
    super.initState();
    _cargarReportes();
    _cargarCategorias();
    _cargarZonas();
    _cargarCalor();
    _ubicacionSiHayPermiso();
  }

  @override
  void dispose() {
    _seguimiento?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _cargarCategorias() async {
    try {
      final categorias = await _reporteServicio.obtenerCategorias();
      if (!mounted) return;
      setState(() => _categorias = categorias);
    } catch (_) {
      // Sin categorías solo se pierde el filtro: el mapa sigue funcionando.
    }
  }

  Future<void> _cargarReportes() async {
    try {
      final reportes = await _reporteServicio.obtenerReportes();
      if (!_modoAdmin) {
        EstadoAlertas.revisar(reportes.map((r) => r.id));
        // Enciende la insignia por alertas de zona sin leer aunque el usuario
        // todavia no haya entrado a la pestana Alertas.
        EstadoAlertas.refrescarZonasSinLeer();
      }
      if (!mounted) return;
      setState(() {
        _reportes = reportes;
        // Si el reporte abierto dejó de estar vigente, se cierra su tarjeta.
        if (_seleccionado != null && !reportes.any((r) => r.id == _seleccionado!.id)) {
          _cerrarVistaPrevia();
        }
      });
    } catch (_) {
      if (!mounted) return;
      mostrarAviso(context, 'No se pudieron cargar los reportes del mapa');
    }
  }

  Future<void> _cargarZonas() async {
    try {
      final zonas = await _reporteServicio.obtenerZonasRiesgo(dias: _diasZonas);
      if (!mounted) return;
      setState(() => _zonas = zonas);
      if (_modoAdmin) return;
      final preferencia = await AvisoZonasRiesgo.cargarPreferencia();
      await AvisoZonasRiesgo.sincronizar(zonas);
      if (mounted && preferencia == null && zonas.isNotEmpty) _ofrecerAviso();
    } catch (_) {
      // Sin zonas el mapa funciona igual: solo no se marcan.
    }
  }

  /// Primera vez que hay zonas: se explica el aviso antes de pedir permisos.
  Future<void> _ofrecerAviso() async {
    if (await ofrecerAvisoZonasRiesgo(context) && mounted) _ubicacionSiHayPermiso();
  }

  Future<void> _cambiarAviso(bool activar) async {
    if (!activar) return desactivarAvisoZonasRiesgo(context);
    await activarAvisoZonasRiesgo(context);
    if (mounted) _ubicacionSiHayPermiso();
  }

  /// Un solo mapa de calor: robos y accidentes de tránsito.
  Future<void> _cargarCalor() async {
    try {
      final calor = await _reporteServicio.obtenerCalor(dias: _diasZonas);
      if (mounted) setState(() => _calor = calor);
    } catch (_) {
      // Sin calor el mapa funciona igual.
    }
  }

  bool get _lejos => _zoom < _zoomCalor;

  /// El calor es de robos y accidentes: si se filtra otra categoría, se oculta.
  bool get _filtroAdmiteCalor {
    final filtro = _codigoFiltro?.toUpperCase();
    return filtro == null || filtro == 'ROBO' || filtro == 'ACCIDENTE';
  }

  bool get _mostrarCalor =>
      _verZonas && _filtroAdmiteCalor && _calor.isNotEmpty && (_lejos || _calorSiempre);

  /// Los círculos se dibujan de cerca; en el panel, siempre.
  bool get _mostrarCirculos => !_lejos || _modoAdmin;

  /// Redibuja al cruzar el zoom en que cambia calor por círculos, o cuando el
  /// zoom cambia lo suficiente para que los pines se agrupen distinto.
  void _alMoverMapa(MapCamera camara, bool _) {
    final antes = _lejos;
    final pasoAntes = _zoomAgrupacion;
    _zoom = camara.zoom;
    final cruzoCalor = antes != _lejos;
    final cambioGrupos = pasoAntes != _zoomAgrupacion;
    if ((cruzoCalor || cambioGrupos) && mounted) {
      setState(() {
        if (cruzoCalor && _lejos && !_modoAdmin) _zonaSeleccionada = null;
        // El abanico se calcula para un zoom: al cambiarlo se vuelve a agrupar.
        if (cambioGrupos) _abanico = null;
      });
    }
  }

  double get _zoomAgrupacion => (_zoom / _pasoZoomGrupos).round() * _pasoZoomGrupos;

  /// Zonas a la vista: si se filtra por una categoría, solo las de su tipo
  /// (robos -> seguridad, accidentes -> vial; mascotas -> ninguna).
  List<ZonaRiesgo> get _zonasVisibles {
    if (!_verZonas) return const [];
    final filtro = _codigoFiltro;
    if (filtro == null) return _zonas;
    final tipo = ZonaRiesgo.tipoDeCategoria(filtro);
    return _zonas.where((z) => z.tipo == tipo).toList();
  }

  /// Zona de seguridad donde está el usuario, para avisarle.
  ZonaRiesgo? get _zonaDondeEstoy {
    final yo = _miUbicacion;
    if (yo == null) return null;
    for (final z in _zonasVisibles) {
      if (zonaContiene(z, yo)) return z;
    }
    return null;
  }

  void _seleccionarZona(ZonaRiesgo zona) {
    setState(() {
      _cerrarVistaPrevia();
      _filtrosAbiertos = false;
      _zonaSeleccionada = zona;
    });
  }

  /// Muestra el punto azul sin pedir permiso al abrir la app: solo si el
  /// usuario ya lo había dado antes (por ejemplo, al reportar).
  Future<void> _ubicacionSiHayPermiso() async {
    try {
      final permiso = await Geolocator.checkPermission();
      if (permiso != LocationPermission.always &&
          permiso != LocationPermission.whileInUse) {
        return;
      }
      final punto = await _ubicacionServicio.obtenerUbicacionActual();
      if (!mounted) return;
      setState(() => _miUbicacion = punto);
      _zonaActual = _zonaQueContiene(punto);
      _seguirUbicacion();
    } catch (_) {
      // Sin ubicación el mapa funciona igual.
    }
  }

  ZonaRiesgo? _zonaQueContiene(LatLng punto) {
    for (final z in _zonas) {
      if (zonaContiene(z, punto)) return z;
    }
    return null;
  }

  /// Mientras el mapa está abierto, el punto azul y el banner siguen al
  /// usuario; al entrar a una zona nueva, además llega el aviso.
  void _seguirUbicacion() {
    if (_seguimiento != null || _modoAdmin) return;
    _seguimiento = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 20),
    ).listen(
      (posicion) {
        if (!mounted) return;
        final punto = LatLng(posicion.latitude, posicion.longitude);
        final zona = _zonaQueContiene(punto);
        if (zona != null && zona != _zonaActual) AvisoZonasRiesgo.alEntrar(zona);
        _zonaActual = zona;
        setState(() => _miUbicacion = punto);
      },
      onError: (_) {
        _seguimiento?.cancel();
        _seguimiento = null;
      },
    );
  }

  /// Botón de ubicación: centra el mapa en el usuario.
  Future<void> _irAMiUbicacion() async {
    setState(() => _buscandoUbicacion = true);
    try {
      final punto = await _ubicacionServicio.obtenerUbicacionActual();
      if (!mounted) return;
      setState(() => _miUbicacion = punto);
      _seguirUbicacion();
      if (_mapaListo) _mapController.move(punto, 16);
    } on UbicacionServicioException catch (e) {
      if (mounted) mostrarAviso(context, e.mensaje.split(':').first);
    } catch (_) {
      if (mounted) mostrarAviso(context, 'No pudimos obtener tu ubicación');
    } finally {
      if (mounted) setState(() => _buscandoUbicacion = false);
    }
  }

  List<ReporteMapa> get _reportesVisibles {
    if (_codigoFiltro == null) return _reportes;
    return _reportes.where((r) => r.categoriaCodigo == _codigoFiltro).toList();
  }

  /// Pines y grupos a dibujar. El seleccionado y los del abanico se dibujan
  /// aparte, así que no entran en la agrupación.
  List<GrupoPines> get _gruposVisibles {
    final apartados = {_seleccionado?.id, ...?_abanico?.reportes.map((r) => r.id)};
    final reportes = _reportesVisibles.where((r) => !apartados.contains(r.id)).toList();
    final anterior = _claveGrupos;
    if (anterior == null ||
        anterior.zoom != _zoomAgrupacion ||
        !_mismosReportes(anterior.reportes, reportes)) {
      _claveGrupos = (zoom: _zoomAgrupacion, reportes: reportes);
      _grupos = agruparPines(reportes, _zoomAgrupacion);
    }
    return _grupos;
  }

  static bool _mismosReportes(List<ReporteMapa> a, List<ReporteMapa> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  /// Un grupo que se separa acercando el mapa se encuadra; si sus pines
  /// siguen juntos al zoom de separación, se abren en abanico o en una lista.
  Future<void> _tocarGrupo(GrupoPines grupo) async {
    if (!grupo.siguenJuntos) {
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: [for (final r in grupo.reportes) LatLng(r.latitud, r.longitud)],
          padding: const EdgeInsets.all(90),
          maxZoom: zoomSeparacion,
        ),
      );
      return;
    }
    if (grupo.reportes.length <= maximoAbanico) {
      setState(() {
        _abanico = grupo;
        _cerrarVistaPrevia();
        _filtrosAbiertos = false;
        _zonaSeleccionada = null;
      });
      return;
    }
    final elegido = await elegirReporteSuperpuesto(context, grupo.reportes);
    if (elegido != null && mounted) _seleccionar(elegido);
  }

  // ---------------------------------------------------------------------------
  // Vista previa del reporte

  Future<void> _seleccionar(ReporteMapa reporte) async {
    setState(() {
      _seleccionado = reporte;
      _vistaPrevia = null;
      _filtrosAbiertos = false;
      _zonaSeleccionada = null;
      _abanico = null;
    });
    await _cargarVistaPrevia(reporte.id);
  }

  Future<void> _cargarVistaPrevia(int idReporte) async {
    try {
      final detalle = await _reporteServicio.obtenerDetalle(idReporte);
      if (!mounted || _seleccionado?.id != idReporte) return;
      setState(() => _vistaPrevia = detalle);
    } catch (_) {
      if (!mounted || _seleccionado?.id != idReporte) return;
      mostrarAviso(context, 'No se pudo cargar el reporte');
    }
  }

  void _cerrarVistaPrevia() {
    _seleccionado = null;
    _vistaPrevia = null;
  }

  Future<void> _votar(DetalleReporte d, TipoVoto voto) async {
    if (!Sesion.activa) {
      mostrarAviso(context, 'Inicia sesión para confirmar o desmentir un reporte');
      return;
    }
    setState(() => _votando = true);
    try {
      final resumen = d.miVoto == voto
          ? await _reporteServicio.quitarVoto(d.id)
          : await _reporteServicio.votar(d.id, voto);
      await _cargarVistaPrevia(d.id);
      // Si el voto lo descartó, deja de ser vigente y su pin desaparece.
      if (resumen.estado != d.estado) await _cargarReportes();
    } catch (e) {
      if (mounted) mostrarAviso(context, mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _votando = false);
    }
  }

  Future<void> _abrirDetalle(int idReporte, {bool irAComentarios = false}) async {
    final cambio = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => DetalleIncidenteVista(
          idReporte: idReporte,
          irAComentarios: irAComentarios,
        ),
      ),
    );
    if (!mounted) return;
    // Si se marcó como resuelto, deja de ser vigente: se recargan los pines.
    if (cambio == true) await _cargarReportes();
    if (_seleccionado != null) _cargarVistaPrevia(_seleccionado!.id);
  }

  /// Panel de administración: si se moderó (estado, eliminado...), se recargan
  /// los pines; si dejó de estar vigente, su tarjeta se cierra sola.
  Future<void> _moderar(int idReporte) async {
    final cambio = await widget.alModerar!(idReporte);
    if (!cambio || !mounted) return;
    await _cargarReportes();
    if (_seleccionado != null) _cargarVistaPrevia(_seleccionado!.id);
  }

  Future<void> _abrirReportar() async {
    final punto = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(builder: (context) => const ReportarIncidenteVista()),
    );
    if (punto == null || !mounted) return;
    await _cargarReportes();
    _cargarZonas();
    _cargarCalor();
    if (_mapaListo) _mapController.move(punto, 16);
  }

  // ---------------------------------------------------------------------------
  // Interfaz

  /// Botones compactos para que el mapa quede a la vista.
  static const _altoBoton = 46.0;

  @override
  Widget build(BuildContext context) {
    final circulos = _mostrarCirculos ? _zonasVisibles : const <ZonaRiesgo>[];
    return Scaffold(
      backgroundColor: RBColores.fondo,
      body: Stack(
        children: [
          _mapa(circulos),
          _controlesSuperiores(),
          const Positioned(left: 6, bottom: 2, child: AtribucionMapa()),
          ..._controlesInferiores(),
        ],
      ),
      bottomNavigationBar: _modoAdmin
          ? null
          : const BarraNavegacionInferior(seccionActiva: SeccionApp.mapa),
    );
  }

  /// Mapa con calor, zonas de riesgo, punto del usuario y pines de reportes.
  Widget _mapa(List<ZonaRiesgo> circulos) {
    final seleccionado = _seleccionado;
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: widget.centrarEn ?? MapaConfig.centroPorDefecto,
        initialZoom: widget.centrarEn != null ? 16 : 14.5,
        onMapReady: () => _mapaListo = true,
        onPositionChanged: _alMoverMapa,
        onTap: (_, punto) {
          if (_seleccionado != null || _filtrosAbiertos || _zonaSeleccionada != null || _abanico != null) {
            setState(() {
              _cerrarVistaPrevia();
              _filtrosAbiertos = false;
              _zonaSeleccionada = null;
              _abanico = null;
            });
            return;
          }
          // Tocar dentro de un círculo abre su zona.
          for (final z in circulos) {
            if (zonaContiene(z, punto)) return _seleccionarZona(z);
          }
        },
      ),
      children: [
        capaMapaBase(),
        if (_mostrarCalor) CapaCalor(puntos: _calor),
        if (circulos.isNotEmpty) ...[
          capaZonasRiesgo(circulos),
          // Antes que los pines, para que los reportes queden encima.
          MarkerLayer(
            markers: [for (final z in circulos) marcadorZona(z, () => _seleccionarZona(z))],
          ),
        ],
        if (_abanico != null) _lineasAbanico(_abanico!),
        MarkerLayer(
          markers: [
            if (_miUbicacion != null)
              Marker(point: _miUbicacion!, width: 56, height: 56, child: const PuntoUsuario()),
            for (final grupo in _gruposVisibles)
              if (grupo.esUnico)
                _marcadorReporte(grupo.reportes.first)
              else
                Marker(
                  point: grupo.centro,
                  width: 56,
                  height: 56,
                  child: GestureDetector(
                    onTap: () => _tocarGrupo(grupo),
                    child: PinGrupo(
                      cantidad: grupo.totalReportes,
                      codigoCategoria: grupo.dominante.categoriaCodigo,
                      colorHex: grupo.dominante.colorHex,
                    ),
                  ),
                ),
            ..._marcadoresAbanico(),
            // El seleccionado va al final para quedar por encima del resto.
            if (seleccionado != null) ...[
              Marker(
                point: LatLng(seleccionado.latitud, seleccionado.longitud),
                width: 84,
                height: 84,
                child: PinIncidente(
                  codigo: seleccionado.categoriaCodigo,
                  colorHex: seleccionado.colorHex,
                  seleccionado: true,
                  cantidad: seleccionado.totalReportes,
                ),
              ),
              Marker(
                point: LatLng(seleccionado.latitud, seleccionado.longitud),
                width: 220,
                height: 44 + 40,
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 44),
                  child: Center(child: EtiquetaPin(reporte: seleccionado)),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// Pin de un reporte en su posición, o en [punto] si se dibuja en abanico.
  Marker _marcadorReporte(ReporteMapa reporte, [LatLng? punto]) => Marker(
    point: punto ?? LatLng(reporte.latitud, reporte.longitud),
    width: 48,
    height: 48,
    child: GestureDetector(
      onTap: () => _seleccionar(reporte),
      child: PinIncidente(
        codigo: reporte.categoriaCodigo,
        colorHex: reporte.colorHex,
        cantidad: reporte.totalReportes,
      ),
    ),
  );

  /// Pines del abanico, repartidos en círculo alrededor del punto común.
  List<Marker> _marcadoresAbanico() {
    final abanico = _abanico;
    if (abanico == null) return const [];
    final posiciones = posicionesAbanico(abanico.centro, abanico.reportes.length, _zoom);
    return [
      for (var i = 0; i < abanico.reportes.length; i++) _marcadorReporte(abanico.reportes[i], posiciones[i]),
    ];
  }

  /// Líneas del punto común a cada pin del abanico.
  PolylineLayer _lineasAbanico(GrupoPines abanico) {
    final posiciones = posicionesAbanico(abanico.centro, abanico.reportes.length, _zoom);
    return PolylineLayer(
      polylines: [
        for (final p in posiciones)
          Polyline(points: [abanico.centro, p], color: RBColores.tinta.withValues(alpha: 0.55), strokeWidth: 2),
      ],
    );
  }

  /// Filtros y avisos superpuestos arriba del mapa.
  Widget _controlesSuperiores() {
    final zonaDondeEstoy = _zonaDondeEstoy;
    // Los avisos se ocultan mientras hay una tarjeta o el panel de filtros abierto.
    final despejado = _seleccionado == null && _zonaSeleccionada == null && !_filtrosAbiertos;
    CategoriaIncidente? categoriaFiltro;
    for (final c in _categorias) {
      if (c.codigo == _codigoFiltro) categoriaFiltro = c;
    }
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                BotonFiltrar(
                  categoria: categoriaFiltro,
                  abierto: _filtrosAbiertos,
                  onTap: () => setState(() => _filtrosAbiertos = !_filtrosAbiertos),
                ),
                BotonZonasRiesgo(
                  activo: _verZonas,
                  cantidad: _zonasVisibles.length,
                  onTap: () => setState(() {
                    _verZonas = !_verZonas;
                    if (!_verZonas) _zonaSeleccionada = null;
                  }),
                ),
                // En el panel, el calor se puede dejar fijo a cualquier zoom.
                if (_modoAdmin && _verZonas)
                  BotonMapaCalor(
                    activo: _calorSiempre,
                    onTap: () => setState(() => _calorSiempre = !_calorSiempre),
                  ),
              ],
            ),
            if (_mostrarCalor && despejado) ...[
              const SizedBox(height: 8),
              const LeyendaCalor(texto: 'Robos y accidentes · $_diasZonas días'),
            ],
            if (zonaDondeEstoy != null && despejado) ...[
              const SizedBox(height: 8),
              AvisoZonaRiesgo(zona: zonaDondeEstoy, onTap: () => _seleccionarZona(zonaDondeEstoy)),
            ],
            if (_filtrosAbiertos) ...[
              const SizedBox(height: 8),
              PanelFiltros(
                categorias: _categorias,
                codigoSeleccionado: _codigoFiltro,
                onSeleccionar: _filtrar,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _filtrar(String? codigo) {
    setState(() {
      _codigoFiltro = codigo;
      _filtrosAbiertos = false;
      _abanico = null;
      if (codigo != null && _seleccionado?.categoriaCodigo != codigo) _cerrarVistaPrevia();
    });
  }

  /// Abajo: los botones de acción, o la tarjeta de la zona o del reporte tocado.
  List<Widget> _controlesInferiores() {
    final seleccionado = _seleccionado;
    final zonaSeleccionada = _zonaSeleccionada;
    if (zonaSeleccionada != null) {
      return [
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: TarjetaZonaRiesgo(
            zona: zonaSeleccionada,
            dias: _diasZonas,
            onCerrar: () => setState(() => _zonaSeleccionada = null),
            avisoActivo: _modoAdmin || !AvisoZonasRiesgo.soportado ? null : AvisoZonasRiesgo.activo,
            onCambiarAviso: _cambiarAviso,
          ),
        ),
      ];
    }
    if (seleccionado != null) {
      return [
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: TarjetaVistaPrevia(
            reporte: seleccionado,
            detalle: _vistaPrevia,
            votando: _votando,
            onCerrar: () => setState(_cerrarVistaPrevia),
            onAbrir: () => _abrirDetalle(seleccionado.id),
            onComentarios: () => _abrirDetalle(seleccionado.id, irAComentarios: true),
            onVotar: _votar,
            onModerar: _modoAdmin ? () => _moderar(seleccionado.id) : null,
          ),
        ),
      ];
    }
    return [
      Positioned(
        right: 12,
        bottom: _modoAdmin ? 20 : 20 + _altoBoton + 10,
        child: BotonCuadrado(
          tamano: _altoBoton,
          onTap: _buscandoUbicacion ? null : _irAMiUbicacion,
          child: _buscandoUbicacion
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
              : const Icon(Icons.my_location_rounded, color: RBColores.azul, size: 22),
        ),
      ),
      if (!_modoAdmin)
        Positioned(
          left: 12,
          right: 12,
          bottom: 20,
          // Si los botones no caben, se reparten el ancho y el texto se
          // achica en vez de cortarse.
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: BotonPildora(
                  texto: 'Emergencias',
                  icono: Icons.notification_important_outlined,
                  fondo: Colors.white,
                  color: RBColores.rojo,
                  alto: _altoBoton,
                  onTap: () => mostrarPanelEmergencias(context),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: BotonPildora(
                  texto: 'Reportar',
                  icono: Icons.add_rounded,
                  fondo: RBColores.verde,
                  color: Colors.white,
                  alto: _altoBoton,
                  onTap: _abrirReportar,
                ),
              ),
            ],
          ),
        ),
    ];
  }
}
