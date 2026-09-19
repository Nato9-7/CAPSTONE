import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:rb_alertas/vistas/pantalla_bienvenida_vista.dart';

void main() {
  runApp(const RBAlertasApp());
}

class RBAlertasApp extends StatelessWidget {
  const RBAlertasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RB Alertas',
      debugShowCheckedModeBanner: false,
      // En web, Flutter no deja arrastrar las listas horizontales con el
      // mouse (p. ej. los filtros del mapa); así se pueden deslizar igual
      // que con el dedo.
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: PointerDeviceKind.values.toSet(),
      ),
      home: const PantallaBienvenidaVista(),
    );
  }
}

