import 'package:rb_alertas/modelos/comentario.dart';
import 'package:rb_alertas/modelos/reporte.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';

/// Conversación de un reporte.
class ComentarioServicio {
  /// Con sesión, la API marca cuáles comentarios son de quien consulta.
  Future<ConversacionReporte> obtenerComentarios(int idReporte) async {
    final cuerpo = await ApiCliente.get(
      '/api/reportes/$idReporte/comentarios',
      error: 'No se pudieron cargar los comentarios',
    );
    return ConversacionReporte.desdeJson(cuerpo as Map<String, dynamic>);
  }

  /// Publica un comentario, o una respuesta si viene [idPadre]. Lleva texto, foto o ambos.
  Future<void> comentar({
    required int idReporte,
    required String contenido,
    int? idPadre,
    Evidencia? foto,
  }) async {
    await ApiCliente.multipart(
      '/api/reportes/$idReporte/comentarios',
      campos: {
        'contenido': contenido,
        if (idPadre != null) 'id_comentario_padre': idPadre.toString(),
      },
      archivos: [
        if (foto != null) (campo: 'foto', nombre: foto.nombreArchivo, bytes: foto.bytes),
      ],
      error: 'No se pudo publicar tu comentario',
    );
  }

  /// Elimina un comentario propio.
  Future<void> eliminar({required int idReporte, required int idComentario}) async {
    await ApiCliente.delete(
      '/api/reportes/$idReporte/comentarios/$idComentario',
      error: 'No se pudo eliminar el comentario',
    );
  }
}
