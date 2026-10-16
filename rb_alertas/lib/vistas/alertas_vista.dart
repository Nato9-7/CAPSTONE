import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:rb_alertas/servicios/estado_alertas_servicio.dart';
import 'package:rb_alertas/servicios/notificaciones_servicio.dart';
import 'package:rb_alertas/servicios/reporte_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/servicios/ubicacion_servicio.dart';
import 'package:rb_alertas/servicios/zonas_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/detalle_incidente_vista.dart';
import 'package:rb_alertas/vistas/inicio_sesion_vista.dart';
import 'package:rb_alertas/vistas/zonas_seguras_vista.dart';
import 'package:rb_alertas/widgets/barra_navegacion_inferior.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Punto de referencia cuando todavía no se conoce la ubicación del usuario.
const _centroPorDefecto = LatLng(-41.4693, -72.9424);

/// Radio en kilómetros que se consulta a la API para las alertas cercanas.
const _radioKm = 2.0;

/// Antigüedad hasta la que una alerta se muestra en la sección "Recientes".
const _ventanaRecientes = Duration(hours: 2);

/// Pantalla "Alertas": incidentes vigentes cerca del usuario, alertas de sus
/// zonas seguras e historial de sus reportes.
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
      backgroundColor: RBColores.fondo,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, context.pantallaBaja ? 14 : 28, 20, 14),
              child: const TituloPantalla('Alertas'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SelectorSegmentado(
                controlador: _tabs,
                opciones: const ['Cerca de ti', 'Mis zonas', 'Mis reportes'],
              ),
            ),
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

/// Número grande + texto, dentro de la tarjeta verde.
class _Cifra extends StatelessWidget {
  final String valor;
  final String etiqueta;

  const _Cifra({required this.valor, required this.etiqueta});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          valor,
          style: const TextStyle(
            fontFamily: RBFuentes.titulos,
            fontSize: 40,
            height: 1.05,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        Text(
          etiqueta,
          style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.9)),
        ),
      ],
    );
  }
}

/// Fila horizontal de filtros de estado.
class _Filtros<T> extends StatelessWidget {
  final List<(T, String)> opciones;
  final T seleccionado;
  final ValueChanged<T> onSeleccionar;

  const _Filtros({
    required this.opciones,
    required this.seleccionado,
    required this.onSeleccionar,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (valor, etiqueta) in opciones) ...[
            ChipFiltro(
              etiqueta: etiqueta,
              activo: valor == seleccionado,
              onTap: () => onSeleccionar(valor),
            ),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pestaña 1: alertas activas cerca del usuario
// ---------------------------------------------------------------------------

enum _FiltroCercanas { todas, activas, validadas }

class _PanelCercanas extends StatefulWidget {
  const _PanelCercanas();

  @override
  State<_PanelCercanas> createState() => _PanelCercanasState();
}

class _PanelCercanasState extends State<_PanelCercanas>
    with AutomaticKeepAliveClientMixin {
  final _reporteServicio = ReporteServicio();
  final _ubicacionServicio = UbicacionServicio();

  List<ReporteCercano> _alertas = [];
  _FiltroCercanas _filtro = _FiltroCercanas.todas;
  bool _cargando = true;
  String? _error;
  DateTime? _actualizado;
  // Aviso cuando no se pudo leer el GPS y se usa el centro por defecto.
  String? _avisoUbicacion;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
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
        _alertas = cercanas.reportes;
        _avisoUbicacion = aviso;
        _actualizado = DateTime.now();
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

  List<ReporteCercano> get _visibles {
    return switch (_filtro) {
      _FiltroCercanas.todas => _alertas,
      _FiltroCercanas.activas =>
        _alertas.where((a) => EstadoVisual.desdeApi(a.estado) == EstadoVisual.activa).toList(),
      _FiltroCercanas.validadas =>
        _alertas.where((a) => EstadoVisual.desdeApi(a.estado) == EstadoVisual.validada).toList(),
    };
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

  Widget _fila(ReporteCercano alerta) {
    final tiempo = tiempoRelativoInicio(alerta.fechaCreacion);
    final distancia = 'a ${distanciaLegible(alerta.distanciaMetros)}';
    return FilaIncidente(
      codigoCategoria: alerta.categoriaCodigo,
      colorHex: alerta.colorHex,
      titulo: tituloReporte(alerta.categoria, alerta.direccion),
      detalle: tiempo.isEmpty ? capitalizar(distancia) : '$tiempo · $distancia',
      estado: EstadoVisual.desdeApi(alerta.estado),
      contador: '${alerta.confirmaciones} '
          '${alerta.confirmaciones == 1 ? 'confirma' : 'confirman'}',
      onTap: () => _abrirDetalle(alerta.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return EstadoVacio(
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
    final total = _alertas.length;

    return RefreshIndicator(
      onRefresh: _cargarTodo,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          TarjetaSuricata(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$total',
                      style: const TextStyle(
                        fontFamily: RBFuentes.titulos,
                        fontSize: 52,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          total == 1 ? 'alerta activa' : 'alertas activas',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'En ${distanciaLegible(_radioKm * 1000)} a tu alrededor · '
                  'actualizado ${tiempoRelativo(_actualizado)}',
                  style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.92)),
                ),
              ],
            ),
          ),
          if (_avisoUbicacion != null) ...[
            const SizedBox(height: 12),
            AvisoRB(texto: _avisoUbicacion!),
          ],
          const SizedBox(height: 20),
          _Filtros<_FiltroCercanas>(
            opciones: const [
              (_FiltroCercanas.todas, 'Todas'),
              (_FiltroCercanas.activas, 'Activas'),
              (_FiltroCercanas.validadas, 'Validadas'),
            ],
            seleccionado: _filtro,
            onSeleccionar: (f) => setState(() => _filtro = f),
          ),
          const SizedBox(height: 20),
          if (visibles.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: EstadoVacio(
                icono: Icons.notifications_off_outlined,
                titulo: 'Sin alertas cerca de ti',
                detalle: 'No hay incidentes vigentes en un radio de 2 km. '
                    'Desliza hacia abajo para actualizar.',
              ),
            ),
          if (recientes.isNotEmpty) ...[
            const EtiquetaSeccion('Recientes'),
            const SizedBox(height: 12),
            for (final alerta in recientes) _fila(alerta),
          ],
          if (anteriores.isNotEmpty) ...[
            const SizedBox(height: 12),
            const EtiquetaSeccion('Anteriores'),
            const SizedBox(height: 12),
            for (final alerta in anteriores) _fila(alerta),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pestaña 2: incidentes dentro de las zonas seguras del usuario
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
  final _zonasServicio = ZonasServicio();

  List<AlertaDeZona> _alertas = const [];
  // Las zonas solo alimentan las tarjetas de arriba: si fallan, la lista de
  // alertas se muestra igual.
  List<ZonaSegura>? _zonas;
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
    _cargarZonas(token);
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

  Future<void> _cargarZonas(String token) async {
    try {
      final datos = await _zonasServicio.listar(token);
      if (mounted) setState(() => _zonas = datos.zonas);
    } catch (_) {
      // Sin zonas solo se ocultan las tarjetas.
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

  /// Alertas vigentes de cada zona, para la línea "1 alerta" de su tarjeta.
  int _alertasVigentes(ZonaSegura zona) => _alertas
      .where((a) => a.zona?.id == zona.id)
      .where((a) {
        final estado = EstadoVisual.desdeApi(a.reporte.estado);
        return estado == EstadoVisual.activa || estado == EstadoVisual.validada;
      })
      .length;

  Widget _fila(AlertaDeZona alerta) {
    final reporte = alerta.reporte;
    final tiempo = tiempoRelativo(alerta.fechaEnvio ?? reporte.fechaCreacion);
    final distancia = alerta.distanciaMetros == null
        ? null
        : 'a ${distanciaLegible(alerta.distanciaMetros!)}';
    final detalle = alerta.zona == null
        ? '${capitalizar(alerta.referencia)} · $tiempo'
        : [
            'En ${alerta.zona!.nombre}',
            if (tiempo.isNotEmpty) tiempo,
            ?distancia,
          ].join(' · ');
    final confirmaciones = reporte.confirmaciones;

    return FilaIncidente(
      codigoCategoria: reporte.categoriaCodigo,
      colorHex: reporte.colorHex,
      titulo: tituloReporte(reporte.categoria, reporte.direccion),
      detalle: detalle,
      estado: EstadoVisual.desdeApi(reporte.estado),
      contador: '$confirmaciones ${confirmaciones == 1 ? 'confirma' : 'confirman'}',
      destacada: !alerta.leida,
      onTap: () => _abrir(alerta),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sinSesion) {
      return EstadoVacio(
        icono: Icons.lock_outline_rounded,
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
      return EstadoVacio(
        icono: Icons.cloud_off_rounded,
        titulo: 'No se pudieron cargar tus alertas',
        detalle: _error!,
        accion: 'Reintentar',
        onAccion: _cargar,
      );
    }

    final zonas = _zonas;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        children: [
          EtiquetaSeccion(
            'Tus zonas seguras',
            accion: InkWell(
              onTap: _abrirZonas,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  'Gestionar',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: RBColores.azul,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (zonas != null)
            SizedBox(
              height: 168,
              child: ListView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                children: [
                  for (final zona in zonas) ...[
                    _TarjetaZona(
                      zona: zona,
                      alertas: _alertasVigentes(zona),
                      onTap: _abrirZonas,
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (zonas.isEmpty) _TarjetaAnadirZona(onTap: _abrirZonas),
                ],
              ),
            ),
          const SizedBox(height: 26),
          const EtiquetaSeccion('Alertas en tus zonas'),
          const SizedBox(height: 12),
          if (_alertas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: EstadoVacio(
                icono: Icons.shield_outlined,
                titulo: 'Sin alertas en tus zonas',
                detalle: 'Tus zonas seguras están tranquilas por ahora.',
              ),
            )
          else
            for (final alerta in _alertas) _fila(alerta),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Te avisaremos con una notificación cuando alguien reporte un '
              'incidente dentro de una de tus zonas.',
              style: TextStyle(fontSize: 15, height: 1.45, color: RBColores.texto2),
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaZona extends StatelessWidget {
  final ZonaSegura zona;
  final int alertas;
  final VoidCallback onTap;

  const _TarjetaZona({required this.zona, required this.alertas, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: TarjetaRB(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(18, 18, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: RBColores.verde50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(zona.tipo.icono, color: RBColores.verde, size: 26),
            ),
            const Spacer(),
            Text(
              zona.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 17.5,
                fontWeight: FontWeight.w700,
                color: RBColores.tinta,
              ),
            ),
            Text(
              'Radio ${zona.radioTexto}',
              style: const TextStyle(fontSize: 14, color: RBColores.texto2),
            ),
            const SizedBox(height: 4),
            Text(
              alertas == 0 ? 'Sin alertas' : '$alertas ${alertas == 1 ? 'alerta' : 'alertas'}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: alertas == 0 ? RBColores.verde : RBColores.rojo,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaAnadirZona extends StatelessWidget {
  final VoidCallback onTap;

  const _TarjetaAnadirZona({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: CustomPaint(
        painter: const BordePunteado(color: RBColores.placeholder, radio: RBRadios.tarjeta),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(RBRadios.tarjeta),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, color: RBColores.azul, size: 30),
                SizedBox(height: 6),
                Text(
                  'Añadir zona',
                  style: TextStyle(fontWeight: FontWeight.w700, color: RBColores.azul),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pestaña 3: historial de reportes del usuario
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

  EstadoVisual _estadoVisual(EstadoMiReporte estado) => switch (estado) {
        EstadoMiReporte.activa => EstadoVisual.activa,
        EstadoMiReporte.resuelta => EstadoVisual.resuelta,
        EstadoMiReporte.vencida => EstadoVisual.vencida,
        EstadoMiReporte.descartada => EstadoVisual.descartada,
      };

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_sinSesion) {
      return EstadoVacio(
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
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return EstadoVacio(
        icono: Icons.cloud_off_rounded,
        titulo: 'No se pudo cargar tu historial',
        detalle: _error!,
        accion: 'Reintentar',
        onAccion: _cargar,
      );
    }

    final visibles = _visibles;
    final apoyos = _reportes.fold<int>(0, (suma, r) => suma + r.apoyos);
    final resueltos = _reportes.where((r) => r.estado == EstadoMiReporte.resuelta).length;

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          TarjetaSuricata(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tu impacto en el barrio',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: context.pantallaAngosta ? 18 : 28,
                  runSpacing: 8,
                  children: [
                    _Cifra(
                      valor: '${_reportes.length}',
                      etiqueta: _reportes.length == 1 ? 'reporte' : 'reportes',
                    ),
                    _Cifra(valor: '$apoyos', etiqueta: apoyos == 1 ? 'apoyo' : 'apoyos'),
                    _Cifra(
                      valor: '$resueltos',
                      etiqueta: resueltos == 1 ? 'resuelto' : 'resueltos',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _Filtros<_FiltroHistorial>(
            opciones: const [
              (_FiltroHistorial.todos, 'Todos'),
              (_FiltroHistorial.activas, 'Activas'),
              (_FiltroHistorial.resueltas, 'Resueltas'),
              (_FiltroHistorial.vencidas, 'Vencidas'),
            ],
            seleccionado: _filtro,
            onSeleccionar: (f) => setState(() => _filtro = f),
          ),
          const SizedBox(height: 20),
          if (visibles.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: EstadoVacio(
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
            FilaIncidente(
              codigoCategoria: reporte.categoriaCodigo,
              colorHex: reporte.colorHex,
              titulo: tituloReporte(reporte.categoria, reporte.direccion),
              detalle: tiempoRelativoInicio(reporte.fechaCreacion),
              estado: _estadoVisual(reporte.estado),
              contador: '${reporte.apoyos} ${reporte.apoyos == 1 ? 'apoyo' : 'apoyos'}',
              onTap: () => _abrirDetalle(reporte.id),
            ),
        ],
      ),
    );
  }
}
