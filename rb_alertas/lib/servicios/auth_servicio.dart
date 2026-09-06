import 'dart:convert';

import 'package:http/http.dart' as http;

class AuthServicioException implements Exception {
  final String mensaje;
  AuthServicioException(this.mensaje);
}

class LoginResultado {
  final String token;
  final Map<String, dynamic> usuario;

  LoginResultado({required this.token, required this.usuario});
}

class AuthServicio {
  static const String baseUrl = 'http://localhost:3000';

  // NOTA: ajusta esta ruta si tu backend expone el login en otro path
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
      final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
      return LoginResultado(
        token: (cuerpo['token'] ?? cuerpo['access_token'] ?? '').toString(),
        usuario:
            (cuerpo['usuario'] ?? cuerpo['user'] ?? {}) as Map<String, dynamic>,
      );
    }

    String mensaje = 'Correo o contraseña incorrectos';
    try {
      final cuerpo = jsonDecode(respuesta.body);
      if (cuerpo is Map && cuerpo['detail'] != null) {
        mensaje = cuerpo['detail'].toString();
      }
    } catch (_) {
      // se usa el mensaje por defecto si el cuerpo no es JSON válido
    }
    throw AuthServicioException(mensaje);
  }

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

    String mensaje = 'No se pudo completar el registro';
    try {
      final cuerpo = jsonDecode(respuesta.body);
      if (cuerpo is Map && cuerpo['detail'] != null) {
        mensaje = cuerpo['detail'].toString();
      }
    } catch (_) {
      // se usa el mensaje por defecto si el cuerpo no es JSON válido
    }
    throw AuthServicioException(mensaje);
  }
}
