import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rb_alertas/config/api_config.dart';
import 'package:rb_alertas/servicios/sesion.dart';

/// Error de una llamada a la API, con el mensaje listo para mostrar.
class ApiException implements Exception {
  final String mensaje;

  /// Código que la API manda en algunos errores (p. ej. `EMAIL_NO_VERIFICADO`).
  final String? codigo;

  /// Estado HTTP de la respuesta.
  final int estadoHttp;

  const ApiException(this.mensaje, {this.codigo, required this.estadoHttp});

  @override
  String toString() => mensaje;
}

/// Texto para mostrar ante un error de una llamada: el de la API si lo hay,
/// o un aviso de conexión para cualquier otro fallo (red, tiempo agotado...).
String mensajeDeError(Object error) => error is ApiException
    ? error.mensaje
    : 'No se pudo conectar con el servidor';

/// Archivo que viaja en un formulario multipart.
typedef ArchivoAdjunto = ({String campo, String nombre, List<int> bytes});

/// Punto único de acceso a la API de RB Alertas.
///
/// - Envía el token de [Sesion] salvo que se pida `conSesion: false`.
/// - Cualquier estado fuera de 2xx se convierte en [ApiException] con el
///   `detail` de FastAPI, o con [error] si la API no trae uno legible.
class ApiCliente {
  const ApiCliente._();

  static Future<dynamic> get(
    String ruta, {
    required String error,
    Map<String, String>? consulta,
    bool conSesion = true,
  }) => _enviar(
    'GET',
    ruta,
    error: error,
    consulta: consulta,
    conSesion: conSesion,
  );

  static Future<dynamic> post(
    String ruta, {
    required String error,
    Object? cuerpo,
    bool conSesion = true,
  }) =>
      _enviar('POST', ruta, error: error, cuerpo: cuerpo, conSesion: conSesion);

  static Future<dynamic> put(
    String ruta, {
    required String error,
    Object? cuerpo,
  }) => _enviar('PUT', ruta, error: error, cuerpo: cuerpo);

  static Future<dynamic> patch(
    String ruta, {
    required String error,
    Object? cuerpo,
  }) => _enviar('PATCH', ruta, error: error, cuerpo: cuerpo);

  static Future<dynamic> delete(String ruta, {required String error}) =>
      _enviar('DELETE', ruta, error: error);

  /// Formulario multipart (reportes y comentarios con foto).
  static Future<dynamic> multipart(
    String ruta, {
    required String error,
    required Map<String, String> campos,
    List<ArchivoAdjunto> archivos = const [],
  }) async {
    final peticion = http.MultipartRequest('POST', _uri(ruta))
      ..headers.addAll(_cabeceraSesion())
      ..fields.addAll(campos)
      ..files.addAll([
        for (final a in archivos)
          http.MultipartFile.fromBytes(a.campo, a.bytes, filename: a.nombre),
      ]);
    return _leer(await http.Response.fromStream(await peticion.send()), error);
  }

  static Future<dynamic> _enviar(
    String metodo,
    String ruta, {
    required String error,
    Map<String, String>? consulta,
    Object? cuerpo,
    bool conSesion = true,
  }) async {
    final peticion = http.Request(metodo, _uri(ruta, consulta));
    if (conSesion) peticion.headers.addAll(_cabeceraSesion());
    if (metodo != 'GET') {
      // La API exige Content-Length en POST/PUT/PATCH: siempre va un cuerpo.
      peticion.headers['Content-Type'] = 'application/json; charset=utf-8';
      peticion.body = jsonEncode(cuerpo ?? const {});
    }
    return _leer(await http.Response.fromStream(await peticion.send()), error);
  }

  static Uri _uri(String ruta, [Map<String, String>? consulta]) {
    final uri = Uri.parse('${ApiConfig.baseUrl}$ruta');
    return (consulta == null || consulta.isEmpty)
        ? uri
        : uri.replace(queryParameters: consulta);
  }

  static Map<String, String> _cabeceraSesion() {
    final token = Sesion.token;
    return (token == null || token.isEmpty)
        ? const {}
        : {'Authorization': 'Bearer $token'};
  }

  static dynamic _leer(http.Response respuesta, String error) {
    final cuerpo = _json(respuesta);
    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) {
      return cuerpo;
    }

    // FastAPI manda `detail` como texto, como {mensaje, codigo} en los errores
    // que la app distingue, o como lista si falla la validación (se ignora).
    final detalle = cuerpo is Map ? cuerpo['detail'] : null;
    if (detalle is String) {
      throw ApiException(detalle, estadoHttp: respuesta.statusCode);
    }
    if (detalle is Map && detalle['mensaje'] != null) {
      throw ApiException(
        detalle['mensaje'].toString(),
        codigo: detalle['codigo']?.toString(),
        estadoHttp: respuesta.statusCode,
      );
    }
    throw ApiException(error, estadoHttp: respuesta.statusCode);
  }

  /// Cuerpo decodificado, o null si viene vacío o no es JSON.
  static dynamic _json(http.Response respuesta) {
    if (respuesta.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(respuesta.bodyBytes));
    } on FormatException {
      return null;
    }
  }
}
