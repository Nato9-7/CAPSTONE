import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rb_alertas/config/api_config.dart';

class AuthServicioException implements Exception {
  final String mensaje;
  // Código que manda la API para errores que la app trata distinto
  // (por ejemplo AuthServicio.codigoEmailNoVerificado).
  final String? codigo;

  AuthServicioException(this.mensaje, {this.codigo});
}

class LoginResultado {
  final String token;
  final Map<String, dynamic> usuario;

  LoginResultado({required this.token, required this.usuario});
}

class AuthServicio {
  static const String baseUrl = ApiConfig.baseUrl;
  static const String codigoEmailNoVerificado = 'EMAIL_NO_VERIFICADO';

  Future<LoginResultado> login({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/api/usuarios/login');

    final respuesta = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (respuesta.statusCode == 200) {
      final cuerpo = _json(respuesta) as Map<String, dynamic>;
      return LoginResultado(
        token: (cuerpo['token'] ?? cuerpo['access_token'] ?? '').toString(),
        usuario:
            (cuerpo['usuario'] ?? cuerpo['user'] ?? {}) as Map<String, dynamic>,
      );
    }

    throw _error(respuesta, 'Correo o contraseña incorrectos');
  }

  /// Crea la cuenta; la API envía un correo con el enlace para verificarla.
  Future<void> registrar({
    required String nombres,
    required String apellidos,
    required String rut,
    required String email,
    required String telefono,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/api/usuarios/registro');

    final respuesta = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'nombres': nombres,
        'apellidos': apellidos,
        'rut': rut,
        'email': email,
        'telefono': telefono,
        'password': password,
      }),
    );

    if (respuesta.statusCode == 201) {
      return;
    }

    throw _error(respuesta, 'No se pudo completar el registro');
  }

  /// Pide un nuevo correo de verificación. Devuelve el mensaje para mostrar.
  Future<String> reenviarVerificacion(String email) async {
    final respuesta = await http.post(
      Uri.parse('$baseUrl/api/usuarios/reenviar-verificacion'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );

    if (respuesta.statusCode == 202) {
      final cuerpo = _json(respuesta);
      return (cuerpo is Map ? cuerpo['detail'] : null)?.toString() ??
          'Te enviamos un nuevo enlace a tu correo.';
    }
    throw _error(respuesta, 'No se pudo reenviar el correo');
  }

  // La API responde JSON sin charset; se decodifica como UTF-8 para que
  // las tildes y la ñ se vean bien.
  dynamic _json(http.Response respuesta) =>
      jsonDecode(utf8.decode(respuesta.bodyBytes));

  AuthServicioException _error(http.Response respuesta, String porDefecto) {
    try {
      final cuerpo = _json(respuesta);
      final detalle = cuerpo is Map ? cuerpo['detail'] : null;
      if (detalle is String) return AuthServicioException(detalle);
      if (detalle is Map && detalle['mensaje'] != null) {
        return AuthServicioException(
          detalle['mensaje'].toString(),
          codigo: detalle['codigo']?.toString(),
        );
      }
    } catch (_) {
      // se usa el mensaje por defecto si el cuerpo no es JSON válido
    }
    return AuthServicioException(porDefecto);
  }
}
