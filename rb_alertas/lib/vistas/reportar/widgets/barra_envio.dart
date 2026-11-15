import 'package:flutter/material.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Suricata con el aviso de a quién le llegará el reporte.
class MensajeSuricata extends StatelessWidget {
  final bool soloGrupo;

  const MensajeSuricata({super.key, required this.soloGrupo});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AvatarSuricata(tamano: context.escala(56)),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: RBColores.verde50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              soloGrupo
                  ? 'Se avisará solo a los vecinos de tu grupo. '
                      '¡Gracias por cuidar tu barrio!'
                  : 'Se avisará a los vecinos que estén cerca del lugar. '
                      '¡Gracias por cuidar tu barrio!',
              style: const TextStyle(
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: RBColores.verde,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Barra fija inferior: adjuntar foto o video y enviar el reporte. En
/// pantallas bajas solo lleva los botones, para dejar más espacio al formulario.
class BarraEnvio extends StatelessWidget {
  final bool enviando;
  final bool soloGrupo;
  final VoidCallback onTomarFoto;
  final VoidCallback onElegirArchivo;
  final VoidCallback onEnviar;

  const BarraEnvio({
    super.key,
    required this.enviando,
    required this.soloGrupo,
    required this.onTomarFoto,
    required this.onElegirArchivo,
    required this.onEnviar,
  });

  @override
  Widget build(BuildContext context) {
    final baja = context.pantallaBaja;
    final alto = baja || context.pantallaAngosta ? 52.0 : 60.0;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        baja ? 10 : 14,
        16,
        (baja ? 10 : 14) + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: RBColores.linea)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!baja) ...[MensajeSuricata(soloGrupo: soloGrupo), const SizedBox(height: 12)],
          Row(
            children: [
              _botonAdjuntar(
                icono: Icons.photo_camera_outlined,
                tooltip: 'Tomar foto',
                tamano: alto,
                onTap: onTomarFoto,
              ),
              const SizedBox(width: 10),
              _botonAdjuntar(
                icono: Icons.image_outlined,
                tooltip: 'Elegir foto o video',
                tamano: alto,
                onTap: onElegirArchivo,
              ),
              const SizedBox(width: 12),
              Expanded(child: SizedBox(height: alto, child: _botonEnviar())),
            ],
          ),
        ],
      ),
    );
  }

  Widget _botonEnviar() {
    return ElevatedButton.icon(
      onPressed: enviando ? null : onEnviar,
      style: ElevatedButton.styleFrom(
        backgroundColor: RBColores.verde,
        foregroundColor: Colors.white,
        disabledBackgroundColor: RBColores.verde.withValues(alpha: 0.6),
        disabledForegroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RBRadios.tarjeta)),
        textStyle: const TextStyle(
          fontFamily: RBFuentes.interfaz,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      icon: enviando
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
            )
          : const Icon(Icons.near_me_outlined, size: 22),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(enviando ? 'Enviando…' : 'Enviar reporte'),
      ),
    );
  }

  Widget _botonAdjuntar({
    required IconData icono,
    required String tooltip,
    required double tamano,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(RBRadios.tarjeta),
        child: InkWell(
          onTap: enviando ? null : onTap,
          borderRadius: BorderRadius.circular(RBRadios.tarjeta),
          child: Container(
            width: tamano,
            height: tamano,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(RBRadios.tarjeta),
              border: Border.all(color: RBColores.bordeCampo, width: 1.2),
            ),
            child: Icon(icono, color: RBColores.azul, size: 26),
          ),
        ),
      ),
    );
  }
}
