import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rb_alertas/servicios/aviso_zonas_riesgo.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/dialogos.dart';

/// Explica el aviso de zonas de riesgo antes de pedir permisos (solo la
/// primera vez que hay zonas). Devuelve true si el usuario quiso activarlo.
Future<bool> ofrecerAvisoZonasRiesgo(BuildContext context) async {
  final acepta = await showDialog<bool>(
    context: context,
    builder: (dialogo) => AlertDialog(
      icon: const Icon(Icons.gpp_maybe_rounded, color: RBColores.rojo, size: 32),
      title: const Text('¿Te avisamos al pasar por zonas de riesgo?'),
      content: const Text(
        'RB Alertas puede avisarte cuando entres a un lugar con robos o '
        'accidentes frecuentes, incluso con la app cerrada.\n\n'
        'Para eso usa tu ubicación en segundo plano: elige "Permitir todo el '
        'tiempo". Tu ubicación no se envía ni se guarda en el servidor; solo '
        'el teléfono la compara con las zonas. Puedes desactivarlo cuando quieras '
        'desde la tarjeta de cualquier zona.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogo, false), child: const Text('Ahora no')),
        FilledButton(onPressed: () => Navigator.pop(dialogo, true), child: const Text('Activar avisos')),
      ],
    ),
  );
  if (acepta == true && context.mounted) {
    await activarAvisoZonasRiesgo(context);
    return true;
  }
  if (acepta == false) await AvisoZonasRiesgo.rechazar();
  return false;
}

/// Pide los permisos del aviso y cuenta el resultado al usuario.
Future<void> activarAvisoZonasRiesgo(BuildContext context) async {
  final resultado = await AvisoZonasRiesgo.activar();
  if (!context.mounted) return;
  switch (resultado) {
    case ActivacionAviso.activado:
      mostrarAviso(context, 'Listo: te avisaremos al pasar por zonas de riesgo');
    case ActivacionAviso.soloConAppAbierta:
      mostrarAviso(
        context,
        'Te avisaremos con la app abierta. Para recibirlo con la app cerrada, '
        'elige "Permitir todo el tiempo" en la ubicación.',
        duracion: const Duration(seconds: 8),
        accion: SnackBarAction(label: 'Ajustes', onPressed: Geolocator.openAppSettings),
      );
    case ActivacionAviso.sinPermiso:
      mostrarAviso(context, 'Sin permiso de ubicación no podemos avisarte');
  }
}

/// Apaga el aviso desde la tarjeta de una zona.
Future<void> desactivarAvisoZonasRiesgo(BuildContext context) async {
  await AvisoZonasRiesgo.desactivar();
  if (context.mounted) mostrarAviso(context, 'Ya no te avisaremos al pasar por zonas de riesgo');
}
