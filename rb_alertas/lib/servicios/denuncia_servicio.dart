import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rb_alertas/config/api_config.dart';

class DenunciaServicioException implements Exception {
  final String mensaje;
  DenunciaServicioException(this.mensaje);
}

/// Motivos para denunciar un reporte o un comentario (los mismos que acepta la API).
enum MotivoDenuncia {
  falso('FALSO', 'Es falso o engañoso'),
  ofensivo('OFENSIVO', 'Ofensivo o con insultos'),
  spam('SPAM', 'Spam o publicidad'),
  datosPersonales('DATOS_PERSONALES', 'Expone datos personales'),
  otro('OTRO', 'Otro motivo');

  final String api;
  final String texto;
  const MotivoDenuncia(this.api, this.texto);

  static String textoDe(String api) =>
      values.where((m) => m.api == api).firstOrNull?.texto ?? api;
}

class DenunciaServicio {
  static const String baseUrl = ApiConfig.baseUrl;

  Future<void> denunciarReporte({
    required String token,
    required int idReporte,
    required MotivoDenuncia motivo,
    String? detalle,
  }) {
    return _enviar(token, '/api/reportes/$idReporte/denuncias', motivo, detalle);
  }

  /// Devuelve true si con esta denuncia el comentario quedó oculto.
  Future<bool> denunciarComentario({
    required String token,
    required int idReporte,
    required int idComentario,
    required MotivoDenuncia motivo,
    String? detalle,
  }) async {
    final cuerpo = await _enviar(
      token,
      '/api/reportes/$idReporte/comentarios/$idComentario/denuncias',
      motivo,
      detalle,
    );
    return cuerpo['oculto'] == true;
  }

  Future<Map<String, dynamic>> _enviar(
    String token,
    String ruta,
    MotivoDenuncia motivo,
    String? detalle,
  ) async {
    final respuesta = await http.post(
      Uri.parse('$baseUrl$ruta'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'motivo': motivo.api,
        if (detalle != null && detalle.trim().isNotEmpty) 'detalle': detalle.trim(),
      }),
    );
    if (respuesta.statusCode == 201) {
      return jsonDecode(utf8.decode(respuesta.bodyBytes)) as Map<String, dynamic>;
    }
    throw DenunciaServicioException(_mensajeDeError(respuesta));
  }

  String _mensajeDeError(http.Response respuesta) {
    try {
      final cuerpo = jsonDecode(utf8.decode(respuesta.bodyBytes));
      final detalle = cuerpo is Map ? cuerpo['detail'] : null;
      if (detalle is String) return detalle;
    } catch (_) {
      // se usa el mensaje por defecto si el cuerpo no es JSON válido
    }
    return 'No se pudo enviar la denuncia';
  }
}
