import 'package:flutter/material.dart';
import 'package:rb_alertas/vistas/mapa_vista.dart';
import 'package:rb_alertas/vistas/reportar_incidente_vista.dart';

enum SeccionApp { mapa, reportar, alertas, perfil }

class BarraNavegacionInferior extends StatelessWidget {
  final SeccionApp seccionActiva;

  const BarraNavegacionInferior({super.key, required this.seccionActiva});

  static const _colorAzul = Color(0xFF0056D2);
  static const _colorInactivo = Color(0xFF6B7280);

  void _irA(BuildContext context, SeccionApp seccion) {
    if (seccion == seccionActiva) return;

    final Widget? destino = switch (seccion) {
      SeccionApp.mapa => const MapaVista(),
      SeccionApp.reportar => const ReportarIncidenteVista(),
      // Alertas y Perfil todavía no tienen pantalla.
      SeccionApp.alertas || SeccionApp.perfil => null,
    };
    if (destino == null) return;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animacion, animacionSecundaria) => destino,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 8,
        bottom: 8 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, -2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _item(
            context,
            seccion: SeccionApp.mapa,
            icono: Icons.map_outlined,
            iconoActivo: Icons.map_rounded,
            etiqueta: 'Mapa',
          ),
          _item(
            context,
            seccion: SeccionApp.reportar,
            icono: Icons.add_circle_outline_rounded,
            iconoActivo: Icons.add_circle_rounded,
            etiqueta: 'Reportar',
          ),
          _item(
            context,
            seccion: SeccionApp.alertas,
            icono: Icons.notifications_none_rounded,
            iconoActivo: Icons.notifications_rounded,
            etiqueta: 'Alertas',
            conInsignia: true,
          ),
          _item(
            context,
            seccion: SeccionApp.perfil,
            icono: Icons.person_outline_rounded,
            iconoActivo: Icons.person_rounded,
            etiqueta: 'Perfil',
          ),
        ],
      ),
    );
  }

  Widget _item(
    BuildContext context, {
    required SeccionApp seccion,
    required IconData icono,
    required IconData iconoActivo,
    required String etiqueta,
    bool conInsignia = false,
  }) {
    final activo = seccion == seccionActiva;

    // "Reportar" activo va como botón azul relleno, igual que en el diseño.
    if (activo && seccion == SeccionApp.reportar) {
      return InkWell(
        onTap: () => _irA(context, seccion),
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: _colorAzul,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(iconoActivo, color: Colors.white, size: 24),
              const SizedBox(height: 2),
              Text(
                etiqueta,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final color = activo ? _colorAzul : _colorInactivo;
    return InkWell(
      onTap: () => _irA(context, seccion),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: activo ? _colorAzul.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(activo ? iconoActivo : icono, color: color, size: 24),
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
      ),
    );
  }
}
