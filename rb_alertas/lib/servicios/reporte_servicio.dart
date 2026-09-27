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

/// Reporte vigente cerca de un punto, con la distancia que devuelve la API.
class ReporteCercano {
  final int id;
  final String categoriaCodigo;
  final String categoria;
  final String? colorHex;
  final double latitud;
  final double longitud;
  final String? direccion;
  final String descripcion;
  final DateTime? fechaCreacion;
  final double distanciaMetros;
  final int confirmaciones;

  ReporteCercano({
    required this.id,
    required this.categoriaCodigo,
    required this.categoria,
    required this.colorHex,
    required this.latitud,
    required this.longitud,
    required this.direccion,
    required this.descripcion,
    required this.fechaCreacion,
    required this.distanciaMetros,
    required this.confirmaciones,
  });

  /// "a 500 m" / "a 1.2 km", como se muestra en la lista de alertas.
  String get distanciaLegible {
    if (distanciaMetros < 1000) return '${distanciaMetros.round()} m';
    return '${(distanciaMetros / 1000).toStringAsFixed(1)} km';
  }

  factory ReporteCercano.desdeJson(Map<String, dynamic> json) {
    return ReporteCercano(
      id: json['id_reporte'] as int,
      categoriaCodigo: (json['categoria_codigo'] ?? '').toString(),
      categoria: (json['categoria'] ?? '').toString(),
      colorHex: json['color_hex']?.toString(),
      latitud: (json['latitud'] as num).toDouble(),
      longitud: (json['longitud'] as num).toDouble(),
      direccion: json['direccion']?.toString(),
      descripcion: (json['descripcion'] ?? '').toString(),
      fechaCreacion: DateTime.tryParse((json['fecha_creacion'] ?? '').toString()),
      distanciaMetros: (json['distancia_metros'] as num?)?.toDouble() ?? 0,
      confirmaciones: (json['total_confirmaciones'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Respuesta de /api/reportes/cercanos: los reportes y el radio que aplicó la
/// API (el de las preferencias del usuario, o el estándar si no tiene).
class AlertasCercanas {
  final int radioMetros;
  final List<ReporteCercano> reportes;

  AlertasCercanas({required this.radioMetros, required this.reportes});

  /// "2 km" o "800 m", para el encabezado de la pantalla.
  String get radioLegible => radioMetros < 1000
      ? '$radioMetros m'
      : '${(radioMetros / 1000).toStringAsFixed(radioMetros % 1000 == 0 ? 0 : 1)} km';

  factory AlertasCercanas.desdeJson(Map<String, dynamic> json) {
    return AlertasCercanas(
      radioMetros: (json['radio_metros'] as num?)?.toInt() ?? 0,
      reportes: [
        for (final r in (json['reportes'] as List? ?? []))
          ReporteCercano.desdeJson(r as Map<String, dynamic>),
      ],
    );
  }
}

/// Cómo ve el usuario el estado de un reporte suyo en el historial.
enum EstadoMiReporte { activa, resuelta, vencida, descartada }

/// Reporte creado por quien tiene la sesión abierta (pantalla "Mis reportes").
class MiReporte {
  final int id;
  final String categoriaCodigo;
  final String categoria;
  final String? colorHex;
  final String descripcion;
  final String? direccion;
  final String? zona;
  final EstadoMiReporte estado;
  final DateTime? fechaCreacion;
  final String? imagen;
  final int confirmaciones;
  final int desmentidos;

  MiReporte({
    required this.id,
    required this.categoriaCodigo,
    required this.categoria,
    required this.colorHex,
    required this.descripcion,
    required this.direccion,
    required this.zona,
    required this.estado,
    required this.fechaCreacion,
    required this.imagen,
    required this.confirmaciones,
    required this.desmentidos,
  });

  /// Apoyos netos: confirmaciones menos desmentidos, nunca bajo cero.
  int get apoyos {
    final neto = confirmaciones - desmentidos;
    return neto < 0 ? 0 : neto;
  }

  /// URL completa de la evidencia, o null si el reporte no trae foto.
  String? get imagenUrl =>
      imagen == null || imagen!.isEmpty ? null : ApiConfig.urlArchivo(imagen!);

  factory MiReporte.desdeJson(Map<String, dynamic> json) {
    return MiReporte(
      id: json['id_reporte'] as int,
      categoriaCodigo: (json['categoria_codigo'] ?? '').toString(),
      categoria: (json['categoria'] ?? '').toString(),
      colorHex: json['color_hex']?.toString(),
      descripcion: (json['descripcion'] ?? '').toString(),
      direccion: json['direccion']?.toString(),
      zona: json['zona']?.toString(),
      estado: switch ((json['estado_visual'] ?? '').toString()) {
        'ACTIVA' => EstadoMiReporte.activa,
        'RESUELTA' => EstadoMiReporte.resuelta,
        'DESCARTADA' => EstadoMiReporte.descartada,
        // Un estado que la app no conozca se muestra como no vigente, para
        // no dar por activo un reporte que ya no lo está.
        _ => EstadoMiReporte.vencida,
      },
      fechaCreacion: DateTime.tryParse((json['fecha_creacion'] ?? '').toString()),
      imagen: json['imagen']?.toString(),
      confirmaciones: (json['total_confirmaciones'] as num?)?.toInt() ?? 0,
      desmentidos: (json['total_desmentidos'] as num?)?.toInt() ?? 0,
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
/// Postura de un usuario frente a un reporte (tabla reporte_voto).
enum TipoVoto {
  confirma,
  desmiente;

  String get valorApi => this == TipoVoto.confirma ? 'CONFIRMA' : 'DESMIENTE';

  static TipoVoto? desdeApi(Object? valor) => switch (valor?.toString()) {
        'CONFIRMA' => TipoVoto.confirma,
        'DESMIENTE' => TipoVoto.desmiente,
        _ => null,
      };
}

/// Contadores de votos de un reporte y la postura de quien consulta.
class ResumenVotos {
  final int confirmaciones;
  final int desmentidos;
  final String estado;
  final TipoVoto? miVoto;

  ResumenVotos({
    required this.confirmaciones,
    required this.desmentidos,
    required this.estado,
    required this.miVoto,
  });

  factory ResumenVotos.desdeJson(Map<String, dynamic> json) {
    return ResumenVotos(
      confirmaciones: (json['total_confirmaciones'] as num?)?.toInt() ?? 0,
      desmentidos: (json['total_desmentidos'] as num?)?.toInt() ?? 0,
      estado: (json['estado'] ?? '').toString(),
      miVoto: TipoVoto.desdeApi(json['mi_voto']),
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
  final int confirmaciones;
  final int desmentidos;
  final TipoVoto? miVoto;

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
    required this.confirmaciones,
    required this.desmentidos,
    required this.miVoto,
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
      confirmaciones: (json['total_confirmaciones'] as num?)?.toInt() ?? 0,
      desmentidos: (json['total_desmentidos'] as num?)?.toInt() ?? 0,
      miVoto: TipoVoto.desdeApi(json['mi_voto']),
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

  /// Reportes vigentes alrededor del punto, con su distancia.
  ///
  /// Sin [radioKm] manda el token (si lo hay) y la API aplica el radio que el
  /// usuario tiene en sus preferencias.
  Future<AlertasCercanas> obtenerCercanos({
    required double latitud,
    required double longitud,
    double? radioKm,
    String? token,
  }) async {
    final uri = Uri.parse('$baseUrl/api/reportes/cercanos').replace(
      queryParameters: {
        'latitud': latitud.toString(),
        'longitud': longitud.toString(),
        if (radioKm != null) 'radio_km': radioKm.toString(),
      },
    );
    final respuesta = await http.get(
      uri,
      headers: {
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );

    if (respuesta.statusCode == 200) {
      return AlertasCercanas.desdeJson(
        jsonDecode(utf8.decode(respuesta.bodyBytes)) as Map<String, dynamic>,
      );
    }
    throw ReporteServicioException(
      _mensajeDeError(respuesta, 'No se pudieron cargar las alertas cercanas'),
    );
  }

  /// Confirma o desmiente un reporte. Volver a votar reemplaza el voto anterior.
  Future<ResumenVotos> votar(int idReporte, String token, TipoVoto voto) async {
    final respuesta = await http.put(
      Uri.parse('$baseUrl/api/reportes/$idReporte/voto'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'tipo_voto': voto.valorApi}),
    );
    if (respuesta.statusCode == 200) {
      return ResumenVotos.desdeJson(
        jsonDecode(utf8.decode(respuesta.bodyBytes)) as Map<String, dynamic>,
      );
    }
    throw ReporteServicioException(
      _mensajeDeError(respuesta, 'No se pudo registrar tu voto'),
    );
  }

  /// Retira el voto propio de un reporte.
  Future<ResumenVotos> quitarVoto(int idReporte, String token) async {
    final respuesta = await http.delete(
      Uri.parse('$baseUrl/api/reportes/$idReporte/voto'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (respuesta.statusCode == 200) {
      return ResumenVotos.desdeJson(
        jsonDecode(utf8.decode(respuesta.bodyBytes)) as Map<String, dynamic>,
      );
    }
    throw ReporteServicioException(
      _mensajeDeError(respuesta, 'No se pudo quitar tu voto'),
    );
  }

  /// Historial de reportes de quien tiene la sesión abierta.
  Future<List<MiReporte>> obtenerMisReportes(String token) async {
    final respuesta = await http.get(
      Uri.parse('$baseUrl/api/reportes/mios'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (respuesta.statusCode == 200) {
      final cuerpo = jsonDecode(utf8.decode(respuesta.bodyBytes)) as List;
      return cuerpo
          .map((r) => MiReporte.desdeJson(r as Map<String, dynamic>))
          .toList();
    }
    throw ReporteServicioException(
      _mensajeDeError(respuesta, 'No se pudo cargar tu historial de reportes'),
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
