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

  CategoriaIncidente({
    required this.id,
    required this.codigo,
    required this.nombre,
  });

  factory CategoriaIncidente.desdeJson(Map<String, dynamic> json) {
    return CategoriaIncidente(
      id: json['id_categoria'] as int,
      codigo: (json['codigo'] ?? '').toString(),
      nombre: (json['nombre'] ?? '').toString(),
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

  Future<int> enviarReporte({
    required String uuidUsuario,
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

    solicitud.fields.addAll({
      'uuid_usuario': uuidUsuario,
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
