import 'package:rb_alertas/servicios/auth_servicio.dart';

/// Datos del usuario que inició sesión, en memoria mientras la app está abierta.
class Sesion {
  static String? token;
  static Map<String, dynamic>? usuario;

  static String? get uuidUsuario => usuario?['uuid_publico']?.toString();

  static void iniciar(LoginResultado resultado) {
    token = resultado.token;
    usuario = resultado.usuario;
  }

  static void cerrar() {
    token = null;
    usuario = null;
  }
}
