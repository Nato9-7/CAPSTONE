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
  final double? latitud;
  final double? longitud;
  // Comentarios publicados y ocultos por moderación.
  final int comentarios;
  final int comentariosOcultos;

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
    this.latitud,
    this.longitud,
    this.comentarios = 0,
    this.comentariosOcultos = 0,
  });

  bool get tieneUbicacion => latitud != null && longitud != null;

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
      latitud: (json['latitud'] as num?)?.toDouble(),
      longitud: (json['longitud'] as num?)?.toDouble(),
      comentarios: (json['total_comentarios'] as num?)?.toInt() ?? 0,
      comentariosOcultos: (json['comentarios_ocultos'] as num?)?.toInt() ?? 0,
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

  /// Grupo de vecinos y reportes conectados entre sí (null si está aislado).
  final int? comunidad;

  NodoGrafo({
    required this.clave,
    required this.tipo,
    required this.etiqueta,
    required this.datos,
    this.anillo = 0,
    this.detalle,
    this.comunidad,
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
    comunidad: (json['comunidad'] as num?)?.toInt(),
  );
}

/// Un trozo de la red: lo que se dibuja en el explorador.
class RedGrafo {
  final List<NodoGrafo> nodos;
  final List<AristaGrafo> aristas;

  /// Solo en un camino: cuántos pasos hay entre los dos extremos.
  final int? pasos;

  RedGrafo({required this.nodos, required this.aristas, this.pasos});

  factory RedGrafo.desdeJson(Map<String, dynamic> json) => RedGrafo(
    nodos: [
      for (final n in (json['nodos'] as List? ?? []))
        NodoGrafo.desdeJson(n as Map<String, dynamic>),
    ],
    aristas: [
      for (final a in (json['aristas'] as List? ?? []))
        AristaGrafo.desdeJson(a as Map<String, dynamic>),
    ],
    pasos: (json['pasos'] as num?)?.toInt(),
  );
}

/// Un voto dentro de un grupo sospechoso: la evidencia de por qué lo es.
class VotoEvidencia {
  final String votante;
  final String autor;
  final int reporte;
  final String categoria;

  VotoEvidencia({
    required this.votante,
    required this.autor,
    required this.reporte,
    required this.categoria,
  });

  factory VotoEvidencia.desdeJson(Map<String, dynamic> json) => VotoEvidencia(
    votante: (json['votante'] ?? '').toString(),
    autor: (json['autor'] ?? '').toString(),
    reporte: (json['reporte'] as num?)?.toInt() ?? 0,
    categoria: (json['categoria'] ?? '').toString(),
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

/// Contadores de las tres secciones del grafo.
class ResumenGrafo {
  final int sospechosos;
  final int bajaReputacion;
  final int incidentesAbiertos;

  /// Fecha (texto ISO) de la última copia de MySQL a Neo4j, si hubo.
  final String? sincronizadoEn;

  ResumenGrafo({
    required this.sospechosos,
    required this.bajaReputacion,
    required this.incidentesAbiertos,
    required this.sincronizadoEn,
  });

  factory ResumenGrafo.desdeJson(Map<String, dynamic> json) => ResumenGrafo(
    sospechosos: (json['sospechosos'] as num?)?.toInt() ?? 0,
    bajaReputacion: (json['baja_reputacion'] as num?)?.toInt() ?? 0,
    incidentesAbiertos: (json['incidentes_abiertos'] as num?)?.toInt() ?? 0,
    sincronizadoEn: (json['sincronizacion'] as Map?)?['fecha']?.toString(),
  );
}

/// Grupo de cuentas que se confirman los reportes entre ellas.
class GrupoSospechoso {
  final NodoGrafo nodo;
  final List<NodoGrafo> miembros;

  /// Los votos entre los miembros (por qué el grupo es sospechoso).
  final List<VotoEvidencia> evidencia;

  /// Confirmaciones que dieron a vecinos de fuera del grupo.
  final int confirmacionesAfuera;

  GrupoSospechoso({
    required this.nodo,
    required this.miembros,
    this.evidencia = const [],
    this.confirmacionesAfuera = 0,
  });

  int get id => nodo.id;

  /// "ALTO" o "MEDIO".
  String get nivel => (nodo.datos['nivel'] ?? 'MEDIO').toString();

  /// Parte de las confirmaciones de sus miembros que se quedan dentro del grupo (0 a 1).
  double get reciprocidad => (nodo.datos['reciprocidad'] as num?)?.toDouble() ?? 0;

  int get confirmacionesInternas =>
      (nodo.datos['confirmaciones_internas'] as num?)?.toInt() ?? 0;

  factory GrupoSospechoso.desdeJson(Map<String, dynamic> json) => GrupoSospechoso(
    nodo: NodoGrafo.desdeJson(json),
    miembros: [
      for (final m in (json['miembros'] as List? ?? []))
        NodoGrafo.desdeJson(m as Map<String, dynamic>),
    ],
    evidencia: [
      for (final e in (json['evidencia'] as List? ?? []))
        VotoEvidencia.desdeJson(e as Map<String, dynamic>),
    ],
    confirmacionesAfuera: (json['confirmaciones_afuera'] as num?)?.toInt() ?? 0,
  );
}

/// Vecino con su reputación (0 a 100) y lo que la explica.
class VecinoReputacion {
  final NodoGrafo nodo;
  final int reportes;
  final bool sospechoso;

  VecinoReputacion({
    required this.nodo,
    required this.reportes,
    required this.sospechoso,
  });

  int _entero(String campo) => (nodo.datos[campo] as num?)?.toInt() ?? 0;

  int get puntaje => (nodo.datos['reputacion'] as num?)?.round() ?? 50;
  int get confirmaciones => _entero('confirmaciones_recibidas');
  int get desmentidos => _entero('desmentidos_recibidos');
  int get buenos => _entero('reportes_buenos');
  int get descartados => _entero('reportes_descartados');

  factory VecinoReputacion.desdeJson(Map<String, dynamic> json) => VecinoReputacion(
    nodo: NodoGrafo.desdeJson(json),
    reportes: (json['reportes'] as num?)?.toInt() ?? 0,
    sospechoso: json['sospechoso'] == true,
  );
}

/// Varios reportes del mismo hecho, juntados en un incidente.
class IncidenteGrafo {
  final NodoGrafo nodo;
  final String? lugar;
  final int vigentes;
  final List<NodoGrafo> reportes;

  IncidenteGrafo({
    required this.nodo,
    required this.lugar,
    required this.vigentes,
    required this.reportes,
  });

  /// El incidente se identifica con el id de su primer reporte.
  int get id => nodo.id;
  String get categoria => (nodo.datos['categoria'] ?? '').toString();
  DateTime? get ultimo => DateTime.tryParse((nodo.datos['fin'] ?? '').toString());

  factory IncidenteGrafo.desdeJson(Map<String, dynamic> json) => IncidenteGrafo(
    nodo: NodoGrafo.desdeJson(json),
    lugar: json['lugar']?.toString(),
    vigentes: (json['vigentes'] as num?)?.toInt() ?? 0,
    reportes: [
      for (final r in (json['reportes'] as List? ?? []))
        NodoGrafo.desdeJson(r as Map<String, dynamic>),
    ],
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

  /// Un reporte con sus datos de moderación, o null si ya no existe.
  Future<ReporteAdmin?> reporte(String token, int idReporte) async {
    final cuerpo = await _get(token, '/api/admin/reportes', {
      'id_reporte': '$idReporte',
    });
    final lista = cuerpo as List;
    return lista.isEmpty
        ? null
        : ReporteAdmin.desdeJson(lista.first as Map<String, dynamic>);
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

  /// Elimina el reporte para siempre (con sus votos, comentarios y fotos).
  Future<void> eliminarReporte(String token, int idReporte) async {
    await _enviar('DELETE', token, '/api/admin/reportes/$idReporte', null);
  }

  /// Elimina un comentario (y su foto). No se puede deshacer.
  Future<void> eliminarComentario(String token, int idComentario) async {
    await _enviar('DELETE', token, '/api/admin/comentarios/$idComentario', null);
  }

  /// Suspende a quien escribió el comentario (sin revelar quién es).
  Future<void> suspenderAutorComentario(String token, int idComentario) async {
    await _enviar(
      'POST',
      token,
      '/api/admin/comentarios/$idComentario/suspender-autor',
      null,
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

  Future<ResumenGrafo> resumenGrafo(String token) async {
    final cuerpo = await _get(token, '/api/admin/grafo/resumen');
    return ResumenGrafo.desdeJson(cuerpo as Map<String, dynamic>);
  }

  Future<List<GrupoSospechoso>> cuentasSospechosas(String token) async {
    final cuerpo = await _get(token, '/api/admin/grafo/sospechosos');
    return [
      for (final g in cuerpo as List)
        GrupoSospechoso.desdeJson(g as Map<String, dynamic>),
    ];
  }

  /// Suspende todas las cuentas del grupo; devuelve los ids suspendidos
  /// (para poder deshacerlo reactivándolas).
  Future<List<int>> suspenderGrupoSospechoso(String token, int idGrupo) async {
    final cuerpo = await _enviar(
      'POST',
      token,
      '/api/admin/grafo/sospechosos/$idGrupo/suspender',
      null,
    );
    return [
      for (final id in ((cuerpo as Map?)?['ids'] as List? ?? []))
        (id as num).toInt(),
    ];
  }

  /// La red del explorador. [modo]: "vecinos" (quién apoya a quién) o
  /// "completa" (vecinos y reportes con las [capas] pedidas). [dias] limita
  /// a la actividad reciente; null es toda la historia.
  Future<RedGrafo> red(
    String token, {
    String modo = 'vecinos',
    int? dias,
    Set<String> capas = const {},
  }) async {
    final cuerpo = await _get(token, '/api/admin/grafo/red', {
      'modo': modo,
      if (dias != null) 'dias': '$dias',
      'capas': capas.join(','),
    });
    return RedGrafo.desdeJson(cuerpo as Map<String, dynamic>);
  }

  Future<List<NodoGrafo>> buscarEnGrafo(String token, String texto) async {
    final cuerpo = await _get(token, '/api/admin/grafo/buscar', {'q': texto});
    return [
      for (final n in cuerpo as List)
        NodoGrafo.desdeJson(n as Map<String, dynamic>),
    ];
  }

  /// El camino más corto entre dos elementos (lo calcula Neo4j).
  Future<RedGrafo> camino(String token, NodoGrafo desde, NodoGrafo hasta) async {
    final cuerpo = await _get(token, '/api/admin/grafo/camino', {
      'desde': desde.clave,
      'hasta': hasta.clave,
    });
    return RedGrafo.desdeJson(cuerpo as Map<String, dynamic>);
  }

  /// [orden]: "baja" (menos confiables primero) o "alta".
  Future<List<VecinoReputacion>> reputacion(String token, {String orden = 'baja'}) async {
    final cuerpo = await _get(token, '/api/admin/grafo/reputacion', {'orden': orden});
    return [
      for (final v in cuerpo as List)
        VecinoReputacion.desdeJson(v as Map<String, dynamic>),
    ];
  }

  Future<List<IncidenteGrafo>> incidentes(String token) async {
    final cuerpo = await _get(token, '/api/admin/grafo/incidentes');
    return [
      for (final i in cuerpo as List)
        IncidenteGrafo.desdeJson(i as Map<String, dynamic>),
    ];
  }

  /// Aplica [estado] (VALIDADO, RESUELTO o DESCARTADO) a todos los reportes del incidente.
  Future<void> cambiarEstadoIncidente(
    String token,
    int idIncidente,
    String estado, {
    String? motivo,
  }) async {
    await _enviar('PATCH', token, '/api/admin/incidentes/$idIncidente/estado', {
      'estado': estado,
      'motivo': ?motivo,
    });
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

  /// Devuelve el cuerpo de la respuesta ya decodificado (o null si viene vacío).
  Future<dynamic> _enviar(
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
    if (respuesta.statusCode == 200) {
      return respuesta.bodyBytes.isEmpty ? null : _json(respuesta);
    }
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
