import 'package:flutter/material.dart';
import 'package:rb_alertas/servicios/auth_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
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
    _arrancar();
  }

  /// Mientras se muestra el logo se recupera la sesión guardada, así el
  /// usuario entra directo sin volver a escribir su correo y contraseña.
  Future<void> _arrancar() async {
    final espera = Future.delayed(const Duration(seconds: 5));
    await _recuperarSesion();
    await espera;
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MapaVista()),
    );
  }

  Future<void> _recuperarSesion() async {
    if (!await Sesion.restaurar()) return;
    final vigente = await AuthServicio().sesionVigente(Sesion.token!);
    // Solo se descarta cuando la API confirma que el token ya no sirve.
    // Si no hubo respuesta (sin conexión), se conserva y se reintenta al usarla.
    if (vigente == false) await Sesion.cerrar();
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
