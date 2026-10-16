import 'package:flutter/material.dart';
import 'package:rb_alertas/servicios/estado_alertas_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/alertas_vista.dart';
import 'package:rb_alertas/vistas/grupos_vista.dart';
import 'package:rb_alertas/vistas/mapa_vista.dart';
import 'package:rb_alertas/vistas/perfil_vista.dart';

/// Secciones de la barra inferior. Reportar ya no es una pestaña: se abre con
/// el botón verde del mapa.
enum SeccionApp { mapa, grupos, alertas, perfil }

class BarraNavegacionInferior extends StatelessWidget {
  final SeccionApp seccionActiva;
  // En false los botones no responden (por ejemplo, mientras se envía algo).
  final bool habilitada;

  const BarraNavegacionInferior({
    super.key,
    required this.seccionActiva,
    this.habilitada = true,
  });

  void _irA(BuildContext context, SeccionApp seccion) {
    if (!habilitada || seccion == seccionActiva) return;

    final Widget destino = switch (seccion) {
      SeccionApp.mapa => const MapaVista(),
      SeccionApp.grupos => const GruposVista(),
      SeccionApp.alertas => const AlertasVista(),
      SeccionApp.perfil => const PerfilVista(),
    };

    // Se limpia la pila: la barra también aparece en pantallas apiladas
    // (por ejemplo Zonas seguras sobre Perfil) y no deben quedar debajo.
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animacion, animacionSecundaria) => destino,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      (ruta) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vertical = context.pantallaBaja ? 6.0 : 10.0;
    return Container(
      padding: EdgeInsets.only(
        top: vertical,
        bottom: vertical + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: RBColores.linea)),
      ),
      child: Row(
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
            seccion: SeccionApp.grupos,
            icono: Icons.people_outline_rounded,
            iconoActivo: Icons.people_rounded,
            etiqueta: 'Grupos',
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
    final color = activo ? RBColores.azul : RBColores.texto2;

    return Expanded(
      child: InkWell(
        onTap: () => _irA(context, seccion),
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: context.pantallaAngosta ? 60 : 72,
              height: context.pantallaBaja ? 32 : 36,
              decoration: BoxDecoration(
                color: activo ? RBColores.azul50 : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(activo ? iconoActivo : icono, color: color, size: 26),
                  if (conInsignia)
                    const Positioned(left: 38, top: -4, child: _InsigniaAlertas()),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              etiqueta,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Contador rojo de alertas de zona sin leer. Si solo hay incidentes nuevos
/// cerca (sin número que mostrar), se ve como un punto.
class _InsigniaAlertas extends StatelessWidget {
  const _InsigniaAlertas();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([EstadoAlertas.hayNuevas, EstadoAlertas.cantidad]),
      builder: (context, _) {
        final cantidad = EstadoAlertas.cantidad.value;
        if (cantidad <= 0) {
          if (!EstadoAlertas.hayNuevas.value) return const SizedBox.shrink();
          return Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: RBColores.rojo,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          );
        }
        return Container(
          constraints: const BoxConstraints(minWidth: 22),
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: RBColores.rojo,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Text(
            cantidad > 99 ? '99+' : '$cantidad',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        );
      },
    );
  }
}
