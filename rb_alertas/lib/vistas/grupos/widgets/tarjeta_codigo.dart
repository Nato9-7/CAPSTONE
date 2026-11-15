import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/grupo.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Código de invitación del grupo (solo lo ve el admin): su vigencia y los
/// botones para copiarlo, compartirlo o generar uno nuevo.
class TarjetaCodigo extends StatelessWidget {
  final Grupo grupo;

  /// Deshabilita los botones mientras hay una operación en curso.
  final bool trabajando;
  final VoidCallback onCopiar;
  final VoidCallback onCompartir;
  final VoidCallback onRegenerar;

  const TarjetaCodigo({
    super.key,
    required this.grupo,
    required this.trabajando,
    required this.onCopiar,
    required this.onCompartir,
    required this.onRegenerar,
  });

  String get _vigencia {
    final expira = grupo.codigoExpira;
    if (grupo.codigoVencido || expira == null) return 'Venció: genera uno nuevo para invitar';
    final dias = expira.difference(DateTime.now()).inDays;
    return dias < 1 ? 'Vence hoy' : (dias == 1 ? 'Vence mañana' : 'Vence en $dias días');
  }

  @override
  Widget build(BuildContext context) {
    final vencido = grupo.codigoVencido;
    final forma = RoundedRectangleBorder(borderRadius: BorderRadius.circular(RBRadios.boton));
    return TarjetaRB(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('CÓDIGO DE INVITACIÓN', style: RBTexto.etiqueta),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    grupo.codigo!,
                    style: TextStyle(
                      fontFamily: RBFuentes.titulos,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                      color: vencido ? RBColores.texto2 : RBColores.azul,
                      decoration: vencido ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              ),
              if (!vencido)
                IconButton(
                  tooltip: 'Copiar código',
                  onPressed: onCopiar,
                  icon: const Icon(Icons.copy_rounded, color: RBColores.azul),
                ),
            ],
          ),
          Text(
            _vigencia,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: vencido ? RBColores.rojo : RBColores.texto2,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: vencido || trabajando ? null : onCompartir,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: RBColores.verde,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: forma,
                    ),
                    icon: const Icon(Icons.share_rounded, size: 20),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Invitar vecinos', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: trabajando ? null : onRegenerar,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: RBColores.azul,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: forma,
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Código nuevo', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
