import 'package:flutter/material.dart';
import 'package:rb_alertas/vistas/mapa_vista.dart';
import 'package:rb_alertas/widgets/app_logo.dart';

class PantallaBienvenidaVista extends StatefulWidget {
  const PantallaBienvenidaVista({super.key});

  @override
  State<PantallaBienvenidaVista> createState() =>
      _PantallaBienvenidaVistaState();
}

class _PantallaBienvenidaVistaState extends State<PantallaBienvenidaVista> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MapaVista()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double logoSize = size.width * 0.5;
    final double fontDesc = size.width * 0.5 * 0.1;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(size: logoSize),
            SizedBox(height: size.height * 0.04),
            Text(
              'Alpha v6.7',
              style: TextStyle(
                fontSize: fontDesc,
                color: const Color(0xFF9CA3AF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
