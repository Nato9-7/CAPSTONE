import 'package:flutter/material.dart';
import 'package:rb_alertas/vistas/pantalla_bienvenida_vista.dart';

void main() {
  runApp(const RBAlertasApp());
}

class RBAlertasApp extends StatelessWidget {
  const RBAlertasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'RB Alertas',
      debugShowCheckedModeBanner: false,
      home: PantallaBienvenidaVista(),
    );
  }
}

