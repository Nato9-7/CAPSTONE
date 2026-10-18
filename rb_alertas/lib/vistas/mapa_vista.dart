import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:rb_alertas/config/api_config.dart';
import 'package:rb_alertas/servicios/estado_alertas_servicio.dart';
import 'package:rb_alertas/servicios/reporte_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/servicios/ubicacion_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/detalle_incidente_vista.dart';
import 'package:rb_alertas/vistas/perfil_vista.dart';
import 'package:rb_alertas/vistas/reportar_incidente_vista.dart';
import 'package:rb_alertas/widgets/barra_navegacion_inferior.dart';
import 'package:rb_alertas/widgets/boton_voto.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';
import 'package:rb_alertas/widgets/panel_emergencias.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

class MapaVista extends StatefulWidget {
  /// Punto donde se abre el mapa (por ejemplo, el reporte recién enviado).
  final LatLng? centrarEn;

  const MapaVista({super.key, this.centrarEn});

  @override
  State<MapaVista> createState() => _MapaVistaState();
}

class _MapaVistaState extends State<MapaVista> {
  // Puerto Montt, Chile (referencia del mockup).
  static const _centroInicial = LatLng(-41.4693, -72.9424);

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

  /// Panel de filtros desplegado bajo el botón "Filtrar".
  bool _filtrosAbiertos = false;

  /// Pin tocado: muestra su etiqueta y la tarjeta de vista previa.
  ReporteMapa? _seleccionado;
  DetalleReporte? _vistaPrevia;
  bool _votando = false;

  @override
  void initState() {
    super.initState();
    _cargarReportes();
    _cargarCategorias();
    _ubicacionSiHayPermiso();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
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
      EstadoAlertas.revisar(reportes.map((r) => r.id));
      // Enciende la insignia por alertas de zona sin leer aunque el usuario
      // todavia no haya entrado a la pestana Alertas.
      EstadoAlertas.refrescarZonasSinLeer();
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
      _mostrarMensaje('No se pudieron cargar los reportes del mapa');
    }
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
      if (mounted) setState(() => _miUbicacion = punto);
    } catch (_) {
      // Sin ubicación el mapa funciona igual.
    }
  }

  /// Botón de ubicación: centra el mapa en el usuario.
  Future<void> _irAMiUbicacion() async {
    setState(() => _buscandoUbicacion = true);
    try {
      final punto = await _ubicacionServicio.obtenerUbicacionActual();
      if (!mounted) return;
      setState(() => _miUbicacion = punto);
      if (_mapaListo) _mapController.move(punto, 16);
    } on UbicacionServicioException catch (e) {
      if (mounted) _mostrarMensaje(e.mensaje.split(':').first);
    } catch (_) {
      if (mounted) _mostrarMensaje('No pudimos obtener tu ubicación');
    } finally {
      if (mounted) setState(() => _buscandoUbicacion = false);
    }
  }

  List<ReporteMapa> get _reportesVisibles {
    if (_codigoFiltro == null) return _reportes;
    return _reportes.where((r) => r.categoriaCodigo == _codigoFiltro).toList();
  }

  // ---------------------------------------------------------------------------
  // Vista previa del reporte

  Future<void> _seleccionar(ReporteMapa reporte) async {
    setState(() {
      _seleccionado = reporte;
      _vistaPrevia = null;
      _filtrosAbiertos = false;
    });
    await _cargarVistaPrevia(reporte.id);
  }

  Future<void> _cargarVistaPrevia(int idReporte) async {
    try {
      final detalle = await _reporteServicio.obtenerDetalle(idReporte, token: Sesion.token);
      if (!mounted || _seleccionado?.id != idReporte) return;
      setState(() => _vistaPrevia = detalle);
    } catch (_) {
      if (!mounted || _seleccionado?.id != idReporte) return;
      _mostrarMensaje('No se pudo cargar el reporte');
    }
  }

  void _cerrarVistaPrevia() {
    _seleccionado = null;
    _vistaPrevia = null;
  }

  Future<void> _votar(DetalleReporte d, TipoVoto voto) async {
    final token = Sesion.token;
    if (token == null || token.isEmpty) {
      _mostrarMensaje('Inicia sesión para confirmar o desmentir un reporte');
      return;
    }
    setState(() => _votando = true);
    try {
      final resumen = d.miVoto == voto
          ? await _reporteServicio.quitarVoto(d.id, token)
          : await _reporteServicio.votar(d.id, token, voto);
      await _cargarVistaPrevia(d.id);
      // Si el voto lo descartó, deja de ser vigente y su pin desaparece.
      if (resumen.estado != d.estado) await _cargarReportes();
    } on ReporteServicioException catch (e) {
      if (mounted) _mostrarMensaje(e.mensaje);
    } catch (_) {
      if (mounted) _mostrarMensaje('No se pudo conectar con el servidor');
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

  Future<void> _abrirReportar() async {
    final punto = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(builder: (context) => const ReportarIncidenteVista()),
    );
    if (punto == null || !mounted) return;
    await _cargarReportes();
    if (_mapaListo) _mapController.move(punto, 16);
  }

  void _irAPerfil() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, a, b) => const PerfilVista(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Interfaz

  @override
  Widget build(BuildContext context) {
    final seleccionado = _seleccionado;
    // Botones compactos para que el mapa quede a la vista.
    const altoBoton = 46.0;
    CategoriaIncidente? categoriaFiltro;
    for (final c in _categorias) {
      if (c.codigo == _codigoFiltro) categoriaFiltro = c;
    }

    return Scaffold(
      backgroundColor: RBColores.fondo,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.centrarEn ?? _centroInicial,
              initialZoom: widget.centrarEn != null ? 16 : 14.5,
              onMapReady: () => _mapaListo = true,
              onTap: (_, punto) {
                if (_seleccionado != null || _filtrosAbiertos) {
                  setState(() {
                    _cerrarVistaPrevia();
                    _filtrosAbiertos = false;
                  });
                }
              },
            ),
            children: [
              capaMapaBase(),
              MarkerLayer(
                markers: [
                  if (_miUbicacion != null)
                    Marker(
                      point: _miUbicacion!,
                      width: 56,
                      height: 56,
                      child: const PuntoUsuario(),
                    ),
                  for (final reporte in _reportesVisibles)
                    if (reporte.id != seleccionado?.id)
                      Marker(
                        point: LatLng(reporte.latitud, reporte.longitud),
                        width: 48,
                        height: 48,
                        child: GestureDetector(
                          onTap: () => _seleccionar(reporte),
                          child: PinIncidente(
                            codigo: reporte.categoriaCodigo,
                            colorHex: reporte.colorHex,
                          ),
                        ),
                      ),
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
                      ),
                    ),
                    Marker(
                      point: LatLng(seleccionado.latitud, seleccionado.longitud),
                      width: 220,
                      height: 44 + 40,
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 44),
                        child: Center(child: _EtiquetaPin(reporte: seleccionado)),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),

          // Buscador y botón de filtros superpuestos al mapa.
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BarraBusqueda(onAvatar: _irAPerfil),
                  const SizedBox(height: 8),
                  _BotonFiltrar(
                    categoria: categoriaFiltro,
                    abierto: _filtrosAbiertos,
                    onTap: () => setState(() => _filtrosAbiertos = !_filtrosAbiertos),
                  ),
                  if (_filtrosAbiertos) ...[
                    const SizedBox(height: 8),
                    _PanelFiltros(
                      categorias: _categorias,
                      codigoSeleccionado: _codigoFiltro,
                      onSeleccionar: (codigo) {
                        setState(() {
                          _codigoFiltro = codigo;
                          _filtrosAbiertos = false;
                          if (codigo != null && _seleccionado?.categoriaCodigo != codigo) {
                            _cerrarVistaPrevia();
                          }
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),

          const Positioned(left: 6, bottom: 2, child: AtribucionMapa()),

          if (seleccionado == null) ...[
            Positioned(
              right: 12,
              bottom: 20 + altoBoton + 10,
              child: _BotonCuadrado(
                tamano: altoBoton,
                onTap: _buscandoUbicacion ? null : _irAMiUbicacion,
                child: _buscandoUbicacion
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Icon(Icons.my_location_rounded, color: RBColores.azul, size: 22),
              ),
            ),
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
                    child: _BotonPildora(
                      texto: 'Emergencias',
                      icono: Icons.notification_important_outlined,
                      fondo: Colors.white,
                      color: RBColores.rojo,
                      alto: altoBoton,
                      onTap: () => mostrarPanelEmergencias(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: _BotonPildora(
                      texto: 'Reportar',
                      icono: Icons.add_rounded,
                      fondo: RBColores.verde,
                      color: Colors.white,
                      alto: altoBoton,
                      onTap: _abrirReportar,
                    ),
                  ),
                ],
              ),
            ),
          ] else
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: _TarjetaVistaPrevia(
                reporte: seleccionado,
                detalle: _vistaPrevia,
                votando: _votando,
                onCerrar: () => setState(_cerrarVistaPrevia),
                onAbrir: () => _abrirDetalle(seleccionado.id),
                onComentarios: () => _abrirDetalle(seleccionado.id, irAComentarios: true),
                onVotar: _votar,
              ),
            ),
        ],
      ),
      bottomNavigationBar: const BarraNavegacionInferior(
        seccionActiva: SeccionApp.mapa,
      ),
    );
  }
}

/// Etiqueta oscura sobre el pin seleccionado: "Accidente · 12 min".
class _EtiquetaPin extends StatelessWidget {
  final ReporteMapa reporte;

  const _EtiquetaPin({required this.reporte});

  @override
  Widget build(BuildContext context) {
    final tiempo = tiempoCorto(reporte.fechaCreacion);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: RBColores.tinta,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        tiempo.isEmpty
            ? nombreCortoCategoria(reporte.categoriaCodigo, reporte.categoria)
            : '${nombreCortoCategoria(reporte.categoriaCodigo, reporte.categoria)} · $tiempo',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _BarraBusqueda extends StatelessWidget {
  final VoidCallback onAvatar;

  const _BarraBusqueda({required this.onAvatar});

  String get _iniciales {
    final usuario = Sesion.usuario;
    if (usuario == null) return '';
    return [usuario['nombres'], usuario['apellidos']]
        .whereType<String>()
        .where((x) => x.trim().isNotEmpty)
        .map((x) => x.trim()[0].toUpperCase())
        .join();
  }

  @override
  Widget build(BuildContext context) {
    final iniciales = _iniciales;
    const alto = 48.0;
    return Container(
      height: alto,
      padding: const EdgeInsets.only(left: 14, right: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(alto / 2),
        boxShadow: [
          BoxShadow(
            color: RBColores.azul.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: RBColores.azul, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: TextField(
              decoration: InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: 'Buscar dirección o incidente',
                hintStyle: TextStyle(color: RBColores.placeholder, fontSize: 15),
              ),
            ),
          ),
          GestureDetector(
            onTap: onAvatar,
            child: Container(
              width: alto - 10,
              height: alto - 10,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: RBColores.azul, shape: BoxShape.circle),
              child: iniciales.isEmpty
                  ? const Icon(Icons.person_rounded, color: Colors.white, size: 20)
                  : Text(
                      iniciales,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Botón único de filtros. Muestra la categoría elegida para que se note que
/// el mapa está filtrado.
class _BotonFiltrar extends StatelessWidget {
  final CategoriaIncidente? categoria;
  final bool abierto;
  final VoidCallback onTap;

  const _BotonFiltrar({required this.categoria, required this.abierto, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final filtrado = categoria != null;
    final activo = abierto || filtrado;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: RBColores.azul.withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: activo ? RBColores.azul : Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 40,
            padding: const EdgeInsets.only(left: 12, right: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (filtrado)
                  IconoCategoria(codigo: categoria!.codigo, colorHex: categoria!.colorHex, tamano: 22)
                else
                  Icon(Icons.tune_rounded, size: 20, color: activo ? Colors.white : RBColores.azul),
                const SizedBox(width: 8),
                Text(
                  filtrado
                      ? etiquetaCortaCategoria(categoria!.codigo, categoria!.nombre)
                      : 'Filtrar',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: activo ? Colors.white : RBColores.azul,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  abierto ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 20,
                  color: activo ? Colors.white : RBColores.azul,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Panel que se despliega bajo "Filtrar" con todas las categorías a la vista,
/// en varias líneas, con chips compactos para no tapar el mapa.
class _PanelFiltros extends StatelessWidget {
  final List<CategoriaIncidente> categorias;
  final String? codigoSeleccionado;
  final ValueChanged<String?> onSeleccionar;

  const _PanelFiltros({
    required this.categorias,
    required this.codigoSeleccionado,
    required this.onSeleccionar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: RBColores.azul.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text('Mostrar en el mapa', style: RBTexto.etiqueta),
          ),
          if (categorias.isEmpty)
            const Padding(
              padding: EdgeInsets.all(4),
              child: Text(
                'No se pudieron cargar las categorías.',
                style: TextStyle(fontSize: 13, color: RBColores.texto2),
              ),
            ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(
                etiqueta: 'Todos',
                activo: codigoSeleccionado == null,
                onTap: () => onSeleccionar(null),
              ),
              for (final categoria in categorias)
                _chip(
                  etiqueta: etiquetaCortaCategoria(categoria.codigo, categoria.nombre),
                  activo: codigoSeleccionado == categoria.codigo,
                  onTap: () => onSeleccionar(categoria.codigo),
                  icono: IconoCategoria(
                    codigo: categoria.codigo,
                    colorHex: categoria.colorHex,
                    tamano: 20,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String etiqueta,
    required bool activo,
    required VoidCallback onTap,
    Widget? icono,
  }) {
    return Material(
      color: activo ? RBColores.azul : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: activo ? RBColores.azul : RBColores.linea),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (activo && icono == null) ...[
                const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                const SizedBox(width: 4),
              ] else if (icono != null) ...[
                icono,
                const SizedBox(width: 6),
              ],
              Text(
                etiqueta,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: activo ? Colors.white : RBColores.tinta,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BotonPildora extends StatelessWidget {
  final String texto;
  final IconData icono;
  final Color fondo;
  final Color color;
  final double alto;
  final VoidCallback onTap;

  const _BotonPildora({
    required this.texto,
    required this.icono,
    required this.fondo,
    required this.color,
    required this.alto,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(23),
        boxShadow: [
          BoxShadow(
            color: (fondo == Colors.white ? RBColores.azul : fondo).withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: fondo,
        borderRadius: BorderRadius.circular(23),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(23),
          child: Container(
            height: alto,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icono, color: color, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    texto,
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BotonCuadrado extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double tamano;

  const _BotonCuadrado({required this.child, required this.onTap, required this.tamano});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: RBColores.azul.withValues(alpha: 0.16),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(width: tamano, height: tamano, child: Center(child: child)),
        ),
      ),
    );
  }
}

/// Tarjeta inferior al tocar un pin: foto, categoría, título, descripción y
/// los votos. Al tocarla se abre el detalle completo.
class _TarjetaVistaPrevia extends StatelessWidget {
  final ReporteMapa reporte;
  final DetalleReporte? detalle;
  final bool votando;
  final VoidCallback onCerrar;
  final VoidCallback onAbrir;
  final VoidCallback onComentarios;
  final void Function(DetalleReporte, TipoVoto) onVotar;

  const _TarjetaVistaPrevia({
    required this.reporte,
    required this.detalle,
    required this.votando,
    required this.onCerrar,
    required this.onAbrir,
    required this.onComentarios,
    required this.onVotar,
  });

  @override
  Widget build(BuildContext context) {
    final color = colorCategoria(reporte.categoriaCodigo, colorHex: reporte.colorHex);
    final d = detalle;
    final imagen = d != null && d.imagenes.isNotEmpty ? d.imagenes.first : null;
    final esVideo = imagen != null &&
        ['.mp4', '.mov', '.webm'].any((ext) => imagen.toLowerCase().endsWith(ext));
    final tiempo = tiempoCorto(reporte.fechaCreacion);
    final angosta = MediaQuery.sizeOf(context).width < 380;
    final foto = angosta ? 80.0 : 104.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: RBColores.azul.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(26),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onAbrir,
          child: Padding(
            padding: EdgeInsets.all(angosta ? 12 : 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SizedBox(
                        width: foto,
                        height: foto,
                        child: imagen != null && !esVideo
                            ? Image.network(
                                ApiConfig.urlArchivo(imagen),
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => _sinFoto(color),
                              )
                            : _sinFoto(color, video: esVideo),
                      ),
                    ),
                    SizedBox(width: angosta ? 10 : 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(iconoCategoria(reporte.categoriaCodigo), size: 16, color: color),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          tiempo.isEmpty
                                              ? nombreCortoCategoria(reporte.categoriaCodigo, reporte.categoria)
                                              : '${nombreCortoCategoria(reporte.categoriaCodigo, reporte.categoria)} · $tiempo',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: color,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: onCerrar,
                                customBorder: const CircleBorder(),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: const BoxDecoration(
                                    color: RBColores.fondo,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close_rounded, size: 20, color: RBColores.tinta),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tituloReporte(reporte.categoria, reporte.direccion),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                              color: RBColores.tinta,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            reporte.descripcion,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14.5, height: 1.35, color: RBColores.texto2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (d == null)
                      const SizedBox(
                        height: 48,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else ...[
                      BotonVoto(
                        icono: Icons.thumb_up_outlined,
                        iconoActivo: Icons.thumb_up_rounded,
                        cantidad: d.confirmaciones,
                        marcado: d.miVoto == TipoVoto.confirma,
                        positivo: true,
                        onTap: !d.esAutor && d.activo && !votando
                            ? () => onVotar(d, TipoVoto.confirma)
                            : null,
                      ),
                      const SizedBox(width: 10),
                      BotonVoto(
                        icono: Icons.thumb_down_outlined,
                        iconoActivo: Icons.thumb_down_rounded,
                        cantidad: d.desmentidos,
                        marcado: d.miVoto == TipoVoto.desmiente,
                        positivo: false,
                        onTap: !d.esAutor && d.activo && !votando
                            ? () => onVotar(d, TipoVoto.desmiente)
                            : null,
                      ),
                    ],
                    const Spacer(),
                    // Comentarios del reporte: abre el detalle ya en la conversación.
                    // El resto de la tarjeta abre el detalle desde arriba.
                    Material(
                      color: RBColores.azul,
                      borderRadius: BorderRadius.circular(24),
                      child: InkWell(
                        onTap: onComentarios,
                        borderRadius: BorderRadius.circular(24),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: angosta ? 14 : 20, vertical: 13),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                color: Colors.white,
                                size: 20,
                                semanticLabel: d == null
                                    ? 'Ver comentarios'
                                    : '${d.totalComentarios} comentarios',
                              ),
                              if (d != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '${d.totalComentarios}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sinFoto(Color color, {bool video = false}) {
    return CustomPaint(
      painter: const BordePunteado(color: RBColores.bordeCampo, radio: 18),
      child: Container(
        color: RBColores.azul50.withValues(alpha: 0.6),
        alignment: Alignment.center,
        child: Icon(
          video ? Icons.play_circle_outline_rounded : iconoCategoria(reporte.categoriaCodigo),
          size: 34,
          color: video ? RBColores.azul : color.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
