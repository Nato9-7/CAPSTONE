import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/servicios/ubicacion_servicio.dart';
import 'package:rb_alertas/servicios/zonas_servicio.dart';

/// Crea o edita una zona segura.
class ZonaDetalleVista extends StatefulWidget {
  final ZonaSegura? zona;
  final List<int> radiosPermitidos;

  const ZonaDetalleVista({
    super.key,
    this.zona,
    required this.radiosPermitidos,
  });

  @override
  State<ZonaDetalleVista> createState() => _ZonaDetalleVistaState();
}

class _ZonaDetalleVistaState extends State<ZonaDetalleVista> {
  static const _colorAzul = Color(0xFF0056D2);
  static const _colorFondo = Color(0xFFF7F8FC);
  static const _colorTitulo = Color(0xFF111827);
  static const _colorTextoGris = Color(0xFF6B7280);
  static const _colorBorde = Color(0xFFE5E7EB);
  static const _colorRojo = Color(0xFFDC2626);

  /// Centro del mapa cuando no hay zona ni GPS: plaza de armas de Puerto Montt.
  static const _centroPorDefecto = LatLng(-41.4717, -72.9369);

  /// Velocidad a pie para traducir el radio a minutos de caminata (4 km/h).
  static const _metrosPorMinutoCaminando = 66.7;

  final _servicio = ZonasServicio();
  final _ubicacionServicio = UbicacionServicio();
  final _mapController = MapController();
  final _nombreCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();

  late TipoZona _tipo;
  late LatLng _centro;
  late int _radio;
  bool _guardando = false;
  bool _buscandoUbicacion = false;

  /// Mientras el usuario mueve el mapa no se le pisa lo que escribió a mano.
  bool _direccionEditadaAMano = false;

  bool get _esNueva => widget.zona == null;

  List<int> get _radios => widget.radiosPermitidos.isEmpty
      ? const [500, 1000, 2000]
      : widget.radiosPermitidos;

  @override
  void initState() {
    super.initState();
    final zona = widget.zona;
    _tipo = zona?.tipo ?? TipoZona.casa;
    _centro = zona != null
        ? LatLng(zona.latitud, zona.longitud)
        : _centroPorDefecto;
    // Si el radio guardado ya no está entre los permitidos, se usa el del medio.
    _radio = zona != null && _radios.contains(zona.radioMetros)
        ? zona.radioMetros
        : _radios[_radios.length ~/ 2];
    _nombreCtrl.text = zona != null && zona.tipo == TipoZona.otro
        ? zona.nombre
        : '';
    _direccionCtrl.text = zona?.direccion ?? '';
    if (zona == null) _usarUbicacionActual(silencioso: true);
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _direccionCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  /// Centra el mapa en el GPS. [silencioso] evita el aviso de error al abrir
  /// una zona nueva: si no hay permiso, el usuario igual puede mover el mapa.
  Future<void> _usarUbicacionActual({bool silencioso = false}) async {
    setState(() => _buscandoUbicacion = true);
    try {
      final punto = await _ubicacionServicio.obtenerUbicacionActual();
      if (!mounted) return;
      setState(() => _centro = punto);
      _mapController.move(punto, 15);
      _completarDireccion(punto);
    } on UbicacionServicioException catch (e) {
      if (!silencioso) _mostrarMensaje(e.mensaje);
    } catch (_) {
      if (!silencioso) _mostrarMensaje('No se pudo obtener tu ubicación');
    } finally {
      if (mounted) setState(() => _buscandoUbicacion = false);
    }
  }

  /// Rellena la dirección con geocodificación inversa, salvo que el usuario
  /// ya haya escrito la suya.
  Future<void> _completarDireccion(LatLng punto) async {
    if (_direccionEditadaAMano) return;
    final direccion = await _ubicacionServicio.obtenerDireccion(punto);
    if (!mounted || direccion == null || _direccionEditadaAMano) return;
    setState(() => _direccionCtrl.text = direccion);
  }

  String _radioTexto(int metros) => metros < 1000
      ? '$metros m'
      : '${(metros / 1000).toStringAsFixed(metros % 1000 == 0 ? 0 : 1)} km';

  int get _minutosCaminando => (_radio / _metrosPorMinutoCaminando).round();

  Future<void> _guardar() async {
    final token = Sesion.token;
    if (token == null || token.isEmpty) {
      _mostrarMensaje('Inicia sesión para guardar tus zonas');
      return;
    }
    if (_tipo.nombreLibre && _nombreCtrl.text.trim().isEmpty) {
      _mostrarMensaje('Escribe un nombre para la zona');
      return;
    }

    setState(() => _guardando = true);
    try {
      if (_esNueva) {
        await _servicio.crear(
          token: token,
          tipo: _tipo,
          nombre: _nombreCtrl.text,
          latitud: _centro.latitude,
          longitud: _centro.longitude,
          radioMetros: _radio,
          direccion: _direccionCtrl.text,
        );
      } else {
        await _servicio.actualizar(
          token: token,
          idZona: widget.zona!.id,
          tipo: _tipo,
          nombre: _nombreCtrl.text,
          latitud: _centro.latitude,
          longitud: _centro.longitude,
          radioMetros: _radio,
          direccion: _direccionCtrl.text,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ZonasServicioException catch (e) {
      _mostrarMensaje(e.mensaje);
    } catch (_) {
      _mostrarMensaje('No se pudo conectar con el servidor');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _eliminar() async {
    final zona = widget.zona;
    final token = Sesion.token;
    if (zona == null || token == null) return;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contextoDialogo) => AlertDialog(
        title: const Text('Eliminar zona'),
        content: Text(
          '¿Eliminar «${zona.nombre}»? Dejarás de recibir alertas de lo que '
          'ocurra en ese sector.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contextoDialogo, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(contextoDialogo, true),
            style: TextButton.styleFrom(foregroundColor: _colorRojo),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    setState(() => _guardando = true);
    try {
      await _servicio.eliminar(token: token, idZona: zona.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ZonasServicioException catch (e) {
      _mostrarMensaje(e.mensaje);
    } catch (_) {
      _mostrarMensaje('No se pudo conectar con el servidor');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        foregroundColor: _colorTitulo,
        title: Text(
          _esNueva ? 'Nueva zona segura' : widget.zona!.nombre,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (!_esNueva)
            IconButton(
              onPressed: _guardando ? null : _eliminar,
              icon: const Icon(Icons.delete_outline, color: _colorRojo),
              tooltip: 'Eliminar zona',
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _tarjetaTipo(),
            const SizedBox(height: 16),
            _tarjetaUbicacion(),
            const SizedBox(height: 16),
            _tarjetaRadio(),
            const SizedBox(height: 16),
            _vistaPrevia(),
          ],
        ),
      ),
      bottomNavigationBar: _barraAcciones(),
    );
  }

  Widget _tarjeta({required Widget hijo}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _colorBorde),
      ),
      child: hijo,
    );
  }

  Widget _titulo(IconData icono, String texto) {
    return Row(
      children: [
        Icon(icono, size: 19, color: _colorAzul),
        const SizedBox(width: 8),
        Text(
          texto,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _colorTitulo,
          ),
        ),
      ],
    );
  }

  Widget _tarjetaTipo() {
    return _tarjeta(
      hijo: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _titulo(Icons.bookmark_outline, 'Tipo de lugar'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tipo in TipoZona.values)
                ChoiceChip(
                  selected: _tipo == tipo,
                  onSelected: (_) => setState(() => _tipo = tipo),
                  avatar: Icon(
                    tipo.icono,
                    size: 17,
                    color: _tipo == tipo ? Colors.white : _colorTextoGris,
                  ),
                  label: Text(tipo.etiqueta),
                  labelStyle: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _tipo == tipo ? Colors.white : _colorTitulo,
                  ),
                  selectedColor: _colorAzul,
                  backgroundColor: const Color(0xFFF3F4F6),
                  showCheckmark: false,
                  side: BorderSide(
                    color: _tipo == tipo ? _colorAzul : _colorBorde,
                  ),
                ),
            ],
          ),
          // Solo "Otro lugar" lleva nombre propio: en los demás lo fija el
          // servidor, y así el nombre guardado siempre corresponde al icono.
          if (_tipo.nombreLibre) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _nombreCtrl,
              maxLength: 60,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Nombre de la zona',
                hintText: 'Colegio, casa de mis padres…',
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tarjetaUbicacion() {
    return _tarjeta(
      hijo: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _titulo(Icons.location_on_outlined, 'Ubicación'),
          const SizedBox(height: 6),
          const Text(
            'Mueve el mapa hasta dejar el punto sobre el lugar exacto.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: _colorTextoGris,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 200,
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _centro,
                      initialZoom: 15,
                      minZoom: 11,
                      maxZoom: 18,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
                      ),
                      // El pin está fijo al centro: lo que se mueve es el mapa.
                      onPositionChanged: (posicion, hayGesto) {
                        if (!hayGesto) return;
                        setState(() => _centro = posicion.center);
                      },
                      // Al soltar, se intenta rellenar la dirección del punto.
                      onMapEvent: (evento) {
                        if (evento is MapEventMoveEnd)
                          _completarDireccion(_centro);
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.rbalertas.rb_alertas',
                      ),
                    ],
                  ),
                  const IgnorePointer(
                    child: Center(
                      child: Padding(
                        // El icono apunta hacia abajo: se sube media altura
                        // para que la punta quede justo en el centro del mapa.
                        padding: EdgeInsets.only(bottom: 34),
                        child: Icon(
                          Icons.location_on,
                          size: 34,
                          color: _colorAzul,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: FloatingActionButton.small(
                      heroTag: 'gps_zona',
                      backgroundColor: Colors.white,
                      foregroundColor: _colorAzul,
                      onPressed: _buscandoUbicacion
                          ? null
                          : () => _usarUbicacionActual(),
                      child: _buscandoUbicacion
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _direccionCtrl,
            maxLength: 255,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => _direccionEditadaAMano = true,
            decoration: InputDecoration(
              labelText: 'Dirección de referencia',
              hintText: 'Av. Presidente Ibáñez 1234',
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaRadio() {
    final indice = _radios.indexOf(_radio).clamp(0, _radios.length - 1);
    return _tarjeta(
      hijo: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _titulo(Icons.my_location, 'Radio de Cobertura')),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _colorAzul,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _radioTexto(_radio),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Define el área de monitoreo alrededor de esta zona segura.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: _colorTextoGris,
            ),
          ),
          const SizedBox(height: 8),
          // El slider se mueve por posiciones, no por metros: así solo existen
          // los valores que el servidor acepta y no hay estados intermedios.
          Slider(
            value: indice.toDouble(),
            min: 0,
            max: (_radios.length - 1).toDouble(),
            divisions: _radios.length - 1,
            activeColor: _colorAzul,
            onChanged: (valor) =>
                setState(() => _radio = _radios[valor.round()]),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final metros in _radios)
                Text(
                  _radioTexto(metros),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: metros == _radio
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: metros == _radio ? _colorAzul : _colorTextoGris,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5FD),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 18, color: _colorAzul),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Con ${_radioTexto(_radio)} de radio, recibirás alertas de '
                    'incidentes reportados a menos de $_minutosCaminando minutos '
                    'caminando desde esta zona.',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: _colorTitulo,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vistaPrevia() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              'VISTA PREVIA DE COBERTURA',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: _colorTextoGris,
              ),
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(15),
            ),
            child: SizedBox(
              height: 190,
              child: FlutterMap(
                // Mapa solo de lectura: el círculo se ajusta al radio elegido.
                options: MapOptions(
                  initialCenter: _centro,
                  // El zoom baja a medida que crece el radio para que el
                  // círculo siempre entre completo en el recuadro.
                  initialZoom: _radio >= 2000
                      ? 12.5
                      : (_radio >= 1000 ? 13.5 : 14.5),
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.rbalertas.rb_alertas',
                  ),
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: _centro,
                        radius: _radio.toDouble(),
                        useRadiusInMeter: true,
                        color: _colorAzul.withValues(alpha: 0.15),
                        borderColor: _colorAzul,
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _centro,
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _barraAcciones() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _colorBorde)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _guardando
                    ? null
                    : () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: _colorBorde),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Descartar',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _colorTitulo,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _guardando ? null : _guardar,
                style: FilledButton.styleFrom(
                  backgroundColor: _colorAzul,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _guardando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(
                  _esNueva ? 'Guardar zona' : 'Guardar Cambios',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
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
