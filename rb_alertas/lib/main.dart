import 'package:flutter/material.dart';

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
      home: Scaffold(
        body: SizedBox(),
      ),
    );
  }
}
