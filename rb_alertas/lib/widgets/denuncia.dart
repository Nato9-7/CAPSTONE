import 'package:flutter/material.dart';
import 'package:rb_alertas/servicios/denuncia_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';

/// Pide el motivo (y un detalle opcional) para denunciar un reporte o un
/// comentario. Devuelve null si se cancela.
Future<(MotivoDenuncia, String)?> pedirDenuncia(
  BuildContext context, {
  required bool esComentario,
}) {
  return showDialog<(MotivoDenuncia, String)>(
    context: context,
    builder: (_) => _DialogoDenuncia(esComentario: esComentario),
  );
}

class _DialogoDenuncia extends StatefulWidget {
  final bool esComentario;

  const _DialogoDenuncia({required this.esComentario});

  @override
  State<_DialogoDenuncia> createState() => _DialogoDenunciaState();
}

class _DialogoDenunciaState extends State<_DialogoDenuncia> {
  final _detalle = TextEditingController();
  MotivoDenuncia? _motivo;

  @override
  void dispose() {
    _detalle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final que = widget.esComentario ? 'comentario' : 'reporte';
    return AlertDialog(
      title: Text('Denunciar $que'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lo revisará el equipo de RB Alertas. Quien lo publicó no sabrá que fuiste tú.',
              style: const TextStyle(fontSize: 14, height: 1.4, color: RBColores.texto2),
            ),
            const SizedBox(height: 8),
            RadioGroup<MotivoDenuncia>(
              groupValue: _motivo,
              onChanged: (m) => setState(() => _motivo = m),
              child: Column(
                children: [
                  for (final m in MotivoDenuncia.values)
                    RadioListTile<MotivoDenuncia>(
                      value: m,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(m.texto, style: const TextStyle(fontSize: 15)),
                    ),
                ],
              ),
            ),
            TextField(
              controller: _detalle,
              maxLength: 300,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Cuéntanos más (opcional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: RBColores.rojo),
          onPressed: _motivo == null
              ? null
              : () => Navigator.pop(context, (_motivo!, _detalle.text)),
          child: const Text('Denunciar'),
        ),
      ],
    );
  }
}
