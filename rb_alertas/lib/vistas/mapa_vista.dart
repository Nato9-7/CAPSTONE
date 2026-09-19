import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rb_alertas/servicios/reporte_servicio.dart';
import 'package:rb_alertas/vistas/detalle_incidente_vista.dart';
import 'package:rb_alertas/widgets/barra_navegacion_inferior.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';

enum _TipoAlerta { accidente, robo, mascota }

class MapaVista extends StatefulWidget {
  /// Punto donde se abre el mapa (por ejemplo, el reporte recién enviado).
  final LatLng? centrarEn;

  const MapaVista({super.key, this.centrarEn});

  @override
  State<MapaVista> createState() => _MapaVistaState();
}

class _MapaVistaState extends State<MapaVista> {
  static const _colorAzul = Color(0xFF0056D2);
  static const _colorTextoGris = Color(0xFF6B7280);

  // Puerto Montt, Chile (referencia del mockup).
  static const _centroInicial = LatLng(-41.4693, -72.9424);

  final _reporteServicio = ReporteServicio();
  List<ReporteMapa> _reportes = [];
  _TipoAlerta? _filtroSeleccionado;

  @override
  void initState() {
    super.initState();
    _cargarReportes();
  }

  Future<void> _cargarReportes() async {
    try {
      final reportes = await _reporteServicio.obtenerReportes();
      if (!mounted) return;
      setState(() => _reportes = reportes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron cargar los reportes del mapa')),
      );
    }
  }

  static _TipoAlerta? _tipoDe(String codigoCategoria) {
    final c = codigoCategoria.toLowerCase();
    if (c.contains('accidente')) return _TipoAlerta.accidente;
    if (c.contains('robo') || c.contains('asalto')) return _TipoAlerta.robo;
    if (c.contains('mascota')) return _TipoAlerta.mascota;
    return null;
  }

  List<ReporteMapa> get _reportesVisibles {
    if (_filtroSeleccionado == null) return _reportes;
    return _reportes
        .where((r) => _tipoDe(r.categoriaCodigo) == _filtroSeleccionado)
        .toList();
  }

  Future<void> _abrirDetalle(ReporteMapa reporte) async {
    final cambio = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => DetalleIncidenteVista(idReporte: reporte.id),
      ),
    );
    // Si se marcó como resuelto, deja de ser vigente: se recargan los pines.
    if (cambio == true && mounted) _cargarReportes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        foregroundColor: Colors.black87,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () {},
        ),
        title: const Text(
          'RB Alertas',
          style: TextStyle(
            color: _colorAzul,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: widget.centrarEn ?? _centroInicial,
              initialZoom: widget.centrarEn != null ? 16 : 14.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.rbalertas.rb_alertas',
              ),
              MarkerLayer(
                markers: [
                  for (final reporte in _reportesVisibles)
                    Marker(
                      point: LatLng(reporte.latitud, reporte.longitud),
                      width: 40,
                      height: 40,
                      child: GestureDetector(
                        onTap: () => _abrirDetalle(reporte),
                        child: _PinReporte(
                          icono: iconoCategoria(reporte.categoriaCodigo),
                          color: colorCategoria(
                            reporte.categoriaCodigo,
                            colorHex: reporte.colorHex,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          const Positioned(
            bottom: 4,
            right: 8,
            child: Text(
              '© OpenStreetMap contributors',
              style: TextStyle(fontSize: 9, color: Color(0xFF9CA3AF)),
            ),
          ),

          // Buscador + chips de filtro superpuestos al mapa.
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Column(
              children: [
                _BarraBusqueda(colorTexto: _colorTextoGris),
                const SizedBox(height: 12),
                _ChipsFiltro(
                  seleccionado: _filtroSeleccionado,
                  colorAzul: _colorAzul,
                  onSeleccionar: (tipo) {
                    setState(() => _filtroSeleccionado = tipo);
                  },
                ),
              ],
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

class _BarraBusqueda extends StatelessWidget {
  final Color colorTexto;

  const _BarraBusqueda({required this.colorTexto});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.search, color: colorTexto, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: 'Buscar dirección o incidente...',
                hintStyle: TextStyle(color: colorTexto, fontSize: 14),
              ),
            ),
          ),
          Icon(Icons.mic_none_rounded, color: colorTexto, size: 20),
        ],
      ),
    );
  }
}

class _ChipsFiltro extends StatelessWidget {
  final _TipoAlerta? seleccionado;
  final Color colorAzul;
  final ValueChanged<_TipoAlerta?> onSeleccionar;

  const _ChipsFiltro({
    required this.seleccionado,
    required this.colorAzul,
    required this.onSeleccionar,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip(
            etiqueta: 'Todos',
            icono: null,
            activo: seleccionado == null,
            onTap: () => onSeleccionar(null),
          ),
          const SizedBox(width: 8),
          _chip(
            etiqueta: 'Accidentes',
            icono: Icons.personal_injury_rounded,
            activo: seleccionado == _TipoAlerta.accidente,
            onTap: () => onSeleccionar(_TipoAlerta.accidente),
          ),
          const SizedBox(width: 8),
          _chip(
            etiqueta: 'Robos',
            icono: Icons.warning_rounded,
            activo: seleccionado == _TipoAlerta.robo,
            onTap: () => onSeleccionar(_TipoAlerta.robo),
          ),
          const SizedBox(width: 8),
          _chip(
            etiqueta: 'Mascotas',
            icono: Icons.pets_rounded,
            activo: seleccionado == _TipoAlerta.mascota,
            onTap: () => onSeleccionar(_TipoAlerta.mascota),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String etiqueta,
    required IconData? icono,
    required bool activo,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: activo ? colorAzul : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icono != null) ...[
              Icon(
                icono,
                size: 16,
                color: activo ? Colors.white : const Color(0xFF6B7280),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              etiqueta,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: activo ? Colors.white : const Color(0xFF374151),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinReporte extends StatelessWidget {
  final IconData icono;
  final Color color;

  const _PinReporte({required this.icono, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icono, color: Colors.white, size: 20),
    );
  }
}
