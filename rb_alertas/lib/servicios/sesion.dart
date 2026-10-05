import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:rb_alertas/servicios/auth_servicio.dart';

/// Datos del usuario que inició sesión.
///
/// [token] es el que entrega el login y se envía como `Authorization: Bearer`
/// en las rutas protegidas de la API. Además de quedar en memoria, se guarda
/// cifrado en el dispositivo (Keystore en Android) para que cerrar la app no
/// obligue a iniciar sesión de nuevo: la sesión del servidor dura 30 días.
class Sesion {
  static String? token;
  static Map<String, dynamic>? usuario;

  static const _almacen = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _claveToken = 'sesion_token';
  static const _claveUsuario = 'sesion_usuario';

  /// La cuenta admin solo usa el panel de administración (ver AdminVista).
  static bool get esAdmin => usuario?['es_admin'] == true;

  static Future<void> iniciar(LoginResultado resultado) async {
    token = resultado.token;
    usuario = resultado.usuario;
    try {
      await _almacen.write(key: _claveToken, value: resultado.token);
      await _almacen.write(
        key: _claveUsuario,
        value: jsonEncode(resultado.usuario),
      );
    } catch (_) {
      // Si el almacén falla, la sesión igual sirve mientras la app esté abierta.
    }
  }

  static Future<void> cerrar() async {
    token = null;
    usuario = null;
    try {
      await _almacen.delete(key: _claveToken);
      await _almacen.delete(key: _claveUsuario);
    } catch (_) {
      // Ya quedó limpio en memoria.
    }
  }

  /// Deja en memoria la sesión guardada en el dispositivo.
  /// Devuelve `false` si no había ninguna o si el almacén no se pudo leer.
  static Future<bool> restaurar() async {
    try {
      final guardado = await _almacen.read(key: _claveToken);
      if (guardado == null || guardado.isEmpty) return false;
      final datos = await _almacen.read(key: _claveUsuario);
      if (datos != null && datos.isNotEmpty) {
        usuario = jsonDecode(datos) as Map<String, dynamic>;
      }
      token = guardado;
      return true;
    } catch (_) {
      token = null;
      usuario = null;
      return false;
    }
  }
}
