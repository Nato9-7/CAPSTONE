import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum _TipoAlerta { accidente, robo, mascota }

class MapaVista extends StatefulWidget {
  const MapaVista({super.key});

  @override
  State<MapaVista> createState() => _MapaVistaState();
}

class _MapaVistaState extends State<MapaVista> {
  static const _colorAzul = Color(0xFF0056D2);
  static const _colorRojo = Color(0xFFE53935);
  static const _colorNaranja = Color(0xFFFB8C00);
  static const _colorTextoGris = Color(0xFF6B7280);

  // Puerto Montt, Chile (referencia del mockup).
  static const _centroInicial = LatLng(-41.4693, -72.9424);

  _TipoAlerta? _filtroSeleccionado;
  GoogleMapController? _controladorMapa;
  final Set<Marker> _marcadores = {};

  final List<_Alerta> _alertas = const [
    _Alerta(
      id: 'a1',
      tipo: _TipoAlerta.accidente,
      titulo: 'Accidente de tránsito',
      posicion: LatLng(-41.4675, -72.9455),
    ),
    _Alerta(
      id: 'a2',
      tipo: _TipoAlerta.robo,
      titulo: 'Robo reportado',
      posicion: LatLng(-41.4705, -72.9400),
    ),
    _Alerta(
      id: 'a3',
      tipo: _TipoAlerta.mascota,
      titulo: 'Mascota perdida',
      posicion: LatLng(-41.4730, -72.9430),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _cargarMarcadores();
  }

  Future<void> _cargarMarcadores() async {
    final marcadores = <Marker>{};
    for (final alerta in _alertas) {
      final icono = await _crearIconoMarcador(
        icono: _iconoPara(alerta.tipo),
        color: _colorPara(alerta.tipo),
      );
      marcadores.add(
        Marker(
          markerId: MarkerId(alerta.id),
          position: alerta.posicion,
          icon: icono,
          infoWindow: InfoWindow(title: alerta.titulo),
        ),
      );
    }
    if (!mounted) return;
    setState(() => _marcadores.addAll(marcadores));
  }

  IconData _iconoPara(_TipoAlerta tipo) {
    switch (tipo) {
      case _TipoAlerta.accidente:
        return Icons.personal_injury_rounded;
      case _TipoAlerta.robo:
        return Icons.warning_rounded;
      case _TipoAlerta.mascota:
        return Icons.pets_rounded;
    }
  }

  Color _colorPara(_TipoAlerta tipo) {
    switch (tipo) {
      case _TipoAlerta.accidente:
        return _colorRojo;
      case _TipoAlerta.robo:
        return _colorNaranja;
      case _TipoAlerta.mascota:
        return _colorAzul;
    }
  }

  // Dibuja un pin circular con un ícono dentro para que los marcadores del
  // mapa coincidan con el estilo del mockup (Google Maps no permite widgets
  // de Flutter directamente como marcador).
  Future<BitmapDescriptor> _crearIconoMarcador({
    required IconData icono,
    required Color color,
  }) async {
    const double tamano = 96;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final centro = const Offset(tamano / 2, tamano / 2 - 6);
    const radio = 30.0;

    final pinturaSombra = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(centro.translate(0, 4), radio, pinturaSombra);

    final pinturaCirculo = Paint()..color = color;
    canvas.drawCircle(centro, radio, pinturaCirculo);

    final pinturaBorde = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(centro, radio, pinturaBorde);

    final painterIcono = TextPainter(textDirection: TextDirection.ltr);
    painterIcono.text = TextSpan(
      text: String.fromCharCode(icono.codePoint),
      style: TextStyle(
        fontSize: 32,
        fontFamily: icono.fontFamily,
        package: icono.fontPackage,
        color: Colors.white,
      ),
    );
    painterIcono.layout();
    painterIcono.paint(
      canvas,
      centro - Offset(painterIcono.width / 2, painterIcono.height / 2),
    );

    final imagen = await recorder
        .endRecording()
        .toImage(tamano.toInt(), tamano.toInt());
    final bytes = await imagen.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      (bytes as ByteData).buffer.asUint8List(),
    );
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
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: _centroInicial,
              zoom: 14.5,
            ),
            markers: _marcadores,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (controlador) => _controladorMapa = controlador,
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
      bottomNavigationBar: _BarraNavegacionInferior(colorAzul: _colorAzul),
      floatingActionButton: null,
    );
  }

  @override
  void dispose() {
    _controladorMapa?.dispose();
    super.dispose();
  }
}

class _Alerta {
  final String id;
  final _TipoAlerta tipo;
  final String titulo;
  final LatLng posicion;

  const _Alerta({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.posicion,
  });
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

class _BarraNavegacionInferior extends StatelessWidget {
  final Color colorAzul;

  const _BarraNavegacionInferior({required this.colorAzul});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, -2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _item(icono: Icons.map_rounded, etiqueta: 'Mapa', activo: true),
          _item(icono: Icons.add_circle_outline_rounded, etiqueta: 'Reportar', activo: false),
          _item(
            icono: Icons.notifications_none_rounded,
            etiqueta: 'Alertas',
            activo: false,
            conInsignia: true,
          ),
          _item(icono: Icons.person_outline_rounded, etiqueta: 'Perfil', activo: false),
        ],
      ),
    );
  }

  Widget _item({
    required IconData icono,
    required String etiqueta,
    required bool activo,
    bool conInsignia = false,
  }) {
    final color = activo ? colorAzul : const Color(0xFF9CA3AF);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: activo ? colorAzul.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icono, color: color, size: 24),
              if (conInsignia)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE53935),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          etiqueta,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
