import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:rb_alertas/config/documentos_legales.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/cuenta/documento_legal_vista.dart';

/// Casilla obligatoria del registro para aceptar los Términos de uso y la
/// Política de privacidad (incluido el uso de la ubicación). Los nombres de
/// los documentos abren su texto completo.
class CasillaTerminos extends StatefulWidget {
  const CasillaTerminos({super.key});

  @override
  State<CasillaTerminos> createState() => _CasillaTerminosState();
}

class _CasillaTerminosState extends State<CasillaTerminos> {
  late final _abrirTerminos = TapGestureRecognizer()..onTap = () => _abrir(DocumentoLegal.terminos);
  late final _abrirPrivacidad = TapGestureRecognizer()..onTap = () => _abrir(DocumentoLegal.privacidad);

  @override
  void dispose() {
    _abrirTerminos.dispose();
    _abrirPrivacidad.dispose();
    super.dispose();
  }

  void _abrir(DocumentoLegal documento) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DocumentoLegalVista(documento: documento)),
    );
  }

  @override
  Widget build(BuildContext context) {
    const enlace = TextStyle(
      color: RBColores.azul,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
    );
    return FormField<bool>(
      initialValue: false,
      validator: (aceptado) =>
          aceptado == true ? null : 'Debes aceptar los términos para crear tu cuenta',
      builder: (campo) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: campo.value ?? false,
                activeColor: RBColores.azul,
                onChanged: campo.didChange,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 13.5, height: 1.4, color: RBColores.tinta),
                      children: [
                        const TextSpan(text: 'Acepto los '),
                        TextSpan(text: 'Términos de uso', style: enlace, recognizer: _abrirTerminos),
                        const TextSpan(text: ' y la '),
                        TextSpan(text: 'Política de privacidad', style: enlace, recognizer: _abrirPrivacidad),
                        const TextSpan(text: ', incluido el uso de mi ubicación.'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (campo.hasError)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                campo.errorText!,
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
