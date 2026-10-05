import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rb_alertas/config/api_config.dart';

class AdminServicioException implements Exception {
  final String mensaje;
  AdminServicioException(this.mensaje);
}

class ResumenAdmin {
  final Map<String, int> usuariosPorEstado;
  final int usuariosNuevos7d;
  final Map<String, int> reportesPorEstado;
  final int reportes24h;
  final int reportes7d;
  final int reportesVigentes;
  final List<({String nombre, String? colorHex, int total})> categorias30d;

  ResumenAdmin({
    required this.usuariosPorEstado,
    required this.usuariosNuevos7d,
    required this.reportesPorEstado,
    required this.reportes24h,
    required this.reportes7d,
    required this.reportesVigentes,
    required this.categorias30d,
  });

  int get totalUsuarios => usuariosPorEstado.values.fold(0, (a, b) => a + b);

  static Map<String, int> _conteo(dynamic json) => {
    for (final e in (json as Map? ?? {}).entries)
      e.key.toString(): (e.value as num?)?.toInt() ?? 0,
  };

  factory ResumenAdmin.desdeJson(Map<String, dynamic> json) {
    return ResumenAdmin(
      usuariosPorEstado: _conteo(json['usuarios_por_estado']),
      usuariosNuevos7d: (json['usuarios_nuevos_7d'] as num?)?.toInt() ?? 0,
      reportesPorEstado: _conteo(json['reportes_por_estado']),
      reportes24h: (json['reportes_24h'] as num?)?.toInt() ?? 0,
      reportes7d: (json['reportes_7d'] as num?)?.toInt() ?? 0,
      reportesVigentes: (json['reportes_vigentes'] as num?)?.toInt() ?? 0,
      categorias30d: [
        for (final c in (json['categorias_30d'] as List? ?? []))
          (
            nombre: (c['nombre'] ?? '').toString(),
            colorHex: c['color_hex']?.toString(),
            total: (c['total'] as num?)?.toInt() ?? 0,
          ),
      ],
    );
  }
}

class ReporteAdmin {
  final int id;
  final String categoria;
  final String categoriaCodigo;
  final String? colorHex;
  final String estado;
  final String descripcion;
  final String? direccion;
  final String? zona;
  final DateTime? fechaCreacion;
  final bool vencido;
  final int confirmaciones;
  final int desmentidos;
  final String? imagen;
  final String autor;

  ReporteAdmin({
    required this.id,
    required this.categoria,
    required this.categoriaCodigo,
    required this.colorHex,
    required this.estado,
    required this.descripcion,
    required this.direccion,
    required this.zona,
    required this.fechaCreacion,
    required this.vencido,
    required this.confirmaciones,
    required this.desmentidos,
    required this.imagen,
    required this.autor,
  });

  factory ReporteAdmin.desdeJson(Map<String, dynamic> json) {
    return ReporteAdmin(
      id: (json['id_reporte'] as num).toInt(),
      categoria: (json['categoria'] ?? '').toString(),
      categoriaCodigo: (json['categoria_codigo'] ?? '').toString(),
      colorHex: json['color_hex']?.toString(),
      estado: (json['estado'] ?? '').toString(),
      descripcion: (json['descripcion'] ?? '').toString(),
      direccion: json['direccion']?.toString(),
      zona: json['zona']?.toString(),
      fechaCreacion: DateTime.tryParse(json['fecha_creacion']?.toString() ?? ''),
      vencido: json['vencido'] == true,
      confirmaciones: (json['total_confirmaciones'] as num?)?.toInt() ?? 0,
      desmentidos: (json['total_desmentidos'] as num?)?.toInt() ?? 0,
      imagen: json['imagen']?.toString(),
      autor: (json['autor'] ?? '').toString(),
    );
  }
}

class UsuarioAdmin {
  final int id;
  final String nombres;
  final String apellidos;
  final String email;
  final String? rut;
  final String? telefono;
  final String estado;
  final bool emailVerificado;
  final DateTime? fechaCreacion;
  final int totalReportes;
  final bool esAdmin;

  UsuarioAdmin({
    required this.id,
    required this.nombres,
    required this.apellidos,
    required this.email,
    required this.rut,
    required this.telefono,
    required this.estado,
    required this.emailVerificado,
    required this.fechaCreacion,
    required this.totalReportes,
    required this.esAdmin,
  });

  String get nombreCompleto => '$nombres $apellidos'.trim();

  factory UsuarioAdmin.desdeJson(Map<String, dynamic> json) {
    return UsuarioAdmin(
      id: (json['id_usuario'] as num).toInt(),
      nombres: (json['nombres'] ?? '').toString(),
      apellidos: (json['apellidos'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      rut: json['rut']?.toString(),
      telefono: json['telefono']?.toString(),
      estado: (json['estado'] ?? '').toString(),
      emailVerificado: json['email_verificado'] == true,
      fechaCreacion: DateTime.tryParse(json['fecha_creacion']?.toString() ?? ''),
      totalReportes: (json['total_reportes'] as num?)?.toInt() ?? 0,
      esAdmin: json['es_admin'] == true,
    );
  }
}

/// Rutas /api/admin: solo responden a la cuenta administradora.
class AdminServicio {
  static const String baseUrl = ApiConfig.baseUrl;

  Future<ResumenAdmin> resumen(String token) async {
    final cuerpo = await _get(token, '/api/admin/resumen');
    return ResumenAdmin.desdeJson(cuerpo as Map<String, dynamic>);
  }

  Future<List<ReporteAdmin>> reportes(String token, {String? estado}) async {
    final cuerpo = await _get(token, '/api/admin/reportes', {
      'estado': ?estado,
    });
    return [
      for (final r in cuerpo as List)
        ReporteAdmin.desdeJson(r as Map<String, dynamic>),
    ];
  }

  Future<List<UsuarioAdmin>> usuarios(
    String token, {
    String? buscar,
    String? estado,
  }) async {
    final cuerpo = await _get(token, '/api/admin/usuarios', {
      if (buscar != null && buscar.trim().isNotEmpty) 'buscar': buscar.trim(),
      'estado': ?estado,
    });
    return [
      for (final u in cuerpo as List)
        UsuarioAdmin.desdeJson(u as Map<String, dynamic>),
    ];
  }

  Future<void> cambiarEstadoReporte(
    String token,
    int idReporte,
    String estado, {
    String? motivo,
  }) async {
    await _enviar(
      'PATCH',
      token,
      '/api/admin/reportes/$idReporte/estado',
      {'estado': estado, 'motivo': ?motivo},
    );
  }

  Future<void> suspenderAutor(String token, int idReporte) async {
    await _enviar(
      'POST',
      token,
      '/api/admin/reportes/$idReporte/suspender-autor',
      null,
    );
  }

  Future<void> cambiarEstadoUsuario(
    String token,
    int idUsuario,
    String estado,
  ) async {
    await _enviar('PATCH', token, '/api/admin/usuarios/$idUsuario/estado', {
      'estado': estado,
    });
  }

  Future<dynamic> _get(
    String token,
    String ruta, [
    Map<String, String>? parametros,
  ]) async {
    final uri = Uri.parse('$baseUrl$ruta').replace(
      queryParameters: (parametros == null || parametros.isEmpty)
          ? null
          : parametros,
    );
    final respuesta = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    if (respuesta.statusCode == 200) return _json(respuesta);
    throw AdminServicioException(_mensaje(respuesta, 'No se pudo cargar'));
  }

  Future<void> _enviar(
    String metodo,
    String token,
    String ruta,
    Map<String, dynamic>? cuerpo,
  ) async {
    final peticion = http.Request(metodo, Uri.parse('$baseUrl$ruta'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json'
      // La API exige Content-Length en POST/PATCH, así que siempre va un cuerpo.
      ..body = jsonEncode(cuerpo ?? {});
    final respuesta = await http.Response.fromStream(await peticion.send());
    if (respuesta.statusCode == 200) return;
    throw AdminServicioException(
      _mensaje(respuesta, 'No se pudo guardar el cambio'),
    );
  }

  dynamic _json(http.Response respuesta) =>
      jsonDecode(utf8.decode(respuesta.bodyBytes));

  String _mensaje(http.Response respuesta, String porDefecto) {
    try {
      final detalle = (_json(respuesta) as Map)['detail'];
      if (detalle is String) return detalle;
    } catch (_) {
      // se usa el mensaje por defecto
    }
    return porDefecto;
  }
}
