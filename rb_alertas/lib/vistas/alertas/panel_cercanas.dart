import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:rb_alertas/config/mapa_config.dart';
import 'package:rb_alertas/modelos/reporte.dart';
import 'package:rb_alertas/servicios/estado_alertas_servicio.dart';
import 'package:rb_alertas/servicios/reporte_servicio.dart';
import 'package:rb_alertas/servicios/ubicacion_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/vistas/alertas/widgets/carga_panel.dart';
import 'package:rb_alertas/vistas/alertas/widgets/piezas_alertas.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';


/// Radio en kilómetros que se consulta a la API para las alertas cercanas.
const _radioKm = 2.0;

/// Antigüedad hasta la que una alerta se muestra en la sección "Recientes".
const _ventanaRecientes = Duration(hours: 2);

enum _Filtro { todas, activas, validadas }

/// Pestaña "Cerca de ti": incidentes vigentes alrededor del teléfono. No
/// necesita sesión; sin GPS usa el centro de la comuna y lo avisa.
class PanelCercanas extends StatefulWidget {
  const PanelCercanas({super.key});

  @override
  State<PanelCercanas> createState() => _PanelCercanasState();
}

class _PanelCercanasState extends State<PanelCercanas>
    with AutomaticKeepAliveClientMixin, CargaPanel {
  final _reporteServicio = ReporteServicio();
  final _ubicacionServicio = UbicacionServicio();

  List<ReporteCercano> _alertas = [];
  _Filtro _filtro = _Filtro.todas;
  DateTime? _actualizado;

  /// Aviso cuando no se pudo leer el GPS y se usa el centro por defecto.
  String? _avisoUbicacion;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() => ejecutarCarga(requiereSesion: false, () async {
    final (punto, aviso) = await _ubicacion();
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
    });
  });

  /// Ubicación del teléfono, o el centro por defecto con el motivo.
  Future<(LatLng, String?)> _ubicacion() async {
    try {
      return (await _ubicacionServicio.obtenerUbicacionActual(), null);
    } on UbicacionServicioException catch (e) {
      return (MapaConfig.centroPorDefecto, e.mensaje);
    } catch (_) {
      return (MapaConfig.centroPorDefecto, 'No pudimos obtener tu ubicación: mostramos el centro de la comuna');
    }
  }

  List<ReporteCercano> get _visibles {
    bool tiene(ReporteCercano a, EstadoVisual e) => EstadoVisual.desdeApi(a.estado) == e;
    return switch (_filtro) {
      _Filtro.todas => _alertas,
      _Filtro.activas => _alertas.where((a) => tiene(a, EstadoVisual.activa)).toList(),
      _Filtro.validadas => _alertas.where((a) => tiene(a, EstadoVisual.validada)).toList(),
    };
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
      contador: [
        if (alerta.totalReportes > 1) '${alerta.totalReportes} reportes',
        '${alerta.confirmaciones} ${alerta.confirmaciones == 1 ? 'confirma' : 'confirman'}',
      ].join(' · '),
      onTap: () => abrirDetalle(alerta.id, _cargar),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return construirPanel(
      tituloError: 'No se pudieron cargar las alertas',
      recargar: _cargar,
      contenido: _lista,
    );
  }

  Widget _lista() {
    final visibles = _visibles;
    final ahora = DateTime.now();
    final recientes = visibles
        .where((a) => a.fechaCreacion != null && ahora.difference(a.fechaCreacion!) <= _ventanaRecientes)
        .toList();
    final anteriores = visibles.where((a) => !recientes.contains(a)).toList();

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          _resumen(),
          if (_avisoUbicacion != null) ...[
            const SizedBox(height: 12),
            AvisoRB(texto: _avisoUbicacion!),
          ],
          const SizedBox(height: 20),
          FiltrosEstado<_Filtro>(
            opciones: const [
              (_Filtro.todas, 'Todas'),
              (_Filtro.activas, 'Activas'),
              (_Filtro.validadas, 'Validadas'),
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

  /// Tarjeta verde con el total de alertas activas en el radio.
  Widget _resumen() {
    final total = _alertas.length;
    return TarjetaSuricata(
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
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
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
    );
  }
}
