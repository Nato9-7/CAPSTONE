import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/modelos.dart';
import 'package:rb_alertas/servicios/estado_alertas_servicio.dart';
import 'package:rb_alertas/servicios/notificaciones_servicio.dart';
import 'package:rb_alertas/servicios/zonas_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/vistas/alertas/widgets/carga_panel.dart';
import 'package:rb_alertas/vistas/alertas/widgets/piezas_alertas.dart';
import 'package:rb_alertas/vistas/zonas/zonas_seguras_vista.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Pestaña "Mis zonas". A diferencia de "Cerca de ti", no depende de dónde
/// esté el teléfono: son los incidentes que cayeron dentro de una zona segura
/// configurada (o que un vecino compartió en un grupo), esté el usuario ahí o no.
class PanelMisZonas extends StatefulWidget {
  const PanelMisZonas({super.key});

  @override
  State<PanelMisZonas> createState() => _PanelMisZonasState();
}

class _PanelMisZonasState extends State<PanelMisZonas>
    with AutomaticKeepAliveClientMixin, CargaPanel {
  final _servicio = NotificacionesServicio();
  final _zonasServicio = ZonasServicio();

  List<AlertaDeZona> _alertas = const [];

  /// Solo alimentan las tarjetas de arriba: si fallan, la lista de alertas
  /// se muestra igual.
  List<ZonaSegura>? _zonas;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() => ejecutarCarga(() async {
    _cargarZonas();
    final datos = await _servicio.listar();
    if (!mounted) return;
    setState(() => _alertas = datos.alertas);
    EstadoAlertas.registrarZonasSinLeer(datos.noLeidas);
  });

  Future<void> _cargarZonas() async {
    try {
      final datos = await _zonasServicio.listar();
      if (mounted) setState(() => _zonas = datos.zonas);
    } catch (_) {
      // Sin zonas solo se ocultan las tarjetas.
    }
  }

  /// Abre el incidente y marca la alerta como leída. El cambio se pinta de
  /// inmediato en memoria para no esperar una recarga completa de la lista.
  Future<void> _abrir(AlertaDeZona alerta) async {
    if (!alerta.leida) {
      setState(() => alerta.leida = true);
      _servicio.marcarLeida(alerta.id);
      // La insignia se apaga en cuanto el usuario abre la última alerta sin leer.
      EstadoAlertas.registrarZonasSinLeer(_alertas.where((a) => !a.leida).length);
    }
    await abrirDetalle(alerta.reporte.id, _cargar);
  }

  Future<void> _abrirZonas() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ZonasSegurasVista()));
    if (mounted) _cargar();
  }

  /// Alertas vigentes de cada zona, para la línea "1 alerta" de su tarjeta.
  int _alertasVigentes(ZonaSegura zona) => _alertas.where((a) {
    final estado = EstadoVisual.desdeApi(a.reporte.estado);
    return a.zona?.id == zona.id && (estado == EstadoVisual.activa || estado == EstadoVisual.validada);
  }).length;

  Widget _fila(AlertaDeZona alerta) {
    final reporte = alerta.reporte;
    final tiempo = tiempoRelativo(alerta.fechaEnvio ?? reporte.fechaCreacion);
    final distancia = alerta.distanciaMetros == null ? null : 'a ${distanciaLegible(alerta.distanciaMetros!)}';
    final detalle = alerta.zona == null
        ? '${capitalizar(alerta.referencia)} · $tiempo'
        : ['En ${alerta.zona!.nombre}', if (tiempo.isNotEmpty) tiempo, ?distancia].join(' · ');
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
    return construirPanel(
      tituloError: 'No se pudieron cargar tus alertas',
      detalleSinSesion: 'Necesitas una cuenta para configurar zonas seguras y recibir sus alertas.',
      recargar: _cargar,
      contenido: _lista,
    );
  }

  Widget _lista() {
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: RBColores.azul),
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
                    TarjetaZona(zona: zona, alertas: _alertasVigentes(zona), onTap: _abrirZonas),
                    const SizedBox(width: 12),
                  ],
                  if (zonas.isEmpty) TarjetaAnadirZona(onTap: _abrirZonas),
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
