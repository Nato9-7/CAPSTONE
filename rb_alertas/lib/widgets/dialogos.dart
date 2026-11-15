import 'package:flutter/material.dart';
import 'package:rb_alertas/tema/rb_tema.dart';

/// Muestra un aviso breve abajo, reemplazando el que hubiera.
void mostrarAviso(
  BuildContext context,
  String mensaje, {
  SnackBarAction? accion,
  Duration duracion = const Duration(seconds: 4),
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(mensaje), action: accion, duration: duracion));
}

/// Diálogo "Cancelar / [accion]". Devuelve true solo si se confirmó.
/// Con [peligro] el botón va en rojo (acciones destructivas); si no, en azul.
/// [color] fija otro color, p. ej. verde para reactivar o resolver.
Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String accion = 'Confirmar',
  bool peligro = true,
  Color? color,
}) async {
  final respuesta = await showDialog<bool>(
    context: context,
    builder: (dialogo) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje, style: const TextStyle(height: 1.4)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogo, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: color ?? (peligro ? RBColores.rojo : RBColores.azul)),
          onPressed: () => Navigator.pop(dialogo, true),
          child: Text(accion),
        ),
      ],
    ),
  );
  return respuesta == true;
}
