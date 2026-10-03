import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rb_alertas/servicios/estado_alertas_servicio.dart';
import 'package:rb_alertas/servicios/notificaciones_servicio.dart';
import 'package:rb_alertas/servicios/reporte_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/servicios/ubicacion_servicio.dart';
import 'package:rb_alertas/vistas/detalle_incidente_vista.dart';
import 'package:rb_alertas/vistas/inicio_sesion_vista.dart';
import 'package:rb_alertas/vistas/zonas_seguras_vista.dart';
import 'package:rb_alertas/widgets/barra_navegacion_inferior.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';

const _colorAzul = Color(0xFF0056D2);
const _colorFondo = Color(0xFFF7F8FC);
const _colorTitulo = Color(0xFF111827);
const _colorTextoGris = Color(0xFF6B7280);
const _colorBorde = Color(0xFFE5E7EB);
const _colorVerde = Color(0xFF16A34A);
const _colorRojo = Color(0xFFDC2626);
const _colorAmbar = Color(0xFFD97706);

/// Punto de referencia cuando todavía no se conoce la ubicación del
const _centroPorDefecto = LatLng(-41.4693, -72.9424);

/// Radio en kilómetros que se consulta a la API para las alertas cercanas.
const _radioKm = 2.0;

/// Antigüedad hasta la que una alerta se muestra en la sección "Recientes".
const _ventanaRecientes = Duration(hours: 2);

String tiempoRelativo(DateTime? fecha) {
  if (fecha == null) return '';
  final diferencia = DateTime.now().difference(fecha);
  if (diferencia.isNegative || diferencia.inMinutes < 1) return 'Recién';
  if (diferencia.inMinutes < 60) return 'hace ${diferencia.inMinutes} min';
  if (diferencia.inHours < 24) return 'hace ${diferencia.inHours} h';
  if (diferencia.inDays == 1) return 'Ayer';
  if (diferencia.inDays < 7) return 'hace ${diferencia.inDays} días';
  return '${fecha.day.toString().padLeft(2, '0')}/'
      '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
}

/// Pantalla "Alertas": incidentes vigentes cerca del usuario e historial
class AlertasVista extends StatefulWidget {
  final int pestanaInicial;

  const AlertasVista({super.key, this.pestanaInicial = 0});

  @override
  State<AlertasVista> createState() => _AlertasVistaState();
}

class _AlertasVistaState extends State<AlertasVista>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.pestanaInicial.clamp(0, 2),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorFondo,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.notifications_rounded,
                    color: _colorAzul,
                    size: 26,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Alertas',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _colorTitulo,
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            _SelectorPestanas(controlador: _tabs),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: const [
                  _PanelCercanas(),
                  _PanelMisZonas(),
                  _PanelMisReportes(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const BarraNavegacionInferior(
        seccionActiva: SeccionApp.alertas,
      ),
    );
  }
}

class _SelectorPestanas extends StatelessWidget {
  final TabController controlador;

  const _SelectorPestanas({required this.controlador});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _colorBorde),
      ),
      child: TabBar(
        controller: controlador,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: _colorAzul,
          borderRadius: BorderRadius.circular(20),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: _colorTextoGris,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        tabs: const [
          Tab(height: 36, text: 'Cerca de ti'),
          Tab(height: 36, text: 'Mis zonas'),
          Tab(height: 36, text: 'Mis reportes'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pestaña 1: alertas activas cerca del usuario
// ---------------------------------------------------------------------------

class _PanelCercanas extends StatefulWidget {
  const _PanelCercanas();

  @override
  State<_PanelCercanas> createState() => _PanelCercanasState();
}

class _PanelCercanasState extends State<_PanelCercanas>
    with AutomaticKeepAliveClientMixin {
  final _reporteServicio = ReporteServicio();
  final _ubicacionServicio = UbicacionServicio();

  LatLng? _punto;
  List<ReporteCercano> _alertas = [];
  List<CategoriaIncidente> _categorias = [];
  String? _codigoFiltro;
  bool _cargando = true;
  String? _error;
  // Aviso cuando no se pudo leer el GPS y se usa el centro por defecto.
  String? _avisoUbicacion;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargarCategorias();
    _cargarTodo();
  }

  Future<void> _cargarCategorias() async {
    try {
      final categorias = await _reporteServicio.obtenerCategorias();
      if (!mounted) return;
      setState(() => _categorias = categorias);
    } catch (_) {
      // Sin categorías solo se pierden los filtros; la lista sigue sirviendo.
    }
  }

  Future<void> _cargarTodo() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    LatLng punto;
    String? aviso;
    try {
      punto = await _ubicacionServicio.obtenerUbicacionActual();
    } on UbicacionServicioException catch (e) {
      punto = _centroPorDefecto;
      aviso = e.mensaje;
    } catch (_) {
      punto = _centroPorDefecto;
      aviso =
          'No pudimos obtener tu ubicación: mostramos el centro de la comuna';
    }

    try {
      final cercanas = await _reporteServicio.obtenerCercanos(
        latitud: punto.latitude,
        longitud: punto.longitude,
        radioKm: _radioKm,
      );
      EstadoAlertas.marcarVistos(cercanas.reportes.map((r) => r.id));
      if (!mounted) return;
      setState(() {
        _punto = punto;
        _alertas = cercanas.reportes;
        _avisoUbicacion = aviso;
        _cargando = false;
      });
    } on ReporteServicioException catch (e) {
      if (!mounted) return;
      setState(() {
        _punto = punto;
        _error = e.mensaje;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _punto = punto;
        _error = 'No se pudo conectar con el servidor';
        _cargando = false;
      });
    }
  }

  List<ReporteCercano> get _visibles {
    if (_codigoFiltro == null) return _alertas;
    return _alertas.where((a) => a.categoriaCodigo == _codigoFiltro).toList();
  }

  Future<void> _abrirDetalle(int idReporte) async {
    final cambio = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => DetalleIncidenteVista(idReporte: idReporte),
      ),
    );
    // Si el reporte se marcó como resuelto deja de estar vigente.
    if (cambio == true && mounted) _cargarTodo();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: _colorAzul));
    }
    if (_error != null) {
      return _EstadoVacio(
        icono: Icons.cloud_off_rounded,
        titulo: 'No se pudieron cargar las alertas',
        detalle: _error!,
        accion: 'Reintentar',
        onAccion: _cargarTodo,
      );
    }

    final visibles = _visibles;
    final ahora = DateTime.now();
    final recientes = visibles
        .where(
          (a) =>
              a.fechaCreacion != null &&
              ahora.difference(a.fechaCreacion!) <= _ventanaRecientes,
        )
        .toList();
    final anteriores = visibles.where((a) => !recientes.contains(a)).toList();

    return RefreshIndicator(
      color: _colorAzul,
      onRefresh: _cargarTodo,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _TarjetaImpactoLocal(
            punto: _punto ?? _centroPorDefecto,
            alertas: _alertas,
            onRecargar: _cargarTodo,
          ),
          if (_avisoUbicacion != null) ...[
            const SizedBox(height: 10),
            _Aviso(texto: _avisoUbicacion!),
          ],
          const SizedBox(height: 14),
          _ChipsCategorias(
            categorias: _categorias,
            codigoSeleccionado: _codigoFiltro,
            onSeleccionar: (codigo) => setState(() => _codigoFiltro = codigo),
          ),
          const SizedBox(height: 18),
          if (visibles.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: _EstadoVacio(
                icono: Icons.notifications_off_outlined,
                titulo: 'Sin alertas cerca de ti',
                detalle: 'No hay incidentes vigentes en un radio de 2 km. Desliza hacia abajo para actualizar.',
              ),
            ),
          if (recientes.isNotEmpty) ...[
            const _TituloSeccion('RECIENTES'),
            const SizedBox(height: 8),
            for (final alerta in recientes)
              _FilaAlerta(
                alerta: alerta,
                destacada: true,
                onTap: () => _abrirDetalle(alerta.id),
              ),
          ],
          if (anteriores.isNotEmpty) ...[
            const SizedBox(height: 18),
            const _TituloSeccion('ANTERIORES'),
            const SizedBox(height: 8),
            for (final alerta in anteriores)
              _FilaAlerta(
                alerta: alerta,
                destacada: false,
                onTap: () => _abrirDetalle(alerta.id),
              ),
          ],
        ],
      ),
    );
  }
}

/// Encabezado con el mini mapa y el recuento de incidentes en el radio.
class _TarjetaImpactoLocal extends StatelessWidget {
  final LatLng punto;
  final List<ReporteCercano> alertas;
  final VoidCallback onRecargar;

  const _TarjetaImpactoLocal({
    required this.punto,
    required this.alertas,
    required this.onRecargar,
  });

  @override
  Widget build(BuildContext context) {
    final total = alertas.length;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 150,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: punto,
                initialZoom: 13.5,
                // Mapa decorativo: la interacción vive en la pestaña Mapa.
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.rbalertas.rb_alertas',
                ),
                MarkerLayer(
                  markers: [
                    for (final alerta in alertas)
                      Marker(
                        point: LatLng(alerta.latitud, alerta.longitud),
                        width: 16,
                        height: 16,
                        child: Container(
                          decoration: BoxDecoration(
                            color: colorCategoria(
                              alerta.categoriaCodigo,
                              colorHex: alerta.colorHex,
                            ).withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                        ),
                      ),
                    Marker(
                      point: punto,
                      width: 18,
                      height: 18,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _colorAzul,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // Degradado para que el texto se lea sobre cualquier zona del mapa.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [Color(0xCC000000), Color(0x11000000)],
                ),
              ),
              child: SizedBox.expand(),
            ),
            Positioned(
              left: 16,
              bottom: 16,
              right: 70,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Impacto Local',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    total == 1
                        ? '1 incidente en tu radio (${_radioKm.toStringAsFixed(0)} km)'
                        : '$total incidentes en tu radio (${_radioKm.toStringAsFixed(0)} km)',
                    style: const TextStyle(
                      color: Color(0xFFE5E7EB),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 14,
              bottom: 14,
              child: Material(
                color: _colorAzul,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onRecargar,
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(
                      Icons.my_location_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaAlerta extends StatelessWidget {
  final ReporteCercano alerta;
  // Las recientes llevan una franja lateral del color de su categoría.
  final bool destacada;
  final VoidCallback onTap;

  const _FilaAlerta({
    required this.alerta,
    required this.destacada,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = colorCategoria(
      alerta.categoriaCodigo,
      colorHex: alerta.colorHex,
    );
    final referencia = alerta.direccion?.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _colorBorde),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            children: [
              if (destacada) Container(width: 4, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: destacada ? 1 : 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          iconoCategoria(alerta.categoriaCodigo),
                          size: 21,
                          color: destacada ? Colors.white : color,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              alerta.categoria,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _colorTitulo,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(
                                  Icons.near_me_outlined,
                                  size: 13,
                                  color: _colorTextoGris,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    referencia == null || referencia.isEmpty
                                        ? 'A ${alerta.distanciaLegible} de ti'
                                        : '$referencia · a ${alerta.distanciaLegible}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: _colorTextoGris,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        tiempoRelativo(alerta.fechaCreacion),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: destacada ? _colorRojo : _colorTextoGris,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pestaña 2: historial de reportes del usuario
// ---------------------------------------------------------------------------

enum _FiltroHistorial { todos, activas, resueltas, vencidas }

class _PanelMisReportes extends StatefulWidget {
  const _PanelMisReportes();

  @override
  State<_PanelMisReportes> createState() => _PanelMisReportesState();
}

class _PanelMisReportesState extends State<_PanelMisReportes>
    with AutomaticKeepAliveClientMixin {
  final _reporteServicio = ReporteServicio();

  List<MiReporte> _reportes = [];
  _FiltroHistorial _filtro = _FiltroHistorial.todos;
  bool _cargando = true;
  String? _error;
  bool _sinSesion = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final token = Sesion.token;
    if (token == null || token.isEmpty) {
      setState(() {
        _sinSesion = true;
        _cargando = false;
      });
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
      _sinSesion = false;
    });
    try {
      final reportes = await _reporteServicio.obtenerMisReportes(token);
      if (!mounted) return;
      setState(() {
        _reportes = reportes;
        _cargando = false;
      });
    } on ReporteServicioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.mensaje;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo conectar con el servidor';
        _cargando = false;
      });
    }
  }

  List<MiReporte> get _visibles {
    return switch (_filtro) {
      _FiltroHistorial.todos => _reportes,
      _FiltroHistorial.activas =>
        _reportes.where((r) => r.estado == EstadoMiReporte.activa).toList(),
      _FiltroHistorial.resueltas =>
        _reportes.where((r) => r.estado == EstadoMiReporte.resuelta).toList(),
      _FiltroHistorial.vencidas =>
        _reportes.where((r) => r.estado == EstadoMiReporte.vencida).toList(),
    };
  }

  Future<void> _abrirDetalle(int idReporte) async {
    final cambio = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => DetalleIncidenteVista(idReporte: idReporte),
      ),
    );
    if (cambio == true && mounted) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_sinSesion) {
      return _EstadoVacio(
        icono: Icons.lock_outline_rounded,
        titulo: 'Inicia sesión',
        detalle:
            'Necesitas una sesión abierta para ver tu historial de reportes.',
        accion: 'Iniciar sesión',
        onAccion: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const InicioSesionVista()),
          );
          if (mounted) _cargar();
        },
      );
    }
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: _colorAzul));
    }
    if (_error != null) {
      return _EstadoVacio(
        icono: Icons.cloud_off_rounded,
        titulo: 'No se pudo cargar tu historial',
        detalle: _error!,
        accion: 'Reintentar',
        onAccion: _cargar,
      );
    }

    final visibles = _visibles;

    return RefreshIndicator(
      color: _colorAzul,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Text(
            'Mis Reportes',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _colorTitulo,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Historial de alertas reportadas en tu zona.',
            style: TextStyle(fontSize: 13.5, color: _colorTextoGris),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final opcion in _FiltroHistorial.values) ...[
                  _Chip(
                    etiqueta: switch (opcion) {
                      _FiltroHistorial.todos => 'Todos',
                      _FiltroHistorial.activas => 'Activas',
                      _FiltroHistorial.resueltas => 'Resueltas',
                      _FiltroHistorial.vencidas => 'Vencidas',
                    },
                    activo: _filtro == opcion,
                    color: _colorAzul,
                    onTap: () => setState(() => _filtro = opcion),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (visibles.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: _EstadoVacio(
                icono: Icons.inbox_outlined,
                titulo: _reportes.isEmpty
                    ? 'Todavía no has reportado nada'
                    : 'Sin reportes en este filtro',
                detalle: _reportes.isEmpty
                    ? 'Cuando envíes un reporte aparecerá aquí con su estado.'
                    : 'Prueba con otro filtro para ver el resto de tus reportes.',
              ),
            ),
          for (final reporte in visibles)
            _TarjetaMiReporte(
              reporte: reporte,
              onTap: () => _abrirDetalle(reporte.id),
            ),
        ],
      ),
    );
  }
}

class _TarjetaMiReporte extends StatelessWidget {
  final MiReporte reporte;
  final VoidCallback onTap;

  const _TarjetaMiReporte({required this.reporte, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = colorCategoria(
      reporte.categoriaCodigo,
      colorHex: reporte.colorHex,
    );
    final imagenUrl = reporte.imagenUrl;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _colorBorde),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 170,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imagenUrl != null)
                    Image.network(
                      imagenUrl,
                      fit: BoxFit.cover,
                      // Si la evidencia no carga, se muestra el marcador de
                      // categoría en lugar de un recuadro roto.
                      errorBuilder: (context, error, stack) =>
                          _PortadaCategoria(color: color, reporte: reporte),
                    )
                  else
                    _PortadaCategoria(color: color, reporte: reporte),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: _InsigniaEstado(estado: reporte.estado),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          reporte.categoria,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: _colorTitulo,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          tiempoRelativo(reporte.fechaCreacion),
                          style: const TextStyle(
                            fontSize: 12,
                            color: _colorTextoGris,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    reporte.descripcion,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.35,
                      color: _colorTextoGris,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: _colorBorde),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 15,
                        color: _colorTextoGris,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          reporte.zona ??
                              reporte.direccion ??
                              'Ubicación registrada',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: _colorTextoGris,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.thumb_up_alt_outlined,
                        size: 15,
                        color: _colorTextoGris,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${reporte.apoyos} '
                        '${reporte.apoyos == 1 ? 'Apoyo' : 'Apoyos'}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: _colorTextoGris,
                        ),
                      ),
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

/// Portada de respaldo para los reportes sin foto.
class _PortadaCategoria extends StatelessWidget {
  final Color color;
  final MiReporte reporte;

  const _PortadaCategoria({required this.color, required this.reporte});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color.withValues(alpha: 0.10),
      child: Center(
        child: Icon(
          iconoCategoria(reporte.categoriaCodigo),
          size: 46,
          color: color.withValues(alpha: 0.65),
        ),
      ),
    );
  }
}

class _InsigniaEstado extends StatelessWidget {
  final EstadoMiReporte estado;

  const _InsigniaEstado({required this.estado});

  @override
  Widget build(BuildContext context) {
    final (texto, color, icono) = switch (estado) {
      EstadoMiReporte.activa => ('Activa', _colorRojo, Icons.error_outline),
      EstadoMiReporte.resuelta => (
        'Resuelta',
        _colorVerde,
        Icons.check_circle_outline,
      ),
      EstadoMiReporte.vencida => (
        'Vencida',
        _colorAmbar,
        Icons.schedule_rounded,
      ),
      EstadoMiReporte.descartada => (
        'Descartada',
        _colorTextoGris,
        Icons.block_rounded,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            texto,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Piezas compartidas
// ---------------------------------------------------------------------------

class _ChipsCategorias extends StatelessWidget {
  final List<CategoriaIncidente> categorias;
  final String? codigoSeleccionado;
  final ValueChanged<String?> onSeleccionar;

  const _ChipsCategorias({
    required this.categorias,
    required this.codigoSeleccionado,
    required this.onSeleccionar,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _Chip(
            etiqueta: 'Todos',
            activo: codigoSeleccionado == null,
            color: _colorAzul,
            onTap: () => onSeleccionar(null),
          ),
          for (final categoria in categorias) ...[
            const SizedBox(width: 8),
            _Chip(
              etiqueta: etiquetaCortaCategoria(
                categoria.codigo,
                categoria.nombre,
              ),
              activo: codigoSeleccionado == categoria.codigo,
              color: colorCategoria(
                categoria.codigo,
                colorHex: categoria.colorHex,
              ),
              onTap: () => onSeleccionar(categoria.codigo),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String etiqueta;
  final bool activo;
  final Color color;
  final VoidCallback onTap;

  const _Chip({
    required this.etiqueta,
    required this.activo,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: activo ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: activo ? color : _colorBorde),
        ),
        child: Text(
          etiqueta,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: activo ? Colors.white : const Color(0xFF374151),
          ),
        ),
      ),
    );
  }
}

class _TituloSeccion extends StatelessWidget {
  final String texto;

  const _TituloSeccion(this.texto);

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: _colorTextoGris,
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final String texto;

  const _Aviso({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 17, color: _colorAmbar),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF92400E)),
            ),
          ),
        ],
      ),
    );
  }
}

class _EstadoVacio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String detalle;
  final String? accion;
  final VoidCallback? onAccion;

  const _EstadoVacio({
    required this.icono,
    required this.titulo,
    required this.detalle,
    this.accion,
    this.onAccion,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 44, color: const Color(0xFF9CA3AF)),
            const SizedBox(height: 12),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _colorTitulo,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detalle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: _colorTextoGris,
              ),
            ),
            if (accion != null && onAccion != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _colorAzul),
                onPressed: onAccion,
                child: Text(accion!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pestaña 3: incidentes dentro de las zonas seguras del usuario
// ---------------------------------------------------------------------------

/// A diferencia de "Cerca de ti", esto no depende de dónde esté el teléfono:
/// son los incidentes que cayeron dentro de una zona segura configurada, esté
/// el usuario ahí o no.
class _PanelMisZonas extends StatefulWidget {
  const _PanelMisZonas();

  @override
  State<_PanelMisZonas> createState() => _PanelMisZonasState();
}

class _PanelMisZonasState extends State<_PanelMisZonas>
    with AutomaticKeepAliveClientMixin {
  final _servicio = NotificacionesServicio();

  List<AlertaDeZona> _alertas = const [];
  bool _cargando = true;
  String? _error;
  bool _sinSesion = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final token = Sesion.token;
    if (token == null || token.isEmpty) {
      setState(() {
        _cargando = false;
        _sinSesion = true;
      });
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
      _sinSesion = false;
    });
    try {
      final datos = await _servicio.listar(token);
      if (!mounted) return;
      setState(() {
        _alertas = datos.alertas;
        _cargando = false;
      });
      EstadoAlertas.registrarZonasSinLeer(datos.noLeidas);
    } on NotificacionesServicioException catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e.mensaje;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo conectar con el servidor';
      });
    }
  }

  /// Abre el incidente y marca la alerta como leída. El cambio se pinta de
  /// inmediato en memoria para no esperar una recarga completa de la lista.
  Future<void> _abrir(AlertaDeZona alerta) async {
    final token = Sesion.token;
    if (!alerta.leida && token != null) {
      setState(() => alerta.leida = true);
      _servicio.marcarLeida(token, alerta.id);
      // El contador se recalcula sobre la lista ya pintada: la insignia se
      // apaga en cuanto el usuario abre la ultima alerta sin leer.
      EstadoAlertas.registrarZonasSinLeer(
        _alertas.where((a) => !a.leida).length,
      );
    }
    final cambio = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => DetalleIncidenteVista(idReporte: alerta.reporte.id),
      ),
    );
    if (cambio == true && mounted) _cargar();
  }

  Future<void> _abrirZonas() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ZonasSegurasVista()),
    );
    if (mounted) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: _colorAzul));
    }
    if (_sinSesion) {
      return _EstadoVacio(
        icono: Icons.lock_outline,
        titulo: 'Inicia sesión',
        detalle: 'Necesitas una cuenta para configurar zonas seguras y recibir sus alertas.',
        accion: 'Iniciar sesión',
        onAccion: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const InicioSesionVista()),
        ),
      );
    }
    if (_error != null) {
      return _EstadoVacio(
        icono: Icons.cloud_off_rounded,
        titulo: 'No se pudieron cargar tus alertas',
        detalle: _error!,
        accion: 'Reintentar',
        onAccion: _cargar,
      );
    }
    if (_alertas.isEmpty) {
      // El mismo estado sirve para "no tienes zonas" y "tus zonas están
      // tranquilas": en ambos casos la acción útil es revisar las zonas.
      return RefreshIndicator(
        color: _colorAzul,
        onRefresh: _cargar,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.12),
            _EstadoVacio(
              icono: Icons.shield_outlined,
              titulo: 'Sin alertas en tus zonas',
              detalle: 'Cuando alguien reporte un incidente dentro de una de tus '
                  'zonas seguras, aparecerá aquí aunque no estés en el lugar.',
              accion: 'Ver mis zonas',
              onAccion: _abrirZonas,
            ),
          ],
        ),
      );
    }

    final noLeidas = _alertas.where((a) => !a.leida).length;
    return RefreshIndicator(
      color: _colorAzul,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _ResumenZonas(noLeidas: noLeidas, total: _alertas.length, onGestionar: _abrirZonas),
          const SizedBox(height: 18),
          const _TituloSeccion('ALERTAS EN TUS ZONAS'),
          const SizedBox(height: 8),
          for (final alerta in _alertas)
            _FilaAlertaZona(alerta: alerta, onTap: () => _abrir(alerta)),
        ],
      ),
    );
  }
}

/// Encabezado de la pestaña: cuántas alertas sin leer y acceso a las zonas.
class _ResumenZonas extends StatelessWidget {
  final int noLeidas;
  final int total;
  final VoidCallback onGestionar;

  const _ResumenZonas({
    required this.noLeidas,
    required this.total,
    required this.onGestionar,
  });

  @override
  Widget build(BuildContext context) {
    final hayNuevas = noLeidas > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _colorBorde),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: hayNuevas ? _colorAzul : const Color(0xFFEFF1F5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.shield_outlined,
              size: 23,
              color: hayNuevas ? Colors.white : _colorTitulo,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hayNuevas
                      ? '$noLeidas sin leer'
                      : 'Todo al día',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _colorTitulo,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$total ${total == 1 ? 'alerta recibida' : 'alertas recibidas'} en tus zonas seguras',
                  style: const TextStyle(fontSize: 12.5, color: _colorTextoGris),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onGestionar,
            child: const Text(
              'Gestionar',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _colorAzul,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de la lista de alertas de zona. Las no leídas llevan franja lateral
/// azul y el nombre de la zona en negrita.
class _FilaAlertaZona extends StatelessWidget {
  final AlertaDeZona alerta;
  final VoidCallback onTap;

  const _FilaAlertaZona({required this.alerta, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final reporte = alerta.reporte;
    final color = colorCategoria(
      reporte.categoriaCodigo,
      colorHex: reporte.colorHex,
    );
    final sinLeer = !alerta.leida;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sinLeer ? _colorAzul : _colorBorde),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            children: [
              if (sinLeer) Container(width: 4, color: _colorAzul),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: sinLeer ? 1 : 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          iconoCategoria(reporte.categoriaCodigo),
                          size: 21,
                          color: sinLeer ? Colors.white : color,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              reporte.categoria,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _colorTitulo,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(
                                  alerta.zona?.tipo.icono ?? Icons.place_outlined,
                                  size: 13,
                                  color: sinLeer ? _colorAzul : _colorTextoGris,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    alerta.referencia,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: sinLeer
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: sinLeer
                                          ? _colorAzul
                                          : _colorTextoGris,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        tiempoRelativo(alerta.fechaEnvio),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: sinLeer ? _colorAzul : _colorTextoGris,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
