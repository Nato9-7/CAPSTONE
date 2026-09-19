import 'package:rb_alertas/servicios/auth_servicio.dart';

/// Datos del usuario que inició sesión, en memoria mientras la app está abierta.
/// [token] es el que entrega el login y se envía como `Authorization: Bearer`
/// en las rutas protegidas de la API.
class Sesion {
  static String? token;
  static Map<String, dynamic>? usuario;

  static void iniciar(LoginResultado resultado) {
    token = resultado.token;
    usuario = resultado.usuario;
  }

  static void cerrar() {
    token = null;
    usuario = null;
  }
}
