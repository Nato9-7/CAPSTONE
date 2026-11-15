import 'package:rb_alertas/modelos/lectura_json.dart';
import 'package:rb_alertas/modelos/territorio.dart';
import 'package:rb_alertas/modelos/usuario.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';

/// Login, registro y recuperación de cuenta.
class AuthServicio {
  /// Código de error que manda la API al iniciar sesión sin verificar el correo.
  static const String codigoEmailNoVerificado = 'EMAIL_NO_VERIFICADO';

  /// Comprueba contra la API si el token de la sesión sigue vigente.
  ///
  /// `true` = sirve, `false` = la sesión ya no vale (hay que volver a entrar),
  /// `null` = no se pudo preguntar (sin conexión); en ese caso no conviene
  /// borrar la sesión, porque puede ser perfectamente válida.
  Future<bool?> sesionVigente() async {
    try {
      await ApiCliente.get('/api/usuarios/perfil', error: '').timeout(const Duration(seconds: 8));
      return true;
    } on ApiException catch (e) {
      return e.estadoHttp == 401 ? false : null;
    } catch (_) {
      return null;
    }
  }

  Future<LoginResultado> login({required String email, required String password}) async {
    final cuerpo = await ApiCliente.post(
      '/api/usuarios/login',
      cuerpo: {'email': email, 'password': password},
      error: 'Correo o contraseña incorrectos',
      conSesion: false,
    ) as Map<String, dynamic>;
    return LoginResultado(
      token: (cuerpo['token'] ?? cuerpo['access_token'] ?? '').toString(),
      usuario: (cuerpo['usuario'] ?? cuerpo['user'] ?? {}) as Map<String, dynamic>,
    );
  }

  /// Regiones con las comunas que se pueden elegir al registrarse.
  Future<List<Region>> regionesRegistro() async {
    final cuerpo = await ApiCliente.get(
      '/api/usuarios/comunas',
      error: 'No se pudieron cargar las comunas',
      conSesion: false,
    );
    return listaDesdeJson(cuerpo, Region.desdeJson);
  }

  /// Crea la cuenta con su comuna y deja constancia de que aceptó los textos
  /// legales en [versionTerminos]. La API envía un correo para verificarla.
  Future<void> registrar({
    required String nombres,
    required String apellidos,
    required String rut,
    required String email,
    required String telefono,
    required String password,
    required int idComuna,
    required String versionTerminos,
  }) async {
    await ApiCliente.post(
      '/api/usuarios/registro',
      cuerpo: {
        'nombres': nombres,
        'apellidos': apellidos,
        'rut': rut,
        'email': email,
        'telefono': telefono,
        'password': password,
        'id_comuna': idComuna,
        'acepta_terminos': true,
        'version_terminos': versionTerminos,
      },
      error: 'No se pudo completar el registro',
      conSesion: false,
    );
  }

  /// Pide un nuevo correo de verificación. Devuelve el mensaje para mostrar.
  Future<String> reenviarVerificacion(String email) => _pedirCorreo(
    '/api/usuarios/reenviar-verificacion',
    email,
    exito: 'Te enviamos un nuevo enlace a tu correo.',
    error: 'No se pudo reenviar el correo',
  );

  /// Pide el correo con el enlace para crear una contraseña nueva.
  /// Devuelve el mensaje para mostrar.
  Future<String> recuperarPassword(String email) => _pedirCorreo(
    '/api/usuarios/recuperar-password',
    email,
    exito: 'Te enviamos un enlace a tu correo.',
    error: 'No se pudo enviar el correo',
  );

  Future<String> _pedirCorreo(
    String ruta,
    String email, {
    required String exito,
    required String error,
  }) async {
    final cuerpo = await ApiCliente.post(ruta, cuerpo: {'email': email}, error: error, conSesion: false);
    return (cuerpo is Map ? cuerpo['detail'] : null)?.toString() ?? exito;
  }
}
