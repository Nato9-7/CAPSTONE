import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rb_alertas/config/api_config.dart';
import 'package:rb_alertas/servicios/reporte_servicio.dart' show EntidadEmergencia;

class PerfilServicioException implements Exception {
  final String mensaje;
  PerfilServicioException(this.mensaje);
}

class PerfilUsuario {
  final String nombres;
  final String apellidos;
  final String email;
  final String? urlFoto;
  final bool emailVerificado;
  final String? comuna;
  final String? region;
  final int totalReportes;
  final int totalResueltos;
  final List<EntidadEmergencia> emergencias;

  PerfilUsuario({
    required this.nombres,
    required this.apellidos,
    required this.email,
    required this.urlFoto,
    required this.emailVerificado,
    required this.comuna,
    required this.region,
    required this.totalReportes,
    required this.totalResueltos,
    required this.emergencias,
  });

  String get nombreCompleto => '$nombres $apellidos'.trim();

  String get lugar {
    final partes = [comuna, region].whereType<String>().where((p) => p.isNotEmpty);
    return partes.isEmpty ? 'Chile' : partes.join(', ');
  }

  factory PerfilUsuario.desdeJson(Map<String, dynamic> json) {
    return PerfilUsuario(
      nombres: (json['nombres'] ?? '').toString(),
      apellidos: (json['apellidos'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      urlFoto: json['url_foto_perfil']?.toString(),
      emailVerificado: json['email_verificado'] == true,
      comuna: json['comuna']?.toString(),
      region: json['region']?.toString(),
      totalReportes: (json['total_reportes'] as num?)?.toInt() ?? 0,
      totalResueltos: (json['total_resueltos'] as num?)?.toInt() ?? 0,
      emergencias: [
        for (final e in (json['emergencias'] as List? ?? []))
          EntidadEmergencia.desdeJson(e as Map<String, dynamic>),
      ],
    );
  }
}

class PerfilServicio {
  static const String baseUrl = ApiConfig.baseUrl;

  Future<PerfilUsuario> obtenerPerfil(String token) async {
    final respuesta = await http.get(
      Uri.parse('$baseUrl/api/usuarios/perfil'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (respuesta.statusCode == 200) {
      return PerfilUsuario.desdeJson(
        jsonDecode(utf8.decode(respuesta.bodyBytes)) as Map<String, dynamic>,
      );
    }
    throw PerfilServicioException(_mensaje(respuesta, 'No se pudo cargar tu perfil'));
  }

  /// Cierra la sesión en el servidor (revoca el token). No falla si ya venció.
  Future<void> cerrarSesion(String token) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/usuarios/logout'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      // aunque falle la llamada, la sesión se borra igual en la app
    }
  }

  String _mensaje(http.Response respuesta, String porDefecto) {
    try {
      final cuerpo = jsonDecode(utf8.decode(respuesta.bodyBytes));
      final detalle = cuerpo is Map ? cuerpo['detail'] : null;
      if (detalle is String) return detalle;
    } catch (_) {
      // se usa el mensaje por defecto
    }
    return porDefecto;
  }
}
