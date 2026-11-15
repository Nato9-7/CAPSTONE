import 'package:flutter/material.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/alertas/panel_cercanas.dart';
import 'package:rb_alertas/vistas/alertas/panel_mis_reportes.dart';
import 'package:rb_alertas/vistas/alertas/panel_mis_zonas.dart';
import 'package:rb_alertas/widgets/barra_navegacion_inferior.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Pantalla "Alertas": incidentes vigentes cerca del usuario, alertas de sus
/// zonas seguras e historial de sus reportes.
class AlertasVista extends StatefulWidget {
  final int pestanaInicial;

  const AlertasVista({super.key, this.pestanaInicial = 0});

  @override
  State<AlertasVista> createState() => _AlertasVistaState();
}

class _AlertasVistaState extends State<AlertasVista>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.pestanaInicial.clamp(0, 2),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RBColores.fondo,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, context.pantallaBaja ? 14 : 28, 20, 14),
              child: const TituloPantalla('Alertas'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SelectorSegmentado(
                controlador: _tabs,
                opciones: const ['Cerca de ti', 'Mis zonas', 'Mis reportes'],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: const [PanelCercanas(), PanelMisZonas(), PanelMisReportes()],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const BarraNavegacionInferior(
        seccionActiva: SeccionApp.alertas,
      ),
    );
  }
}
