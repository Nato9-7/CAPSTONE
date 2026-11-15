import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/reporte.dart';
import 'package:rb_alertas/tema/rb_tema.dart';

/// Pregunta si llamar a la entidad de emergencia. true = llamar.
Future<bool> confirmarLlamada(BuildContext context, EntidadEmergencia entidad) async {
  final llamar = await showDialog<bool>(
    context: context,
    builder: (dialogo) => AlertDialog(
      title: const Text('Contactar emergencias'),
      content: Text('¿Llamar a ${entidad.nombre} al ${entidad.telefono}?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogo, false), child: const Text('Cancelar')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: RBColores.rojo),
          onPressed: () => Navigator.pop(dialogo, true),
          icon: const Icon(Icons.call_rounded, size: 18),
          label: const Text('Llamar'),
        ),
      ],
    ),
  );
  return llamar == true;
}

/// Confirmación (en verde) antes de marcar el reporte como resuelto.
Future<bool> confirmarResuelto(BuildContext context) async {
  final respuesta = await showDialog<bool>(
    context: context,
    builder: (dialogo) => AlertDialog(
      title: const Text('Marcar como resuelto'),
      content: const Text(
        'El reporte dejará de mostrarse en el mapa. ¿Confirmas que el incidente está resuelto?',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogo, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: RBColores.verde),
          onPressed: () => Navigator.pop(dialogo, true),
          child: const Text('Sí, está resuelto'),
        ),
      ],
    ),
  );
  return respuesta == true;
}
