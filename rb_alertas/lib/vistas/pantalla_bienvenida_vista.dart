import 'package:flutter/material.dart';
import 'package:rb_alertas/config/app_info.dart';
import 'package:rb_alertas/servicios/auth_servicio.dart';
import 'package:rb_alertas/servicios/push_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/alertas_vista.dart';
import 'package:rb_alertas/vistas/mapa_vista.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

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
    final abiertaDesdeAviso = await PushServicio.inicializar();
    await _recuperarSesion();
    // Sin await: el permiso de notificaciones no debe atrasar la entrada.
    PushServicio.registrar();
    await espera;
    if (!mounted) return;
    // Si se abrió tocando un aviso, entra directo a lo que avisa: un aviso de
    // comentario o de grupo abre su reporte sobre el mapa; uno de zona segura, Alertas.
    final desdeAviso =
        abiertaDesdeAviso && Sesion.token != null && !Sesion.esAdmin;
    final idReporte = desdeAviso
        ? PushServicio.reporteDeAviso(PushServicio.avisoInicial)
        : null;
    final irAAlertas = desdeAviso && idReporte == null;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) =>
            irAAlertas ? const AlertasVista() : const MapaVista(),
      ),
    );
    if (idReporte != null) {
      PushServicio.abrirReporte(
        idReporte,
        irAComentarios: PushServicio.esAvisoDeComentario(PushServicio.avisoInicial),
      );
    }
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
    final double logoSize = (size.width * 0.45).clamp(140, 220);

    return Scaffold(
      backgroundColor: RBColores.azul,
      body: Stack(
        children: [
          Positioned(
            bottom: -170,
            left: -120,
            child: Container(
              width: 380,
              height: 380,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: RBColores.petroleo,
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AvatarSuricata(tamano: logoSize, borde: 7, sombra: true),
                const SizedBox(height: 28),
                const MarcaRB(tamano: 46, colorRB: Colors.white),
                const SizedBox(height: 8),
                Text(
                  'Alertas vecinales de Puerto Montt',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 24 + MediaQuery.of(context).padding.bottom,
            child: Text(
              AppInfo.version,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
