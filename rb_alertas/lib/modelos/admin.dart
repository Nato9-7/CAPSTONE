import 'package:rb_alertas/modelos/lectura_json.dart';

/// Cifras del inicio del panel de administración.
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

  static Map<String, int> _conteo(Map<String, dynamic> json) => {
    for (final e in json.entries) e.key: (e.value as num?)?.toInt() ?? 0,
  };

  factory ResumenAdmin.desdeJson(Map<String, dynamic> json) => ResumenAdmin(
    usuariosPorEstado: _conteo(json.mapa('usuarios_por_estado')),
    usuariosNuevos7d: json.entero('usuarios_nuevos_7d'),
    reportesPorEstado: _conteo(json.mapa('reportes_por_estado')),
    reportes24h: json.entero('reportes_24h'),
    reportes7d: json.entero('reportes_7d'),
    reportesVigentes: json.entero('reportes_vigentes'),
    categorias30d: json.lista(
      'categorias_30d',
      (c) => (nombre: c.texto('nombre'), colorHex: c.textoOpcional('color_hex'), total: c.entero('total')),
    ),
  );
}

/// Reporte con los datos que necesita la moderación.
class ReporteAdmin {
  final int id;
  final String categoria;
  final String categoriaCodigo;
  final String? colorHex;

  /// Estado efectivo: un pendiente o validado cuya vigencia terminó llega como EXPIRADO.
  final String estado;
  final String descripcion;
  final String? direccion;
  final String? zona;
  final DateTime? fechaCreacion;
  final int confirmaciones;
  final int desmentidos;
  final String? imagen;
  final String autor;

  /// Estados a los que se puede llevar desde el panel (los decide la API).
  final List<String> acciones;
  final int denunciasPendientes;

  /// Privado de un grupo vecinal: no sale en el mapa público.
  final bool soloGrupo;
  final double? latitud;
  final double? longitud;

  /// Comentarios publicados y ocultos por moderación.
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
    required this.confirmaciones,
    required this.desmentidos,
    required this.imagen,
    required this.autor,
    this.acciones = const [],
    this.denunciasPendientes = 0,
    this.soloGrupo = false,
    this.latitud,
    this.longitud,
    this.comentarios = 0,
    this.comentariosOcultos = 0,
  });

  bool get tieneUbicacion => latitud != null && longitud != null;

  factory ReporteAdmin.desdeJson(Map<String, dynamic> json) => ReporteAdmin(
    id: json.entero('id_reporte'),
    categoria: json.texto('categoria'),
    categoriaCodigo: json.texto('categoria_codigo'),
    colorHex: json.textoOpcional('color_hex'),
    estado: json.texto('estado'),
    descripcion: json.texto('descripcion'),
    direccion: json.textoOpcional('direccion'),
    zona: json.textoOpcional('zona'),
    fechaCreacion: json.fecha('fecha_creacion'),
    confirmaciones: json.entero('total_confirmaciones'),
    desmentidos: json.entero('total_desmentidos'),
    imagen: json.textoOpcional('imagen'),
    autor: json.texto('autor'),
    acciones: json.textos('acciones'),
    denunciasPendientes: json.entero('denuncias_pendientes'),
    soloGrupo: json['visibilidad'] == 'GRUPO',
    latitud: json.decimalOpcional('latitud'),
    longitud: json.decimalOpcional('longitud'),
    comentarios: json.entero('total_comentarios'),
    comentariosOcultos: json.entero('comentarios_ocultos'),
  );
}

/// Una página del listado de reportes del panel, con cuántos hay en cada estado.
class PaginaReportes {
  final List<ReporteAdmin> reportes;

  /// Total con los filtros aplicados (para saber si hay más páginas).
  final int total;
  final int pagina;
  final int porPagina;

  /// Cuántos hay en cada estado con los mismos filtros, para los contadores.
  final Map<String, int> conteos;

  PaginaReportes({
    required this.reportes,
    required this.total,
    required this.pagina,
    required this.porPagina,
    required this.conteos,
  });

  bool get hayMas => pagina * porPagina < total;

  factory PaginaReportes.desdeJson(Map<String, dynamic> json) => PaginaReportes(
    reportes: json.lista('reportes', ReporteAdmin.desdeJson),
    total: json.entero('total'),
    pagina: json.entero('pagina', 1),
    porPagina: json.entero('por_pagina', 25),
    conteos: ResumenAdmin._conteo(json.mapa('conteos')),
  );
}

/// Filtros del listado de reportes del panel.
class FiltroReportes {
  final String? estado;
  final String? texto;
  final String? categoria;
  final DateTime? desde;

  /// "prioridad" deja primero lo que más necesita revisión.
  final String orden;

  const FiltroReportes({this.estado, this.texto, this.categoria, this.desde, this.orden = 'recientes'});

  FiltroReportes copiar({
    String? Function()? estado,
    String? Function()? texto,
    String? Function()? categoria,
    DateTime? Function()? desde,
    String? orden,
  }) => FiltroReportes(
    estado: estado != null ? estado() : this.estado,
    texto: texto != null ? texto() : this.texto,
    categoria: categoria != null ? categoria() : this.categoria,
    desde: desde != null ? desde() : this.desde,
    orden: orden ?? this.orden,
  );

  bool get tieneFiltrosExtra => (texto?.isNotEmpty ?? false) || categoria != null || desde != null;
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

  factory GrupoAdmin.desdeJson(Map<String, dynamic> json) => GrupoAdmin(
    id: json.entero('id_grupo'),
    nombre: json.texto('nombre'),
    descripcion: json.textoOpcional('descripcion'),
    radioMetros: json.entero('radio_metros'),
    direccion: json.textoOpcional('direccion'),
    activo: json.booleano('activo'),
    fechaCreacion: json.fecha('fecha_creacion'),
    creador: json.texto('creador').trim(),
    creadorEmail: json.texto('creador_email'),
    totalMiembros: json.entero('total_miembros'),
    totalReportes: json.entero('total_reportes'),
    reportesPrivados: json.entero('reportes_privados'),
    ultimoReporte: json.fecha('ultimo_reporte'),
    codigoVencido: json.booleano('codigo_vencido'),
  );
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

  factory ReporteDeGrupoAdmin.desdeJson(Map<String, dynamic> json) => ReporteDeGrupoAdmin(
    id: json.entero('id_reporte'),
    categoria: json.texto('categoria'),
    categoriaCodigo: json.texto('categoria_codigo'),
    colorHex: json.textoOpcional('color_hex'),
    estado: json.texto('estado'),
    vencido: json.booleano('vencido'),
    soloGrupo: json['visibilidad'] == 'GRUPO',
    descripcion: json.texto('descripcion'),
    direccion: json.textoOpcional('direccion'),
    fechaPublicacion: json.fecha('fecha_publicacion'),
    autor: json.texto('autor'),
  );

  /// Un solo estado: un pendiente o validado vencido se muestra como expirado.
  String get estadoVisible => vencido && (estado == 'PENDIENTE' || estado == 'VALIDADO') ? 'EXPIRADO' : estado;
}

/// Comentario de un reporte tal como lo ve el panel: en cualquier estado.
class ComentarioAdmin {
  final int id;
  final int? idPadre;
  final String? autor;
  final String contenido;
  final String? imagen;

  /// PUBLICADO, OCULTO o ELIMINADO.
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

  factory ComentarioAdmin.desdeJson(Map<String, dynamic> json) => ComentarioAdmin(
    id: json.entero('id_comentario'),
    idPadre: json.enteroOpcional('id_comentario_padre'),
    autor: json.textoOpcional('autor'),
    contenido: json.texto('contenido'),
    imagen: json.textoOpcional('imagen'),
    estado: json.texto('estado'),
    fechaCreacion: json.fecha('fecha_creacion'),
  );
}

/// Denuncias de los vecinos sobre un mismo reporte o comentario, juntas.
/// Quién denunció no llega al panel.
class DenunciaAdmin {
  final bool esComentario;
  final int idReporte;
  final int? idComentario;
  final int total;
  final List<String> motivos;
  final List<String> detalles;
  final DateTime? ultima;
  final String categoria;
  final String categoriaCodigo;
  final String? colorHex;
  final String estadoReporte;
  final String descripcion;
  final String? contenido;
  final String? estadoComentario;

  DenunciaAdmin({
    required this.esComentario,
    required this.idReporte,
    required this.idComentario,
    required this.total,
    required this.motivos,
    required this.detalles,
    required this.ultima,
    required this.categoria,
    required this.categoriaCodigo,
    required this.colorHex,
    required this.estadoReporte,
    required this.descripcion,
    required this.contenido,
    required this.estadoComentario,
  });

  factory DenunciaAdmin.desdeJson(Map<String, dynamic> json) => DenunciaAdmin(
    esComentario: json['tipo'] == 'COMENTARIO',
    idReporte: json.entero('id_reporte'),
    idComentario: json.enteroOpcional('id_comentario'),
    total: json.entero('total'),
    motivos: json.textos('motivos'),
    detalles: json.textos('detalles'),
    ultima: json.fecha('ultima'),
    categoria: json.texto('categoria'),
    categoriaCodigo: json.texto('categoria_codigo'),
    colorHex: json.textoOpcional('color_hex'),
    estadoReporte: json.texto('estado_reporte'),
    descripcion: json.texto('descripcion'),
    contenido: json.textoOpcional('contenido'),
    estadoComentario: json.textoOpcional('estado_comentario'),
  );
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

  /// Correo, RUT y teléfono llegan parcialmente ocultos (p. ej. "2098••••-8");
  /// [UsuarioAdmin.conContacto] los reemplaza por los completos al pedirlos.
  UsuarioAdmin conContacto(({String email, String? rut, String? telefono}) c) => UsuarioAdmin(
    id: id,
    nombres: nombres,
    apellidos: apellidos,
    email: c.email,
    rut: c.rut,
    telefono: c.telefono,
    estado: estado,
    emailVerificado: emailVerificado,
    fechaCreacion: fechaCreacion,
    totalReportes: totalReportes,
    esAdmin: esAdmin,
  );

  factory UsuarioAdmin.desdeJson(Map<String, dynamic> json) => UsuarioAdmin(
    id: json.entero('id_usuario'),
    nombres: json.texto('nombres'),
    apellidos: json.texto('apellidos'),
    email: json.texto('email'),
    rut: json.textoOpcional('rut'),
    telefono: json.textoOpcional('telefono'),
    estado: json.texto('estado'),
    emailVerificado: json.booleano('email_verificado'),
    fechaCreacion: json.fecha('fecha_creacion'),
    totalReportes: json.entero('total_reportes'),
    esAdmin: json.booleano('es_admin'),
  );
}
