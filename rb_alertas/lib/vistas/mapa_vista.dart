import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rb_alertas/widgets/barra_navegacion_inferior.dart';

enum _TipoAlerta { accidente, robo, mascota }

class MapaVista extends StatefulWidget {
  const MapaVista({super.key});

  @override
  State<MapaVista> createState() => _MapaVistaState();
}

class _MapaVistaState extends State<MapaVista> {
  static const _colorAzul = Color(0xFF0056D2);
  static const _colorTextoGris = Color(0xFF6B7280);

  // Puerto Montt, Chile (referencia del mockup).
  static const _centroInicial = LatLng(-41.4693, -72.9424);

  _TipoAlerta? _filtroSeleccionado;

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
            options: const MapOptions(
              initialCenter: _centroInicial,
              initialZoom: 14.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.rbalertas.rb_alertas',
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
