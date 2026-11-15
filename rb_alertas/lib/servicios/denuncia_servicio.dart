import 'package:rb_alertas/modelos/denuncia.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';

/// Denuncias de los vecinos sobre reportes y comentarios.
class DenunciaServicio {
  Future<void> denunciarReporte({
    required int idReporte,
    required MotivoDenuncia motivo,
    String? detalle,
  }) => _enviar('/api/reportes/$idReporte/denuncias', motivo, detalle);

  /// Devuelve true si con esta denuncia el comentario quedó oculto.
  Future<bool> denunciarComentario({
    required int idReporte,
    required int idComentario,
    required MotivoDenuncia motivo,
    String? detalle,
  }) async {
    final cuerpo = await _enviar(
      '/api/reportes/$idReporte/comentarios/$idComentario/denuncias',
      motivo,
      detalle,
    );
    return cuerpo is Map && cuerpo['oculto'] == true;
  }

  Future<dynamic> _enviar(String ruta, MotivoDenuncia motivo, String? detalle) {
    return ApiCliente.post(
      ruta,
      cuerpo: {
        'motivo': motivo.api,
        if (detalle != null && detalle.trim().isNotEmpty) 'detalle': detalle.trim(),
      },
      error: 'No se pudo enviar la denuncia',
    );
  }
}
