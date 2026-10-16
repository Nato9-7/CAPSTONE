import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/servicios/zonas_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/zona_detalle_vista.dart';
import 'package:rb_alertas/widgets/barra_navegacion_inferior.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Lista de zonas seguras del usuario. Se entra desde Perfil.
class ZonasSegurasVista extends StatefulWidget {
  const ZonasSegurasVista({super.key});

  @override
  State<ZonasSegurasVista> createState() => _ZonasSegurasVistaState();
}

class _ZonasSegurasVistaState extends State<ZonasSegurasVista> {
  /// Centro del mapa resumen cuando aún no hay zonas: Puerto Montt.
  static const _centroPorDefecto = LatLng(-41.4717, -72.9369);

  final _servicio = ZonasServicio();
  ZonasUsuario? _datos;
  String? _error;
  bool _cargando = true;

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
        _error = 'Inicia sesión para configurar tus zonas seguras';
      });
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final datos = await _servicio.listar(token);
      if (!mounted) return;
      setState(() {
        _datos = datos;
        _cargando = false;
      });
    } on ZonasServicioException catch (e) {
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

  /// Abre el editor. Con [zona] en null se crea una nueva.
  /// Si el editor devuelve true, algo cambió y hay que recargar la lista.
  Future<void> _abrirDetalle({ZonaSegura? zona}) async {
    final datos = _datos;
    if (datos == null) return;
    final cambio = await ZonaDetalleVista.abrir(
      context,
      zona: zona,
      radiosPermitidos: datos.radiosPermitidos,
    );
    if (cambio == true) _cargar();
  }

  void _avisarTope() {
    final maximo = _datos?.maximo ?? 3;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Ya tienes $maximo zonas seguras. Elimina una para agregar otra.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RBColores.fondo,
      body: SafeArea(bottom: false, child: _cuerpo()),
      bottomNavigationBar: const BarraNavegacionInferior(
        seccionActiva: SeccionApp.perfil,
      ),
    );
  }

  Widget _encabezado() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 20, 16, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Volver',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded, size: 30, color: RBColores.tinta),
          ),
          const SizedBox(width: 6),
          const Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'Zonas seguras',
                style: TextStyle(
                  fontFamily: RBFuentes.titulos,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: RBColores.azul,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return Column(
        children: [
          _encabezado(),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }
    if (_error != null) {
      return Column(
        children: [
          _encabezado(),
          Expanded(
            child: EstadoVacio(
              icono: Icons.cloud_off_rounded,
              titulo: 'No se pudieron cargar tus zonas',
              detalle: _error!,
              accion: 'Reintentar',
              onAccion: _cargar,
            ),
          ),
        ],
      );
    }

    final datos = _datos!;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _encabezado(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Te avisaremos cuando alguien reporte un incidente dentro '
                  'del radio de tus ubicaciones.',
                  style: TextStyle(fontSize: 17, height: 1.45, color: RBColores.texto2),
                ),
                const SizedBox(height: 18),
                _mapaResumen(datos.zonas),
                const SizedBox(height: 26),
                const EtiquetaSeccion('Mis ubicaciones'),
                const SizedBox(height: 12),
                for (final zona in datos.zonas) _filaZona(zona),
                if (datos.zonas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Aún no tienes zonas seguras. Agrega tu casa o tu trabajo '
                      'para recibir alertas de lo que pase cerca, aunque no estés ahí.',
                      style: TextStyle(fontSize: 15, height: 1.45, color: RBColores.texto2),
                    ),
                  ),
                const SizedBox(height: 4),
                _botonAnadir(datos.puedeAgregar),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Mapa de solo lectura con todas las zonas y sus radios.
  Widget _mapaResumen(List<ZonaSegura> zonas) {
    final puntos = [for (final z in zonas) LatLng(z.latitud, z.longitud)];
    final MapOptions opciones;
    if (puntos.length > 1) {
      opciones = MapOptions(
        initialCameraFit: CameraFit.coordinates(
          coordinates: puntos,
          padding: const EdgeInsets.all(60),
          maxZoom: 15,
        ),
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
      );
    } else {
      opciones = MapOptions(
        initialCenter: puntos.isEmpty ? _centroPorDefecto : puntos.first,
        initialZoom: 14,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(RBRadios.tarjeta + 4),
      child: SizedBox(
        height: context.altoRelativo(0.3, minimo: 170, maximo: 240),
        child: Stack(
          children: [
            FlutterMap(
              options: opciones,
              children: [
                capaMapaBase(),
                CircleLayer(
                  circles: [
                    for (final z in zonas)
                      CircleMarker(
                        point: LatLng(z.latitud, z.longitud),
                        radius: z.radioMetros.toDouble(),
                        useRadiusInMeter: true,
                        color: RBColores.verde.withValues(alpha: 0.15),
                        borderColor: RBColores.verde,
                        borderStrokeWidth: 2.5,
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    for (final z in zonas)
                      Marker(
                        point: LatLng(z.latitud, z.longitud),
                        width: 40,
                        height: 40,
                        child: MarcadorZona(icono: z.tipo.icono),
                      ),
                  ],
                ),
              ],
            ),
            const Positioned(left: 6, bottom: 2, child: AtribucionMapa()),
          ],
        ),
      ),
    );
  }

  Widget _filaZona(ZonaSegura zona) {
    final direccion = zona.direccion?.trim();
    return TarjetaRB(
      onTap: () => _abrirDetalle(zona: zona),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
      child: Row(
        children: [
          Container(
            width: context.escala(56),
            height: context.escala(56),
            decoration: BoxDecoration(
              color: RBColores.verde50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(zona.tipo.icono, color: RBColores.verde, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  zona.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: RBColores.tinta,
                  ),
                ),
                if (direccion != null && direccion.isNotEmpty)
                  Text(
                    direccion,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15.5, color: RBColores.texto2),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: RBColores.verde50,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              zona.radioTexto,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: RBColores.verde,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: RBColores.placeholder, size: 26),
        ],
      ),
    );
  }

  Widget _botonAnadir(bool puedeAgregar) {
    // El botón nunca se oculta: si se deshabilitara sin más, el usuario
    // no sabría por qué. Al tocarlo en el tope, se explica el motivo.
    final color = puedeAgregar ? RBColores.azul : RBColores.texto2;
    return CustomPaint(
      painter: const BordePunteado(color: RBColores.placeholder, radio: RBRadios.tarjeta + 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(RBRadios.tarjeta + 4),
          onTap: puedeAgregar ? () => _abrirDetalle() : _avisarTope,
          child: SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, color: color, size: 28),
                const SizedBox(width: 10),
                Text(
                  'Añadir ubicación',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Círculo verde con el ícono blanco del tipo de zona.
class MarcadorZona extends StatelessWidget {
  final IconData icono;

  const MarcadorZona({super.key, required this.icono});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: RBColores.verde,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6),
        ],
      ),
      child: Icon(icono, color: Colors.white, size: 18),
    );
  }
}
