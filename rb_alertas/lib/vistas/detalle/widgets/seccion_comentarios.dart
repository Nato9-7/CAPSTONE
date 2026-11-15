import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/comentario.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/comentarios.dart';

/// Conversación del reporte: título con el total, comentarios con sus
/// respuestas anidadas y, si no se puede escribir, el motivo.
class SeccionComentarios extends StatelessWidget {
  /// null mientras carga o si falló la carga.
  final ConversacionReporte? conversacion;
  final String? error;
  final VoidCallback onReintentar;

  /// true si quien mira puede escribir (lo decide la vista).
  final bool puedeResponder;

  /// Bloquea "Responder" mientras se publica otro comentario.
  final bool publicando;
  final void Function(Comentario) onResponder;
  final void Function(Comentario) onEliminar;
  final void Function(Comentario) onDenunciar;

  const SeccionComentarios({
    super.key,
    required this.conversacion,
    required this.error,
    required this.onReintentar,
    required this.puedeResponder,
    required this.publicando,
    required this.onResponder,
    required this.onEliminar,
    required this.onDenunciar,
  });

  @override
  Widget build(BuildContext context) {
    final conversacion = this.conversacion;

    // Por qué no aparece la barra para escribir.
    final aviso = conversacion == null || puedeResponder || Sesion.esAdmin
        ? null
        : !conversacion.puedeComentar
            ? 'Este reporte ya no está vigente: la conversación quedó cerrada.'
            : 'Inicia sesión para comentar.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.chat_bubble_outline_rounded, size: 24, color: RBColores.azul),
            const SizedBox(width: 10),
            Text(
              'Comentarios',
              style: TextStyle(
                fontFamily: RBFuentes.titulos,
                fontSize: context.escala(24),
                fontWeight: FontWeight.w800,
                color: RBColores.azul,
              ),
            ),
            if (conversacion != null && conversacion.total > 0) ...[
              const SizedBox(width: 8),
              Text('${conversacion.total}', style: const TextStyle(fontSize: 16, color: RBColores.texto2)),
            ],
          ],
        ),
        const SizedBox(height: 16),
        _contenido(context),
        if (aviso != null) ...[
          const SizedBox(height: 4),
          Text(aviso, style: const TextStyle(fontSize: 13.5, color: RBColores.texto2)),
        ],
      ],
    );
  }

  Widget _contenido(BuildContext context) {
    final conversacion = this.conversacion;
    if (conversacion == null) {
      if (error == null) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(error!, style: const TextStyle(fontSize: 15, color: RBColores.texto2)),
          TextButton(onPressed: onReintentar, child: const Text('Reintentar')),
        ],
      );
    }
    if (conversacion.comentarios.isEmpty) {
      return Text(
        puedeResponder
            ? 'Aún no hay comentarios. Si sabes algo más del incidente, cuéntale a tus vecinos.'
            : 'Aún no hay comentarios.',
        style: const TextStyle(fontSize: 15, height: 1.4, color: RBColores.texto2),
      );
    }
    return Column(
      children: [
        for (final c in conversacion.comentarios) ...[
          _tarjeta(context, c),
          for (final r in c.respuestas)
            Padding(
              // Bajo el avatar del comentario raíz; menos sangría en pantallas angostas.
              padding: EdgeInsets.only(left: context.pantallaAngosta ? 30 : 48, top: 10),
              child: _tarjeta(context, r, respuesta: true),
            ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _tarjeta(BuildContext context, Comentario c, {bool respuesta = false}) {
    return TarjetaComentario(
      comentario: c,
      respuesta: respuesta,
      onResponder: puedeResponder && c.publicado && !publicando ? () => onResponder(c) : null,
      onEliminar: c.esMio ? () => onEliminar(c) : null,
      onDenunciar: c.esMio || Sesion.esAdmin ? null : () => onDenunciar(c),
      onVerFoto: (url) => verFotoComentario(context, url),
    );
  }
}
