import 'package:flutter/material.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Marco de las pantallas de acceso (iniciar sesión, registro, recuperar
/// contraseña): fondo azul marino con círculos decorativos, tarjeta blanca con
/// la suricata asomada arriba y un enlace bajo la tarjeta.
class FondoAcceso extends StatelessWidget {
  final Widget tarjeta;
  final Widget? pie;
  final double tamanoSuricata;

  const FondoAcceso({
    super.key,
    required this.tarjeta,
    this.pie,
    this.tamanoSuricata = 150,
  });

  @override
  Widget build(BuildContext context) {
    final puedeVolver = Navigator.of(context).canPop();
    // En pantallas chicas la suricata se achica para que el formulario quepa.
    final suricata = context.escala(tamanoSuricata) * (context.pantallaBaja ? 0.72 : 1);
    final mitad = suricata / 2;
    final margenTarjeta = context.pantallaAngosta ? 18.0 : 22.0;

    return Scaffold(
      backgroundColor: RBColores.azul,
      body: Stack(
        children: [
          // Anillo claro arriba a la derecha y círculo petróleo abajo a la izquierda.
          Positioned(
            top: -90,
            right: -150,
            child: Container(
              width: 420,
              height: 420,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                  width: 40,
                ),
              ),
            ),
          ),
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
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, context.pantallaBaja ? 12 : 24, 16, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.topCenter,
                        children: [
                          Container(
                            margin: EdgeInsets.only(top: mitad + 4),
                            padding: EdgeInsets.fromLTRB(
                              margenTarjeta,
                              mitad + 12,
                              margenTarjeta,
                              context.pantallaBaja ? 18 : 24,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(RBRadios.hoja),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 30,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: tarjeta,
                          ),
                          AvatarSuricata(tamano: suricata, borde: suricata > 110 ? 6 : 4, sombra: true),
                        ],
                      ),
                      if (pie != null) ...[
                        SizedBox(height: context.pantallaBaja ? 16 : 24),
                        pie!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (puedeVolver)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  tooltip: 'Volver',
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.maybePop(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Texto blanco con un enlace subrayado: "¿No tienes cuenta? Regístrate".
class EnlaceAcceso extends StatelessWidget {
  final String texto;
  final String enlace;
  final VoidCallback onTap;

  const EnlaceAcceso({
    super.key,
    required this.texto,
    required this.enlace,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '$texto ',
          style: TextStyle(fontSize: 17, color: Colors.white.withValues(alpha: 0.85)),
        ),
        InkWell(
          onTap: onTap,
          child: Text(
            enlace,
            style: const TextStyle(
              fontSize: 17,
              color: Colors.white,
              fontWeight: FontWeight.w800,
              decoration: TextDecoration.underline,
              decorationColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

/// Campo de formulario con su rótulo arriba, como en el diseño.
class CampoRotulado extends StatelessWidget {
  final String rotulo;
  final Widget campo;

  const CampoRotulado({super.key, required this.rotulo, required this.campo});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(rotulo, style: RBTexto.rotuloCampo),
        const SizedBox(height: 8),
        campo,
      ],
    );
  }
}

/// Botón principal azul marino de ancho completo, con indicador de carga.
class BotonPrincipal extends StatelessWidget {
  final String texto;
  final VoidCallback? onPressed;
  final bool cargando;
  final Color color;
  final IconData? icono;
  final double alto;

  const BotonPrincipal({
    super.key,
    required this.texto,
    required this.onPressed,
    this.cargando = false,
    this.color = RBColores.azul,
    this.icono,
    this.alto = 56,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: alto,
      child: ElevatedButton(
        onPressed: cargando ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withValues(alpha: 0.6),
          disabledForegroundColor: Colors.white,
          textStyle: const TextStyle(
            fontFamily: RBFuentes.interfaz,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: cargando
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icono != null) ...[
                    Icon(icono, size: 22),
                    const SizedBox(width: 10),
                  ],
                  Flexible(child: Text(texto, overflow: TextOverflow.ellipsis)),
                ],
              ),
      ),
    );
  }
}
