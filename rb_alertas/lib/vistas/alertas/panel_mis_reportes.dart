import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/reporte.dart';
import 'package:rb_alertas/servicios/reporte_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/vistas/alertas/widgets/carga_panel.dart';
import 'package:rb_alertas/vistas/alertas/widgets/piezas_alertas.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

enum _Filtro { todos, activas, resueltas, vencidas }

/// Pestaña "Mis reportes": historial de reportes del usuario y su impacto.
class PanelMisReportes extends StatefulWidget {
  const PanelMisReportes({super.key});

  @override
  State<PanelMisReportes> createState() => _PanelMisReportesState();
}

class _PanelMisReportesState extends State<PanelMisReportes>
    with AutomaticKeepAliveClientMixin, CargaPanel {
  final _reporteServicio = ReporteServicio();

  List<MiReporte> _reportes = [];
  _Filtro _filtro = _Filtro.todos;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() => ejecutarCarga(() async {
    final reportes = await _reporteServicio.obtenerMisReportes();
    if (mounted) setState(() => _reportes = reportes);
  });

  List<MiReporte> get _visibles {
    List<MiReporte> con(EstadoMiReporte e) => _reportes.where((r) => r.estado == e).toList();
    return switch (_filtro) {
      _Filtro.todos => _reportes,
      _Filtro.activas => con(EstadoMiReporte.activa),
      _Filtro.resueltas => con(EstadoMiReporte.resuelta),
      _Filtro.vencidas => con(EstadoMiReporte.vencida),
    };
  }

  static EstadoVisual _estadoVisual(EstadoMiReporte estado) => switch (estado) {
    EstadoMiReporte.activa => EstadoVisual.activa,
    EstadoMiReporte.resuelta => EstadoVisual.resuelta,
    EstadoMiReporte.vencida => EstadoVisual.vencida,
    EstadoMiReporte.descartada => EstadoVisual.descartada,
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return construirPanel(
      tituloError: 'No se pudo cargar tu historial',
      detalleSinSesion: 'Necesitas una sesión abierta para ver tu historial de reportes.',
      recargar: _cargar,
      contenido: _lista,
    );
  }

  Widget _lista() {
    final visibles = _visibles;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          _impacto(),
          const SizedBox(height: 20),
          FiltrosEstado<_Filtro>(
            opciones: const [
              (_Filtro.todos, 'Todos'),
              (_Filtro.activas, 'Activas'),
              (_Filtro.resueltas, 'Resueltas'),
              (_Filtro.vencidas, 'Vencidas'),
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
                titulo: _reportes.isEmpty ? 'Todavía no has reportado nada' : 'Sin reportes en este filtro',
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
              onTap: () => abrirDetalle(reporte.id, _cargar),
            ),
        ],
      ),
    );
  }

  /// Tarjeta verde con reportes, apoyos recibidos y resueltos.
  Widget _impacto() {
    final apoyos = _reportes.fold<int>(0, (suma, r) => suma + r.apoyos);
    final resueltos = _reportes.where((r) => r.estado == EstadoMiReporte.resuelta).length;
    return TarjetaSuricata(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tu impacto en el barrio',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: context.pantallaAngosta ? 18 : 28,
            runSpacing: 8,
            children: [
              Cifra(valor: '${_reportes.length}', etiqueta: _reportes.length == 1 ? 'reporte' : 'reportes'),
              Cifra(valor: '$apoyos', etiqueta: apoyos == 1 ? 'apoyo' : 'apoyos'),
              Cifra(valor: '$resueltos', etiqueta: resueltos == 1 ? 'resuelto' : 'resueltos'),
            ],
          ),
        ],
      ),
    );
  }
}
