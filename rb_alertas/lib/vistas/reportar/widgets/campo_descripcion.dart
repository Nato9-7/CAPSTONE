import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rb_alertas/tema/rb_tema.dart';

/// Descripción del incidente con su contador. Es un FormField propio para que
/// el contador quede dentro de la caja, abajo a la derecha, y el error de
/// validación aparezca debajo.
class CampoDescripcion extends StatelessWidget {
  final TextEditingController controller;
  final int maximo;

  const CampoDescripcion({super.key, required this.controller, required this.maximo});

  String? _validar(String? _) {
    final valor = controller.text;
    if (valor.trim().isEmpty) return 'Describe brevemente lo que sucedió';
    // La API cuenta puntos de código: un emoji puede valer 2 o más.
    if (valor.trim().runes.length > maximo) {
      return 'La descripción no puede superar los $maximo caracteres';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      validator: _validar,
      builder: (estado) {
        final usados = controller.text.trim().runes.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(RBRadios.tarjeta + 4),
                border: Border.all(
                  color: estado.hasError ? RBColores.rojo : RBColores.bordeCampo,
                  width: 1.2,
                ),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: controller,
                    minLines: 3,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: [LengthLimitingTextInputFormatter(maximo)],
                    onChanged: estado.didChange,
                    style: const TextStyle(fontSize: 16, color: RBColores.tinta),
                    decoration: const InputDecoration(
                      hintText: 'Describe brevemente lo que sucedió...',
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$usados/$maximo',
                      style: const TextStyle(fontSize: 14, color: RBColores.texto2),
                    ),
                  ),
                ],
              ),
            ),
            if (estado.hasError)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                child: Text(estado.errorText!, style: const TextStyle(fontSize: 12.5, color: RBColores.rojo)),
              ),
          ],
        );
      },
    );
  }
}
