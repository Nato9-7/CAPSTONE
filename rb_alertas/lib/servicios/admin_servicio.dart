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
  // Privado de un grupo vecinal: no sale en el mapa público.
  final bool soloGrupo;

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
    this.soloGrupo = false,
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
      fechaCreacion: DateTime.tryParse(
        json['fecha_creacion']?.toString() ?? '',
      ),
      vencido: json['vencido'] == true,
      confirmaciones: (json['total_confirmaciones'] as num?)?.toInt() ?? 0,
      desmentidos: (json['total_desmentidos'] as num?)?.toInt() ?? 0,
      imagen: json['imagen']?.toString(),
      autor: (json['autor'] ?? '').toString(),
      soloGrupo: json['visibilidad'] == 'GRUPO',
    );
  }
}

/// Grupo vecinal tal como lo ve el panel: activo o cerrado, con quien lo creó.
class GrupoAdmin {
  final int id;
  final String nombre;
  final String? descripcion;
  final int radioMetros;
  final String? direccion;
  final bool activo;
  final DateTime? fechaCreacion;
  final String creador;
  final String creadorEmail;
  final int totalMiembros;
  final int totalReportes;
  final int reportesPrivados;
  final DateTime? ultimoReporte;
  final bool codigoVencido;

  GrupoAdmin({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.radioMetros,
    required this.direccion,
    required this.activo,
    required this.fechaCreacion,
    required this.creador,
    required this.creadorEmail,
    required this.totalMiembros,
    required this.totalReportes,
    required this.reportesPrivados,
    required this.ultimoReporte,
    required this.codigoVencido,
  });

  factory GrupoAdmin.desdeJson(Map<String, dynamic> json) {
    return GrupoAdmin(
      id: (json['id_grupo'] as num).toInt(),
      nombre: (json['nombre'] ?? '').toString(),
      descripcion: json['descripcion']?.toString(),
      radioMetros: (json['radio_metros'] as num?)?.toInt() ?? 0,
      direccion: json['direccion']?.toString(),
      activo: json['activo'] == true,
      fechaCreacion: DateTime.tryParse(json['fecha_creacion']?.toString() ?? ''),
      creador: (json['creador'] ?? '').toString().trim(),
      creadorEmail: (json['creador_email'] ?? '').toString(),
      totalMiembros: (json['total_miembros'] as num?)?.toInt() ?? 0,
      totalReportes: (json['total_reportes'] as num?)?.toInt() ?? 0,
      reportesPrivados: (json['reportes_privados'] as num?)?.toInt() ?? 0,
      ultimoReporte: DateTime.tryParse(json['ultimo_reporte']?.toString() ?? ''),
      codigoVencido: json['codigo_vencido'] == true,
    );
  }
}

/// Un reporte compartido en un grupo, para la hoja del panel.
class ReporteDeGrupoAdmin {
  final int id;
  final String categoria;
  final String categoriaCodigo;
  final String? colorHex;
  final String estado;
  final bool vencido;
  final bool soloGrupo;
  final String descripcion;
  final String? direccion;
  final DateTime? fechaPublicacion;
  final String autor;

  ReporteDeGrupoAdmin({
    required this.id,
    required this.categoria,
    required this.categoriaCodigo,
    required this.colorHex,
    required this.estado,
    required this.vencido,
    required this.soloGrupo,
    required this.descripcion,
    required this.direccion,
    required this.fechaPublicacion,
    required this.autor,
  });

  factory ReporteDeGrupoAdmin.desdeJson(Map<String, dynamic> json) {
    return ReporteDeGrupoAdmin(
      id: (json['id_reporte'] as num).toInt(),
      categoria: (json['categoria'] ?? '').toString(),
      categoriaCodigo: (json['categoria_codigo'] ?? '').toString(),
      colorHex: json['color_hex']?.toString(),
      estado: (json['estado'] ?? '').toString(),
      vencido: json['vencido'] == true,
      soloGrupo: json['visibilidad'] == 'GRUPO',
      descripcion: (json['descripcion'] ?? '').toString(),
      direccion: json['direccion']?.toString(),
      fechaPublicacion: DateTime.tryParse(json['fecha_publicacion']?.toString() ?? ''),
      autor: (json['autor'] ?? '').toString(),
    );
  }
}

/// Comentario de un reporte tal como lo ve el panel: en cualquier estado.
class ComentarioAdmin {
  final int id;
  final int? idPadre;
  final String? autor;
  final String contenido;
  final String? imagen;
  // PUBLICADO, OCULTO o ELIMINADO.
  final String estado;
  final DateTime? fechaCreacion;

  ComentarioAdmin({
    required this.id,
    required this.idPadre,
    required this.autor,
    required this.contenido,
    required this.imagen,
    required this.estado,
    required this.fechaCreacion,
  });

  factory ComentarioAdmin.desdeJson(Map<String, dynamic> json) {
    return ComentarioAdmin(
      id: (json['id_comentario'] as num).toInt(),
      idPadre: (json['id_comentario_padre'] as num?)?.toInt(),
      autor: json['autor']?.toString(),
      contenido: (json['contenido'] ?? '').toString(),
      imagen: json['imagen']?.toString(),
      estado: (json['estado'] ?? '').toString(),
      fechaCreacion: DateTime.tryParse(
        json['fecha_creacion']?.toString() ?? '',
      ),
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
      fechaCreacion: DateTime.tryParse(
        json['fecha_creacion']?.toString() ?? '',
      ),
      totalReportes: (json['total_reportes'] as num?)?.toInt() ?? 0,
      esAdmin: json['es_admin'] == true,
    );
  }
}

class NodoGrafo {
  /// "Tipo:id", p. ej. "Usuario:12". Es la misma clave que usan las aristas.
  final String clave;
  final String tipo;
  final String etiqueta;
  final Map<String, dynamic> datos;

  /// 0 = el elemento en foco, 1 = conectado directo, 2 = a dos pasos.
  final int anillo;

  /// Texto corto extra (p. ej. "12 acciones") en las listas del inicio.
  final String? detalle;

  NodoGrafo({
    required this.clave,
    required this.tipo,
    required this.etiqueta,
    required this.datos,
    this.anillo = 0,
    this.detalle,
  });

  int get id => (datos['id'] as num).toInt();
  String? get estado => datos['estado']?.toString();

  factory NodoGrafo.desdeJson(Map<String, dynamic> json) => NodoGrafo(
    clave: json['clave'].toString(),
    tipo: json['tipo'].toString(),
    etiqueta: (json['etiqueta'] ?? '').toString(),
    datos: (json['datos'] as Map?)?.cast<String, dynamic>() ?? {},
    anillo: (json['anillo'] as num?)?.toInt() ?? 0,
    detalle: json['detalle']?.toString(),
  );
}

class AristaGrafo {
  final String origen;
  final String destino;
  final String tipo;
  final Map<String, dynamic> datos;

  AristaGrafo({
    required this.origen,
    required this.destino,
    required this.tipo,
    required this.datos,
  });

  factory AristaGrafo.desdeJson(Map<String, dynamic> json) => AristaGrafo(
    origen: json['origen'].toString(),
    destino: json['destino'].toString(),
    tipo: json['tipo'].toString(),
    datos: (json['datos'] as Map?)?.cast<String, dynamic>() ?? {},
  );
}

/// Un elemento en foco con sus conexiones hasta 2 pasos.
class FocoGrafo {
  final String foco;
  final List<NodoGrafo> nodos;
  final List<AristaGrafo> aristas;

  FocoGrafo({required this.foco, required this.nodos, required this.aristas});

  NodoGrafo get nodoFoco => nodos.firstWhere((n) => n.clave == foco);

  factory FocoGrafo.desdeJson(Map<String, dynamic> json) => FocoGrafo(
    foco: json['foco'].toString(),
    nodos: [
      for (final n in (json['nodos'] as List? ?? []))
        NodoGrafo.desdeJson(n as Map<String, dynamic>),
    ],
    aristas: [
      for (final a in (json['aristas'] as List? ?? []))
        AristaGrafo.desdeJson(a as Map<String, dynamic>),
    ],
  );
}

class HallazgoGrafo {
  /// "alerta" (conviene revisarlo) o "info".
  final String nivel;
  final String texto;
  final NodoGrafo nodo;

  HallazgoGrafo({required this.nivel, required this.texto, required this.nodo});

  bool get esAlerta => nivel == 'alerta';
}

/// Portada del grafo: hallazgos y elementos desde donde empezar a explorar.
class InicioGrafo {
  final List<HallazgoGrafo> hallazgos;
  final List<NodoGrafo> reportes;
  final List<NodoGrafo> vecinos;
  final List<NodoGrafo> lugares;

  /// Fecha (texto ISO) de la última copia de MySQL a Neo4j, si hubo.
  final String? sincronizadoEn;

  InicioGrafo({
    required this.hallazgos,
    required this.reportes,
    required this.vecinos,
    required this.lugares,
    required this.sincronizadoEn,
  });

  static List<NodoGrafo> _nodos(dynamic lista) => [
    for (final n in (lista as List? ?? []))
      NodoGrafo.desdeJson(n as Map<String, dynamic>),
  ];

  factory InicioGrafo.desdeJson(Map<String, dynamic> json) => InicioGrafo(
    hallazgos: [
      for (final h in (json['hallazgos'] as List? ?? []))
        HallazgoGrafo(
          nivel: (h['nivel'] ?? 'info').toString(),
          texto: (h['texto'] ?? '').toString(),
          nodo: NodoGrafo.desdeJson(h['nodo'] as Map<String, dynamic>),
        ),
    ],
    reportes: _nodos(json['reportes']),
    vecinos: _nodos(json['vecinos']),
    lugares: _nodos(json['lugares']),
    sincronizadoEn: (json['sincronizacion'] as Map?)?['fecha']?.toString(),
  );
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

  Future<List<ComentarioAdmin>> comentarios(String token, int idReporte) async {
    final cuerpo = await _get(token, '/api/admin/reportes/$idReporte/comentarios');
    return [
      for (final c in cuerpo as List)
        ComentarioAdmin.desdeJson(c as Map<String, dynamic>),
    ];
  }

  /// [estado] es OCULTO para esconderlo de la app o PUBLICADO para restaurarlo.
  Future<void> cambiarEstadoComentario(
    String token,
    int idComentario,
    String estado,
  ) async {
    await _enviar('PATCH', token, '/api/admin/comentarios/$idComentario/estado', {
      'estado': estado,
    });
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
    await _enviar('PATCH', token, '/api/admin/reportes/$idReporte/estado', {
      'estado': estado,
      'motivo': ?motivo,
    });
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

  Future<List<GrupoAdmin>> grupos(
    String token, {
    String? buscar,
    bool? activo,
  }) async {
    final cuerpo = await _get(token, '/api/admin/grupos', {
      if (buscar != null && buscar.trim().isNotEmpty) 'buscar': buscar.trim(),
      if (activo != null) 'activo': '$activo',
    });
    return [
      for (final g in cuerpo as List)
        GrupoAdmin.desdeJson(g as Map<String, dynamic>),
    ];
  }

  Future<List<ReporteDeGrupoAdmin>> reportesDeGrupo(String token, int idGrupo) async {
    final cuerpo = await _get(token, '/api/admin/grupos/$idGrupo/reportes');
    return [
      for (final r in cuerpo as List)
        ReporteDeGrupoAdmin.desdeJson(r as Map<String, dynamic>),
    ];
  }

  Future<void> cambiarEstadoGrupo(String token, int idGrupo, bool activo) async {
    await _enviar('PATCH', token, '/api/admin/grupos/$idGrupo/estado', {
      'activo': activo,
    });
  }

  Future<InicioGrafo> inicioGrafo(String token) async {
    final cuerpo = await _get(token, '/api/admin/grafo/inicio');
    return InicioGrafo.desdeJson(cuerpo as Map<String, dynamic>);
  }

  /// [nodo] en el centro, con sus conexiones hasta 2 pasos.
  Future<FocoGrafo> focoGrafo(String token, NodoGrafo nodo) async {
    final cuerpo = await _get(
      token,
      '/api/admin/grafo/nodo/${nodo.tipo}/${nodo.id}',
    );
    return FocoGrafo.desdeJson(cuerpo as Map<String, dynamic>);
  }

  Future<void> sincronizarGrafo(String token) async {
    await _enviar('POST', token, '/api/admin/grafo/sincronizar', null);
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
