import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rb_alertas/config/api_config.dart';
import 'package:rb_alertas/servicios/reporte_servicio.dart';

class ComentarioServicioException implements Exception {
  final String mensaje;
  ComentarioServicioException(this.mensaje);
}

/// Comentario de un reporte (tabla comentario). Los raíz traen sus respuestas.
class Comentario {
  final int id;
  final int? idPadre;
  // PUBLICADO, o ELIMINADO/OCULTO si solo queda el marcador del hilo.
  final String estado;
  // Alias de suricata (lo arma la API); null en un marcador.
  final String? autor;
  final bool esAutorReporte;
  final bool esMio;
  final String? contenido;
  final String? imagen;
  final DateTime? fechaCreacion;
  final List<Comentario> respuestas;

  Comentario({
    required this.id,
    required this.idPadre,
    required this.estado,
    required this.autor,
    required this.esAutorReporte,
    required this.esMio,
    required this.contenido,
    required this.imagen,
    required this.fechaCreacion,
    required this.respuestas,
  });

  bool get publicado => estado == 'PUBLICADO';

  /// URL completa de la foto adjunta, o null si no trae.
  String? get imagenUrl =>
      imagen == null || imagen!.isEmpty ? null : ApiConfig.urlArchivo(imagen!);

  factory Comentario.desdeJson(Map<String, dynamic> json) {
    return Comentario(
      id: (json['id_comentario'] as num).toInt(),
      idPadre: (json['id_comentario_padre'] as num?)?.toInt(),
      estado: (json['estado'] ?? '').toString(),
      autor: json['autor']?.toString(),
      esAutorReporte: json['es_autor_reporte'] == true,
      esMio: json['es_mio'] == true,
      contenido: json['contenido']?.toString(),
      imagen: json['imagen']?.toString(),
      fechaCreacion: DateTime.tryParse((json['fecha_creacion'] ?? '').toString()),
      respuestas: [
        for (final r in (json['respuestas'] as List? ?? []))
          Comentario.desdeJson(r as Map<String, dynamic>),
      ],
    );
  }
}

/// Respuesta de GET /api/reportes/{id}/comentarios.
class ConversacionReporte {
  // Comentarios visibles (raíz y respuestas), sin contar los marcadores.
  final int total;
  // false si el reporte ya no está vigente: la conversación queda de solo lectura.
  final bool puedeComentar;
  final List<Comentario> comentarios;

  ConversacionReporte({
    required this.total,
    required this.puedeComentar,
    required this.comentarios,
  });

  factory ConversacionReporte.desdeJson(Map<String, dynamic> json) {
    return ConversacionReporte(
      total: (json['total'] as num?)?.toInt() ?? 0,
      puedeComentar: json['puede_comentar'] == true,
      comentarios: [
        for (final c in (json['comentarios'] as List? ?? []))
          Comentario.desdeJson(c as Map<String, dynamic>),
      ],
    );
  }
}

class ComentarioServicio {
  static const String baseUrl = ApiConfig.baseUrl;

  /// Con [token], la API marca cuáles comentarios son de quien consulta.
  Future<ConversacionReporte> obtenerComentarios(int idReporte, {String? token}) async {
    final respuesta = await http.get(
      Uri.parse('$baseUrl/api/reportes/$idReporte/comentarios'),
      headers: {
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );
    if (respuesta.statusCode == 200) {
      return ConversacionReporte.desdeJson(
        jsonDecode(utf8.decode(respuesta.bodyBytes)) as Map<String, dynamic>,
      );
    }
    throw ComentarioServicioException(
      _mensajeDeError(respuesta, 'No se pudieron cargar los comentarios'),
    );
  }

  /// Publica un comentario, o una respuesta si viene [idPadre]. Lleva texto, foto o ambos.
  Future<void> comentar({
    required String token,
    required int idReporte,
    required String contenido,
    int? idPadre,
    Evidencia? foto,
  }) async {
    final solicitud = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/reportes/$idReporte/comentarios'),
    );
    solicitud.headers['Authorization'] = 'Bearer $token';
    solicitud.fields.addAll({
      'contenido': contenido,
      if (idPadre != null) 'id_comentario_padre': idPadre.toString(),
    });
    if (foto != null) {
      solicitud.files.add(
        http.MultipartFile.fromBytes('foto', foto.bytes, filename: foto.nombreArchivo),
      );
    }

    final respuesta = await http.Response.fromStream(await solicitud.send());
    if (respuesta.statusCode == 201) return;
    throw ComentarioServicioException(
      _mensajeDeError(respuesta, 'No se pudo publicar tu comentario'),
    );
  }

  /// Elimina un comentario propio.
  Future<void> eliminar({
    required String token,
    required int idReporte,
    required int idComentario,
  }) async {
    final respuesta = await http.delete(
      Uri.parse('$baseUrl/api/reportes/$idReporte/comentarios/$idComentario'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (respuesta.statusCode == 204) return;
    throw ComentarioServicioException(
      _mensajeDeError(respuesta, 'No se pudo eliminar el comentario'),
    );
  }

  String _mensajeDeError(http.Response respuesta, String porDefecto) {
    try {
      final cuerpo = jsonDecode(utf8.decode(respuesta.bodyBytes));
      final detalle = cuerpo is Map ? cuerpo['detail'] : null;
      if (detalle is String) return detalle;
    } catch (_) {
      // se usa el mensaje por defecto si el cuerpo no es JSON válido
    }
    return porDefecto;
  }
}
