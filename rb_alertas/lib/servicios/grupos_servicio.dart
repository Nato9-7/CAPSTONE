import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rb_alertas/config/api_config.dart';

class GruposServicioException implements Exception {
  final String mensaje;
  GruposServicioException(this.mensaje);
}

DateTime? _fecha(Object? valor) =>
    valor == null ? null : DateTime.tryParse(valor.toString())?.toLocal();

/// "500 m" o "1 km", igual que en las zonas seguras.
String radioTexto(int metros) => metros < 1000
    ? '$metros m'
    : '${(metros / 1000).toStringAsFixed(metros % 1000 == 0 ? 0 : 1).replaceAll('.', ',')} km';

class Grupo {
  final int id;
  final String nombre;
  final String? descripcion;
  final double latitud;
  final double longitud;
  final int radioMetros;
  final String? direccion;
  final bool esAdmin;
  final int totalMiembros;
  final DateTime? ultimoReporte;

  /// Solo los recibe el admin: es quien comparte y regenera el código.
  final String? codigo;
  final DateTime? codigoExpira;
  final bool codigoVencido;

  Grupo({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.latitud,
    required this.longitud,
    required this.radioMetros,
    required this.direccion,
    required this.esAdmin,
    required this.totalMiembros,
    required this.ultimoReporte,
    required this.codigo,
    required this.codigoExpira,
    required this.codigoVencido,
  });

  String get radioLegible => radioTexto(radioMetros);

  String get miembrosTexto => totalMiembros == 1 ? '1 vecino' : '$totalMiembros vecinos';

  factory Grupo.desdeJson(Map<String, dynamic> json) {
    return Grupo(
      id: (json['id_grupo'] as num).toInt(),
      nombre: (json['nombre'] ?? '').toString(),
      descripcion: json['descripcion']?.toString(),
      latitud: (json['latitud'] as num).toDouble(),
      longitud: (json['longitud'] as num).toDouble(),
      radioMetros: (json['radio_metros'] as num?)?.toInt() ?? 1000,
      direccion: json['direccion_referencia']?.toString(),
      esAdmin: json['es_admin'] == true,
      totalMiembros: (json['total_miembros'] as num?)?.toInt() ?? 1,
      ultimoReporte: _fecha(json['ultimo_reporte']),
      codigo: json['codigo_invitacion']?.toString(),
      codigoExpira: _fecha(json['codigo_expira']),
      codigoVencido: json['codigo_vencido'] == true,
    );
  }
}

class MisGrupos {
  final List<Grupo> grupos;
  final int maximo;
  final bool puedeCrear;
  final List<int> radiosPermitidos;

  MisGrupos({
    required this.grupos,
    required this.maximo,
    required this.puedeCrear,
    required this.radiosPermitidos,
  });

  bool get administraUno => grupos.any((g) => g.esAdmin);

  factory MisGrupos.desdeJson(Map<String, dynamic> json) {
    return MisGrupos(
      grupos: [
        for (final g in (json['grupos'] as List? ?? []))
          Grupo.desdeJson(g as Map<String, dynamic>),
      ],
      maximo: (json['maximo'] as num?)?.toInt() ?? 5,
      puedeCrear: json['puede_crear'] == true,
      radiosPermitidos: [
        for (final r in (json['radios_permitidos'] as List? ?? [500, 1000, 2000]))
          (r as num).toInt(),
      ],
    );
  }
}

/// Lo que se ve de un grupo antes de unirse: sin el centro exacto.
class InvitacionGrupo {
  final String nombre;
  final String? descripcion;
  final int radioMetros;
  final int totalMiembros;
  final bool yaEsMiembro;

  InvitacionGrupo({
    required this.nombre,
    required this.descripcion,
    required this.radioMetros,
    required this.totalMiembros,
    required this.yaEsMiembro,
  });

  factory InvitacionGrupo.desdeJson(Map<String, dynamic> json) {
    return InvitacionGrupo(
      nombre: (json['nombre'] ?? '').toString(),
      descripcion: json['descripcion']?.toString(),
      radioMetros: (json['radio_metros'] as num?)?.toInt() ?? 1000,
      totalMiembros: (json['total_miembros'] as num?)?.toInt() ?? 1,
      yaEsMiembro: json['ya_es_miembro'] == true,
    );
  }
}

class MiembroGrupo {
  final int id;
  final String alias;
  final bool esAdmin;
  final bool soyYo;
  final DateTime? fechaUnion;

  MiembroGrupo({
    required this.id,
    required this.alias,
    required this.esAdmin,
    required this.soyYo,
    required this.fechaUnion,
  });

  factory MiembroGrupo.desdeJson(Map<String, dynamic> json) {
    return MiembroGrupo(
      id: (json['id_miembro'] as num).toInt(),
      alias: (json['alias'] ?? 'Vecino').toString(),
      esAdmin: json['rol'] == 'ADMIN',
      soyYo: json['soy_yo'] == true,
      fechaUnion: _fecha(json['fecha_union']),
    );
  }
}

/// Un reporte compartido en el grupo: una tarjeta del "chat".
class ReporteGrupo {
  final int id;
  final String autor;
  final bool esMio;
  final bool soloGrupo;
  final String categoriaCodigo;
  final String categoria;
  final String? colorHex;
  final String? direccion;
  final String descripcion;
  final String estado;
  final DateTime? fecha;
  final int totalComentarios;
  final String? imagen;

  ReporteGrupo({
    required this.id,
    required this.autor,
    required this.esMio,
    required this.soloGrupo,
    required this.categoriaCodigo,
    required this.categoria,
    required this.colorHex,
    required this.direccion,
    required this.descripcion,
    required this.estado,
    required this.fecha,
    required this.totalComentarios,
    required this.imagen,
  });

  factory ReporteGrupo.desdeJson(Map<String, dynamic> json) {
    return ReporteGrupo(
      id: (json['id_reporte'] as num).toInt(),
      autor: (json['autor'] ?? 'Un vecino').toString(),
      esMio: json['es_mio'] == true,
      soloGrupo: json['visibilidad'] == 'GRUPO',
      categoriaCodigo: (json['categoria_codigo'] ?? '').toString(),
      categoria: (json['categoria'] ?? 'Incidente').toString(),
      colorHex: json['color_hex']?.toString(),
      direccion: json['direccion']?.toString(),
      descripcion: (json['descripcion'] ?? '').toString(),
      estado: (json['estado'] ?? 'PENDIENTE').toString(),
      fecha: _fecha(json['fecha_publicacion'] ?? json['fecha_creacion']),
      totalComentarios: (json['total_comentarios'] as num?)?.toInt() ?? 0,
      imagen: json['imagen']?.toString(),
    );
  }
}

/// Un grupo del usuario cuyo círculo contiene el lugar del incidente.
class GrupoEnPunto {
  final int id;
  final String nombre;

  GrupoEnPunto({required this.id, required this.nombre});

  factory GrupoEnPunto.desdeJson(Map<String, dynamic> json) {
    return GrupoEnPunto(
      id: (json['id_grupo'] as num).toInt(),
      nombre: (json['nombre'] ?? '').toString(),
    );
  }
}

class GruposServicio {
  static const String baseUrl = ApiConfig.baseUrl;
  static const String _ruta = '/api/grupos';

  /// Reportes que trae cada página del chat.
  static const int reportesPorPagina = 30;

  Future<MisGrupos> listar(String token) async {
    final respuesta = await http.get(
      Uri.parse('$baseUrl$_ruta/'),
      headers: _autorizacion(token),
    );
    if (respuesta.statusCode == 200) return MisGrupos.desdeJson(_json(respuesta));
    throw GruposServicioException(_mensaje(respuesta, 'No se pudieron cargar tus grupos'));
  }

  /// Grupos donde se puede compartir un reporte hecho en este punto.
  Future<List<GrupoEnPunto>> enPunto({
    required String token,
    required double latitud,
    required double longitud,
  }) async {
    final respuesta = await http.get(
      Uri.parse('$baseUrl$_ruta/en-punto').replace(
        queryParameters: {'latitud': '$latitud', 'longitud': '$longitud'},
      ),
      headers: _autorizacion(token),
    );
    if (respuesta.statusCode == 200) {
      return [
        for (final g in jsonDecode(utf8.decode(respuesta.bodyBytes)) as List)
          GrupoEnPunto.desdeJson(g as Map<String, dynamic>),
      ];
    }
    throw GruposServicioException(_mensaje(respuesta, 'No se pudieron revisar tus grupos'));
  }

  Future<Grupo> detalle({required String token, required int idGrupo}) async {
    final respuesta = await http.get(
      Uri.parse('$baseUrl$_ruta/$idGrupo'),
      headers: _autorizacion(token),
    );
    if (respuesta.statusCode == 200) return Grupo.desdeJson(_json(respuesta));
    throw GruposServicioException(_mensaje(respuesta, 'No se pudo cargar el grupo'));
  }

  Future<Grupo> crear({
    required String token,
    required String nombre,
    String? descripcion,
    required double latitud,
    required double longitud,
    required int radioMetros,
    String? direccion,
  }) async {
    final respuesta = await http.post(
      Uri.parse('$baseUrl$_ruta/'),
      headers: _cabeceras(token),
      body: jsonEncode(_cuerpo(nombre, descripcion, latitud, longitud, radioMetros, direccion)),
    );
    if (respuesta.statusCode == 201) return Grupo.desdeJson(_json(respuesta));
    throw GruposServicioException(_mensaje(respuesta, 'No se pudo crear el grupo'));
  }

  Future<Grupo> actualizar({
    required String token,
    required int idGrupo,
    required String nombre,
    String? descripcion,
    required double latitud,
    required double longitud,
    required int radioMetros,
    String? direccion,
  }) async {
    final respuesta = await http.put(
      Uri.parse('$baseUrl$_ruta/$idGrupo'),
      headers: _cabeceras(token),
      body: jsonEncode(_cuerpo(nombre, descripcion, latitud, longitud, radioMetros, direccion)),
    );
    if (respuesta.statusCode == 200) return Grupo.desdeJson(_json(respuesta));
    throw GruposServicioException(_mensaje(respuesta, 'No se pudieron guardar los cambios'));
  }

  Future<void> eliminar({required String token, required int idGrupo}) async {
    final respuesta = await http.delete(
      Uri.parse('$baseUrl$_ruta/$idGrupo'),
      headers: _autorizacion(token),
    );
    if (respuesta.statusCode == 204 || respuesta.statusCode == 200) return;
    throw GruposServicioException(_mensaje(respuesta, 'No se pudo eliminar el grupo'));
  }

  Future<InvitacionGrupo> verInvitacion({required String token, required String codigo}) async {
    final respuesta = await http.get(
      Uri.parse('$baseUrl$_ruta/invitacion/${Uri.encodeComponent(codigo.trim())}'),
      headers: _autorizacion(token),
    );
    if (respuesta.statusCode == 200) return InvitacionGrupo.desdeJson(_json(respuesta));
    throw GruposServicioException(_mensaje(respuesta, 'No se pudo revisar el código'));
  }

  Future<Grupo> unirse({required String token, required String codigo}) async {
    final respuesta = await http.post(
      Uri.parse('$baseUrl$_ruta/unirse'),
      headers: _cabeceras(token),
      body: jsonEncode({'codigo': codigo.trim()}),
    );
    if (respuesta.statusCode == 200) return Grupo.desdeJson(_json(respuesta));
    throw GruposServicioException(_mensaje(respuesta, 'No se pudo entrar al grupo'));
  }

  Future<Grupo> regenerarCodigo({required String token, required int idGrupo}) async {
    final respuesta = await http.post(
      Uri.parse('$baseUrl$_ruta/$idGrupo/codigo'),
      headers: _autorizacion(token),
    );
    if (respuesta.statusCode == 200) return Grupo.desdeJson(_json(respuesta));
    throw GruposServicioException(_mensaje(respuesta, 'No se pudo generar un código nuevo'));
  }

  Future<List<MiembroGrupo>> miembros({required String token, required int idGrupo}) async {
    final respuesta = await http.get(
      Uri.parse('$baseUrl$_ruta/$idGrupo/miembros'),
      headers: _autorizacion(token),
    );
    if (respuesta.statusCode == 200) {
      return [
        for (final m in jsonDecode(utf8.decode(respuesta.bodyBytes)) as List)
          MiembroGrupo.desdeJson(m as Map<String, dynamic>),
      ];
    }
    throw GruposServicioException(_mensaje(respuesta, 'No se pudieron cargar los vecinos'));
  }

  Future<void> expulsar({
    required String token,
    required int idGrupo,
    required int idMiembro,
  }) async {
    final respuesta = await http.delete(
      Uri.parse('$baseUrl$_ruta/$idGrupo/miembros/$idMiembro'),
      headers: _autorizacion(token),
    );
    if (respuesta.statusCode == 204 || respuesta.statusCode == 200) return;
    throw GruposServicioException(_mensaje(respuesta, 'No se pudo quitar al vecino'));
  }

  Future<void> salir({required String token, required int idGrupo}) async {
    final respuesta = await http.post(
      Uri.parse('$baseUrl$_ruta/$idGrupo/salir'),
      headers: _autorizacion(token),
    );
    if (respuesta.statusCode == 204 || respuesta.statusCode == 200) return;
    throw GruposServicioException(_mensaje(respuesta, 'No se pudo salir del grupo'));
  }

  /// Reportes del grupo, del más reciente al más antiguo. Con [antesDe]
  /// (id del último reporte recibido) trae la página siguiente.
  Future<List<ReporteGrupo>> reportes({
    required String token,
    required int idGrupo,
    int? antesDe,
  }) async {
    final respuesta = await http.get(
      Uri.parse('$baseUrl$_ruta/$idGrupo/reportes').replace(
        queryParameters: {
          'limite': '$reportesPorPagina',
          if (antesDe != null) 'antes_de': '$antesDe',
        },
      ),
      headers: _autorizacion(token),
    );
    if (respuesta.statusCode == 200) {
      return [
        for (final r in jsonDecode(utf8.decode(respuesta.bodyBytes)) as List)
          ReporteGrupo.desdeJson(r as Map<String, dynamic>),
      ];
    }
    throw GruposServicioException(_mensaje(respuesta, 'No se pudieron cargar los reportes del grupo'));
  }

  Map<String, String> _autorizacion(String token) => {'Authorization': 'Bearer $token'};

  Map<String, String> _cabeceras(String token) => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json; charset=utf-8',
  };

  Map<String, dynamic> _json(http.Response respuesta) =>
      jsonDecode(utf8.decode(respuesta.bodyBytes)) as Map<String, dynamic>;

  Map<String, dynamic> _cuerpo(
    String nombre,
    String? descripcion,
    double latitud,
    double longitud,
    int radioMetros,
    String? direccion,
  ) {
    final textoDescripcion = (descripcion ?? '').trim();
    final referencia = (direccion ?? '').trim();
    return {
      'nombre': nombre.trim(),
      'descripcion': textoDescripcion.isEmpty ? null : textoDescripcion,
      'latitud': latitud,
      'longitud': longitud,
      'radio_metros': radioMetros,
      'direccion_referencia': referencia.isEmpty ? null : referencia,
    };
  }

  String _mensaje(http.Response respuesta, String porDefecto) {
    try {
      final cuerpo = jsonDecode(utf8.decode(respuesta.bodyBytes));
      final detalle = cuerpo is Map ? cuerpo['detail'] : null;
      if (detalle is String) return detalle;
    } catch (_) {
      // se usa el mensaje por defecto
    }
    return porDefecto;
  }
}
