import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:rb_alertas/config/api_config.dart';
import 'package:rb_alertas/servicios/reporte_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Detalle de un reporte, al tocar su pin en el mapa. Devuelve `true` al
/// cerrarse si el reporte cambió (por ejemplo, se marcó como resuelto).
class DetalleIncidenteVista extends StatefulWidget {
  final int idReporte;

  const DetalleIncidenteVista({super.key, required this.idReporte});

  @override
  State<DetalleIncidenteVista> createState() => _DetalleIncidenteVistaState();
}

class _DetalleIncidenteVistaState extends State<DetalleIncidenteVista> {
  static const _colorAzul = Color(0xFF0056D2);
  static const _colorFondo = Color(0xFFF7F8FC);
  static const _colorTitulo = Color(0xFF111827);
  static const _colorTexto = Color(0xFF4B5563);
  static const _colorBorde = Color(0xFFE5E7EB);
  static const _colorRojo = Color(0xFFEF4444);
  static const _colorVerde = Color(0xFF16A34A);

  final _reporteServicio = ReporteServicio();

  DetalleReporte? _detalle;
  String? _error;
  bool _resolviendo = false;
  bool _cambio = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final detalle = await _reporteServicio.obtenerDetalle(
        widget.idReporte,
        token: Sesion.token,
      );
      if (!mounted) return;
      setState(() => _detalle = detalle);
    } on ReporteServicioException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo conectar con el servidor');
    }
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // ---------------------------------------------------------------------------
  // Textos derivados

  // La BD no guarda un título: se arma con la categoría y la calle.
  String _titulo(DetalleReporte d) {
    final calle = d.direccion?.split(',').first.trim();
    return (calle == null || calle.isEmpty) ? d.categoria : '${d.categoria} en $calle';
  }

  String _textoHora(DateTime fecha) {
    String dos(int n) => n.toString().padLeft(2, '0');
    final ahora = DateTime.now();
    final dias = DateTime(ahora.year, ahora.month, ahora.day)
        .difference(DateTime(fecha.year, fecha.month, fecha.day))
        .inDays;
    final hora = '${dos(fecha.hour)}:${dos(fecha.minute)} hrs';
    if (dias == 0) return '$hora · Hoy';
    if (dias == 1) return '$hora · Ayer';
    return '$hora · ${dos(fecha.day)}-${dos(fecha.month)}-${fecha.year}';
  }

  String _iniciales(String nombre) {
    final partes = nombre.split(' ').where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty || nombre == 'Anónimo') return '?';
    final segunda = partes.length > 1 ? partes[1][0] : '';
    return (partes.first[0] + segunda).toUpperCase();
  }

  bool _esVideo(String url) {
    final u = url.toLowerCase();
    return u.endsWith('.mp4') || u.endsWith('.mov') || u.endsWith('.webm');
  }

  // ---------------------------------------------------------------------------
  // Acciones

  Future<void> _contactarEmergencias(DetalleReporte d) async {
    final entidad = d.emergencia;
    if (entidad == null) {
      _mostrarMensaje('No hay un número de emergencia asociado a este reporte');
      return;
    }
    final llamar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contactar emergencias'),
        content: Text('¿Llamar a ${entidad.nombre} al ${entidad.telefono}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _colorRojo),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.phone, size: 18),
            label: const Text('Llamar'),
          ),
        ],
      ),
    );
    if (llamar != true) return;

    final abierta = await launchUrl(Uri(scheme: 'tel', path: entidad.telefono))
        .catchError((_) => false);
    if (!abierta && mounted) {
      _mostrarMensaje('Marca al ${entidad.telefono} (${entidad.nombre})');
    }
  }

  Future<void> _compartir(DetalleReporte d) async {
    final lat = d.latitud.toStringAsFixed(5);
    final lon = d.longitud.toStringAsFixed(5);
    final texto = '🚨 ${_titulo(d)}\n'
        '${d.descripcion}\n'
        '${d.direccion != null ? '📍 ${d.direccion}\n' : ''}'
        'https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=17/$lat/$lon\n'
        '— Reportado en RB Alertas';
    // En web, share_plus abre el programa de correo cuando el navegador no
    // tiene hoja para compartir (casi todos los de escritorio): se copia el texto.
    if (!kIsWeb) {
      try {
        await SharePlus.instance.share(ShareParams(text: texto, subject: _titulo(d)));
        return;
      } catch (_) {
        // si falla, se copia al portapapeles
      }
    }
    await Clipboard.setData(ClipboardData(text: texto));
    if (mounted) _mostrarMensaje('Copiado: pégalo donde quieras compartirlo');
  }

  Future<void> _marcarResuelto(DetalleReporte d) async {
    final token = Sesion.token;
    if (token == null || token.isEmpty) {
      _mostrarMensaje('Debes iniciar sesión');
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marcar como resuelto'),
        content: const Text(
          'El reporte dejará de mostrarse en el mapa. ¿Confirmas que el incidente está resuelto?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _colorVerde),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí, está resuelto'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _resolviendo = true);
    try {
      await _reporteServicio.marcarResuelto(d.id, token);
      _cambio = true;
      if (!mounted) return;
      _mostrarMensaje('Reporte marcado como resuelto');
      await _cargar();
    } on ReporteServicioException catch (e) {
      if (mounted) _mostrarMensaje(e.mensaje);
    } catch (_) {
      if (mounted) _mostrarMensaje('No se pudo conectar con el servidor');
    } finally {
      if (mounted) setState(() => _resolviendo = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Interfaz

  @override
  Widget build(BuildContext context) {
    // Al volver al mapa se avisa si el reporte cambió, para recargar los pines.
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _cambio);
      },
      child: Scaffold(
        backgroundColor: _colorFondo,
        appBar: AppBar(
          backgroundColor: _colorFondo,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: _colorAzul),
            onPressed: () => Navigator.pop(context, _cambio),
          ),
          title: const Text(
            'Detalle de Incidente',
            style: TextStyle(color: _colorAzul, fontWeight: FontWeight.w700, fontSize: 18),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Color(0xFF374151)),
              onPressed: () {},
            ),
          ],
        ),
        body: _cuerpo(),
      ),
    );
  }

  Widget _cuerpo() {
    final detalle = _detalle;
    if (_error != null && detalle == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _colorTexto)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    if (detalle == null) {
      return const Center(child: CircularProgressIndicator(color: _colorAzul));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _imagen(detalle),
              const SizedBox(height: 14),
              _tarjetaInformacion(detalle),
              const SizedBox(height: 14),
              _tarjetaUbicacion(detalle),
              const SizedBox(height: 18),
              _botonEmergencias(detalle),
              const SizedBox(height: 10),
              _botonCompartir(detalle),
              if (detalle.esAutor || !detalle.activo) ...[
                const SizedBox(height: 22),
                _botonResuelto(detalle),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _imagen(DetalleReporte d) {
    final color = colorCategoria(d.categoriaCodigo, colorHex: d.colorHex);
    final icono = iconoCategoria(d.categoriaCodigo);
    final url = d.imagenes.isNotEmpty ? d.imagenes.first : null;

    Widget marcador({bool video = false}) => Container(
          color: color.withValues(alpha: 0.12),
          child: Center(
            child: Icon(video ? Icons.play_circle_outline : icono, size: 56, color: color),
          ),
        );

    final Widget fondo;
    if (url == null) {
      fondo = marcador();
    } else if (_esVideo(url)) {
      fondo = InkWell(
        onTap: () => launchUrl(Uri.parse(ApiConfig.urlArchivo(url))),
        child: marcador(video: true),
      );
    } else {
      fondo = Image.network(
        ApiConfig.urlArchivo(url),
        fit: BoxFit.cover,
        loadingBuilder: (context, hijo, progreso) => progreso == null
            ? hijo
            : Container(
                color: color.withValues(alpha: 0.08),
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
        errorBuilder: (context, error, pila) => marcador(),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 180,
        child: Stack(
          fit: StackFit.expand,
          children: [
            fondo,
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icono, size: 14, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(
                      d.categoria,
                      style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
            if (!d.activo)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: _colorVerde, borderRadius: BorderRadius.circular(20)),
                  child: const Text(
                    'Resuelto',
                    style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            if (d.fechaCreacion != null)
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4)],
                  ),
                  child: Text(
                    _textoHora(d.fechaCreacion!),
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _colorTitulo),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  BoxDecoration get _estiloTarjeta => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _colorBorde),
      );

  Widget _tarjetaInformacion(DetalleReporte d) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _estiloTarjeta,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _titulo(d),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _colorTitulo, height: 1.25),
          ),
          const SizedBox(height: 8),
          Text(d.descripcion, style: const TextStyle(fontSize: 14, color: _colorTexto, height: 1.5)),
          const SizedBox(height: 14),
          const Divider(height: 1, color: _colorBorde),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _colorAzul,
                child: Text(
                  _iniciales(d.autor),
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reportado por: ${d.autor}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _colorTitulo),
                    ),
                    Text(
                      d.esAutor ? 'Tú reportaste este incidente' : 'Autor del reporte',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tarjetaUbicacion(DetalleReporte d) {
    final punto = LatLng(d.latitud, d.longitud);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _estiloTarjeta,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.location_on_outlined, color: _colorAzul, size: 20),
              SizedBox(width: 6),
              Text('Ubicación', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: _colorTitulo)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 140,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: punto,
                  initialZoom: 16,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.rbalertas.rb_alertas',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: punto,
                        width: 36,
                        height: 36,
                        alignment: Alignment.topCenter,
                        child: const Icon(Icons.location_on, color: _colorRojo, size: 36),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            d.direccion ?? '${d.latitud.toStringAsFixed(5)}, ${d.longitud.toStringAsFixed(5)}',
            style: const TextStyle(fontSize: 13, color: _colorTexto),
          ),
        ],
      ),
    );
  }

  Widget _botonEmergencias(DetalleReporte d) {
    return SizedBox(
      height: 46,
      child: ElevatedButton.icon(
        onPressed: () => _contactarEmergencias(d),
        style: ElevatedButton.styleFrom(
          backgroundColor: _colorRojo,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: const Icon(Icons.phone, size: 20),
        label: const Text('Contactar Emergencias', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _botonCompartir(DetalleReporte d) {
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: () => _compartir(d),
        style: OutlinedButton.styleFrom(
          foregroundColor: _colorAzul,
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFBFD3F5), width: 1.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: const Icon(Icons.share_outlined, size: 20),
        label: const Text('Compartir', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _botonResuelto(DetalleReporte d) {
    final resuelto = !d.activo;
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        // Solo el autor puede marcarlo; si ya está resuelto se muestra deshabilitado.
        onPressed: resuelto || _resolviendo ? null : () => _marcarResuelto(d),
        style: OutlinedButton.styleFrom(
          foregroundColor: _colorVerde,
          disabledForegroundColor: _colorVerde.withValues(alpha: 0.7),
          backgroundColor: Colors.white,
          side: BorderSide(color: _colorVerde.withValues(alpha: resuelto ? 0.4 : 0.8), width: 1.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: _resolviendo
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _colorVerde))
            : const Icon(Icons.check_circle_outline, size: 20),
        label: Text(
          resuelto ? 'Incidente resuelto' : 'Marcar como resuelto',
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
