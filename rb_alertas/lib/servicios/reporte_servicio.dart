import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:rb_alertas/config/api_config.dart';

class ReporteServicioException implements Exception {
  final String mensaje;
  ReporteServicioException(this.mensaje);
}

class CategoriaIncidente {
  final int id;
  final String codigo;
  final String nombre;
  final String? colorHex;

  CategoriaIncidente({
    required this.id,
    required this.codigo,
    required this.nombre,
    this.colorHex,
  });

  factory CategoriaIncidente.desdeJson(Map<String, dynamic> json) {
    return CategoriaIncidente(
      id: json['id_categoria'] as int,
      codigo: (json['codigo'] ?? '').toString(),
      nombre: (json['nombre'] ?? '').toString(),
      colorHex: json['color_hex']?.toString(),
    );
  }
}

class ReporteMapa {
  final int id;
  final String categoriaCodigo;
  final String categoria;
  final String? colorHex;
  final double latitud;
  final double longitud;
  final String? direccion;
  final String descripcion;
  final DateTime? fechaCreacion;

  ReporteMapa({
    required this.id,
    required this.categoriaCodigo,
    required this.categoria,
    required this.colorHex,
    required this.latitud,
    required this.longitud,
    required this.direccion,
    required this.descripcion,
    required this.fechaCreacion,
  });

  factory ReporteMapa.desdeJson(Map<String, dynamic> json) {
    return ReporteMapa(
      id: json['id_reporte'] as int,
      categoriaCodigo: (json['categoria_codigo'] ?? '').toString(),
      categoria: (json['categoria'] ?? '').toString(),
      colorHex: json['color_hex']?.toString(),
      latitud: (json['latitud'] as num).toDouble(),
      longitud: (json['longitud'] as num).toDouble(),
      direccion: json['direccion']?.toString(),
      descripcion: (json['descripcion'] ?? '').toString(),
      fechaCreacion: DateTime.tryParse((json['fecha_creacion'] ?? '').toString()),
    );
  }
}

class EntidadEmergencia {
  final String nombre;
  final String tipo;
  final String telefono;

  EntidadEmergencia({required this.nombre, required this.tipo, required this.telefono});

  factory EntidadEmergencia.desdeJson(Map<String, dynamic> json) {
    return EntidadEmergencia(
      nombre: (json['nombre'] ?? '').toString(),
      tipo: (json['tipo'] ?? '').toString(),
      telefono: (json['telefono'] ?? '').toString(),
    );
  }
}

class DetalleReporte {
  final int id;
  final String categoriaCodigo;
  final String categoria;
  final String? colorHex;
  final double latitud;
  final double longitud;
  final String? direccion;
  final String descripcion;
  final String estado;
  final DateTime? fechaCreacion;
  final String autor;
  // true si quien consulta (según el token de la sesión) creó el reporte.
  final bool esAutor;
  final List<String> imagenes;
  final EntidadEmergencia? emergencia;

  DetalleReporte({
    required this.id,
    required this.categoriaCodigo,
    required this.categoria,
    required this.colorHex,
    required this.latitud,
    required this.longitud,
    required this.direccion,
    required this.descripcion,
    required this.estado,
    required this.fechaCreacion,
    required this.autor,
    required this.esAutor,
    required this.imagenes,
    required this.emergencia,
  });

  bool get activo => estado == 'PENDIENTE' || estado == 'VALIDADO';

  factory DetalleReporte.desdeJson(Map<String, dynamic> json) {
    final emergencia = json['emergencia'];
    return DetalleReporte(
      id: json['id_reporte'] as int,
      categoriaCodigo: (json['categoria_codigo'] ?? '').toString(),
      categoria: (json['categoria'] ?? '').toString(),
      colorHex: json['color_hex']?.toString(),
      latitud: (json['latitud'] as num).toDouble(),
      longitud: (json['longitud'] as num).toDouble(),
      direccion: json['direccion']?.toString(),
      descripcion: (json['descripcion'] ?? '').toString(),
      estado: (json['estado'] ?? '').toString(),
      fechaCreacion: DateTime.tryParse((json['fecha_creacion'] ?? '').toString()),
      autor: (json['autor'] ?? '').toString(),
      esAutor: json['es_autor'] == true,
      imagenes: [for (final url in (json['imagenes'] as List? ?? [])) url.toString()],
      emergencia: emergencia is Map<String, dynamic>
          ? EntidadEmergencia.desdeJson(emergencia)
          : null,
    );
  }
}

class Evidencia {
  final String nombreArchivo;
  final Uint8List bytes;

  Evidencia({required this.nombreArchivo, required this.bytes});
}

class ReporteServicio {
  static const String baseUrl = ApiConfig.baseUrl;

  Future<List<CategoriaIncidente>> obtenerCategorias() async {
    final respuesta = await http.get(
      Uri.parse('$baseUrl/api/reportes/categorias'),
    );

    if (respuesta.statusCode == 200) {
      final cuerpo = jsonDecode(utf8.decode(respuesta.bodyBytes)) as List;
      return cuerpo
          .map((c) => CategoriaIncidente.desdeJson(c as Map<String, dynamic>))
          .toList();
    }
    throw ReporteServicioException(
      _mensajeDeError(respuesta, 'No se pudieron cargar las categorías'),
    );
  }

  /// Detalle de un reporte. Con [token], la API indica si quien consulta es el autor.
  Future<DetalleReporte> obtenerDetalle(int idReporte, {String? token}) async {
    final respuesta = await http.get(
      Uri.parse('$baseUrl/api/reportes/$idReporte'),
      headers: {
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );

    if (respuesta.statusCode == 200) {
      return DetalleReporte.desdeJson(
        jsonDecode(utf8.decode(respuesta.bodyBytes)) as Map<String, dynamic>,
      );
    }
    throw ReporteServicioException(
      _mensajeDeError(respuesta, 'No se pudo cargar el reporte'),
    );
  }

  /// Marca el reporte como resuelto (solo lo permite la API a su autor).
  Future<void> marcarResuelto(int idReporte, String token) async {
    final respuesta = await http.post(
      Uri.parse('$baseUrl/api/reportes/$idReporte/resolver'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (respuesta.statusCode == 200) return;
    throw ReporteServicioException(
      _mensajeDeError(respuesta, 'No se pudo marcar como resuelto'),
    );
  }

  Future<List<ReporteMapa>> obtenerReportes() async {
    final respuesta = await http.get(Uri.parse('$baseUrl/api/reportes/'));

    if (respuesta.statusCode == 200) {
      final cuerpo = jsonDecode(utf8.decode(respuesta.bodyBytes)) as List;
      return cuerpo
          .map((r) => ReporteMapa.desdeJson(r as Map<String, dynamic>))
          .toList();
    }
    throw ReporteServicioException(
      _mensajeDeError(respuesta, 'No se pudieron cargar los reportes'),
    );
  }

  /// [token] es el de la sesión (login): la API identifica al autor con él.
  Future<int> enviarReporte({
    required String token,
    required int idCategoria,
    required String descripcion,
    required double latitud,
    required double longitud,
    String? direccion,
    Evidencia? evidencia,
  }) async {
    final solicitud = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/reportes/'),
    );

    solicitud.headers['Authorization'] = 'Bearer $token';
    solicitud.fields.addAll({
      'id_categoria': idCategoria.toString(),
      'descripcion': descripcion,
      'latitud': latitud.toString(),
      'longitud': longitud.toString(),
      if (direccion != null && direccion.isNotEmpty) 'direccion': direccion,
    });

    if (evidencia != null) {
      solicitud.files.add(
        http.MultipartFile.fromBytes(
          'evidencia',
          evidencia.bytes,
          filename: evidencia.nombreArchivo,
        ),
      );
    }

    final respuesta = await http.Response.fromStream(await solicitud.send());

    if (respuesta.statusCode == 201) {
      final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
      return cuerpo['id_reporte'] as int;
    }
    throw ReporteServicioException(
      _mensajeDeError(respuesta, 'No se pudo enviar el reporte'),
    );
  }

  String _mensajeDeError(http.Response respuesta, String porDefecto) {
    try {
      final cuerpo = jsonDecode(utf8.decode(respuesta.bodyBytes));
      // Si falla la validación FastAPI manda una lista en vez de un texto;
      // en ese caso se muestra el mensaje por defecto.
      final detalle = cuerpo is Map ? cuerpo['detail'] : null;
      if (detalle is String) return detalle;
    } catch (_) {
      // se usa el mensaje por defecto si el cuerpo no es JSON válido
    }
    return porDefecto;
  }
}
