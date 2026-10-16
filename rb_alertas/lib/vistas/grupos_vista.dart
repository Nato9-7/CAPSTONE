import 'package:flutter/material.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/barra_navegacion_inferior.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Pestaña Grupos. La funcionalidad todavía no existe: se muestra un aviso
/// de "próximamente" para reservar su lugar en la navegación.
class GruposVista extends StatelessWidget {
  const GruposVista({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RBColores.fondo,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
          children: [
            const TituloPantalla('Grupos'),
            const SizedBox(height: 28),
            TarjetaRB(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              child: Column(
                children: [
                  const AvatarSuricata(tamano: 112, borde: 5, sombra: true),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: RBColores.verde50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Próximamente',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: RBColores.verde,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Grupos vecinales',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: RBFuentes.titulos,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: RBColores.azul,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Muy pronto podrás coordinarte con los vecinos de tu '
                    'cuadra o de tu junta de vecinos desde aquí.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, height: 1.45, color: RBColores.texto2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const BarraNavegacionInferior(
        seccionActiva: SeccionApp.grupos,
      ),
    );
  }
}
