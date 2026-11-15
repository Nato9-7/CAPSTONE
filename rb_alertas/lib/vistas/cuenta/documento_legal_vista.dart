import 'package:flutter/material.dart';
import 'package:rb_alertas/config/documentos_legales.dart';
import 'package:rb_alertas/tema/rb_tema.dart';

/// Muestra los Términos de uso o la Política de privacidad. Se abre desde el
/// registro (antes de aceptarlos) y desde el perfil.
class DocumentoLegalVista extends StatelessWidget {
  final DocumentoLegal documento;

  const DocumentoLegalVista({super.key, required this.documento});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RBColores.fondo,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 20, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Volver',
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_back_rounded, size: 30, color: RBColores.tinta),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(documento.titulo, style: RBTexto.display),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                children: [
                  const Text(
                    'Versión ${DocumentosLegales.version} · vigente desde el ${DocumentosLegales.vigenteDesde}',
                    style: TextStyle(fontSize: 13, color: RBColores.texto2),
                  ),
                  for (final seccion in documento.secciones) ...[
                    const SizedBox(height: 22),
                    Text(seccion.titulo, style: RBTexto.titulo.copyWith(fontSize: 17)),
                    for (final parrafo in seccion.parrafos) ...[
                      const SizedBox(height: 8),
                      Text(parrafo, style: RBTexto.cuerpo),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
