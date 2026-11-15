import 'dart:typed_data';

import 'package:rb_alertas/config/api_config.dart';
import 'package:rb_alertas/modelos/lectura_json.dart';

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

  factory CategoriaIncidente.desdeJson(Map<String, dynamic> json) => CategoriaIncidente(
    id: json.entero('id_categoria'),
    codigo: json.texto('codigo'),
    nombre: json.texto('nombre'),
    colorHex: json.textoOpcional('color_hex'),
  );
}

/// Reporte vigente tal como se dibuja en el mapa.
class ReporteMapa {
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

  /// Reportes del mismo hecho que la API juntó en este incidente (1 si es único).
  final int totalReportes;

  ReporteMapa({
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
    this.totalReportes = 1,
  });

  factory ReporteMapa.desdeJson(Map<String, dynamic> json) => ReporteMapa(
    id: json.entero('id_reporte'),
    categoriaCodigo: json.texto('categoria_codigo'),
    categoria: json.texto('categoria'),
    colorHex: json.textoOpcional('color_hex'),
    latitud: json.decimal('latitud'),
    longitud: json.decimal('longitud'),
    direccion: json.textoOpcional('direccion'),
    descripcion: json.texto('descripcion'),
    estado: json.texto('estado'),
    fechaCreacion: json.fecha('fecha_creacion'),
    totalReportes: json.entero('total_reportes', 1),
  );
}

/// Reporte vigente cerca de un punto, con la distancia que calcula la API.
class ReporteCercano {
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
  final double distanciaMetros;
  final int confirmaciones;

  /// Reportes del mismo hecho que la API juntó en este incidente (1 si es único).
  final int totalReportes;

  ReporteCercano({
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
    required this.distanciaMetros,
    required this.confirmaciones,
    this.totalReportes = 1,
  });

  factory ReporteCercano.desdeJson(Map<String, dynamic> json) => ReporteCercano(
    id: json.entero('id_reporte'),
    categoriaCodigo: json.texto('categoria_codigo'),
    categoria: json.texto('categoria'),
    colorHex: json.textoOpcional('color_hex'),
    latitud: json.decimal('latitud'),
    longitud: json.decimal('longitud'),
    direccion: json.textoOpcional('direccion'),
    descripcion: json.texto('descripcion'),
    estado: json.texto('estado'),
    fechaCreacion: json.fecha('fecha_creacion'),
    distanciaMetros: json.decimal('distancia_metros'),
    confirmaciones: json.entero('total_confirmaciones'),
    totalReportes: json.entero('total_reportes', 1),
  );
}

/// Respuesta de /api/reportes/cercanos: los reportes y el radio que aplicó la
/// API (el de las preferencias del usuario, o el estándar si no tiene).
class AlertasCercanas {
  final int radioMetros;
  final List<ReporteCercano> reportes;

  AlertasCercanas({required this.radioMetros, required this.reportes});

  factory AlertasCercanas.desdeJson(Map<String, dynamic> json) => AlertasCercanas(
    radioMetros: json.entero('radio_metros'),
    reportes: json.lista('reportes', ReporteCercano.desdeJson),
  );
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

  factory MiReporte.desdeJson(Map<String, dynamic> json) => MiReporte(
    id: json.entero('id_reporte'),
    categoriaCodigo: json.texto('categoria_codigo'),
    categoria: json.texto('categoria'),
    colorHex: json.textoOpcional('color_hex'),
    descripcion: json.texto('descripcion'),
    direccion: json.textoOpcional('direccion'),
    zona: json.textoOpcional('zona'),
    estado: switch (json.texto('estado_visual')) {
      'ACTIVA' => EstadoMiReporte.activa,
      'RESUELTA' => EstadoMiReporte.resuelta,
      'DESCARTADA' => EstadoMiReporte.descartada,
      // Un estado desconocido se muestra como no vigente, para no dar por
      // activo un reporte que ya no lo está.
      _ => EstadoMiReporte.vencida,
    },
    fechaCreacion: json.fecha('fecha_creacion'),
    imagen: json.textoOpcional('imagen'),
    confirmaciones: json.entero('total_confirmaciones'),
    desmentidos: json.entero('total_desmentidos'),
  );
}

/// Institución a la que se puede llamar por un tipo de incidente.
class EntidadEmergencia {
  final String nombre;
  final String tipo;
  final String telefono;

  EntidadEmergencia({required this.nombre, required this.tipo, required this.telefono});

  factory EntidadEmergencia.desdeJson(Map<String, dynamic> json) => EntidadEmergencia(
    nombre: json.texto('nombre'),
    tipo: json.texto('tipo'),
    telefono: json.texto('telefono'),
  );
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

  factory ResumenVotos.desdeJson(Map<String, dynamic> json) => ResumenVotos(
    confirmaciones: json.entero('total_confirmaciones'),
    desmentidos: json.entero('total_desmentidos'),
    estado: json.texto('estado'),
    miVoto: TipoVoto.desdeApi(json['mi_voto']),
  );
}

/// Otro reporte del mismo hecho, visto desde el detalle.
class ReporteDelIncidente {
  final int id;
  final String autor;
  final String descripcion;
  final DateTime? fechaCreacion;

  /// true para el reporte que se está mirando.
  final bool esEste;

  ReporteDelIncidente({
    required this.id,
    required this.autor,
    required this.descripcion,
    required this.fechaCreacion,
    required this.esEste,
  });

  factory ReporteDelIncidente.desdeJson(Map<String, dynamic> json) => ReporteDelIncidente(
    id: json.entero('id_reporte'),
    autor: json.texto('autor'),
    descripcion: json.texto('descripcion'),
    fechaCreacion: json.fecha('fecha_creacion'),
    esEste: json.booleano('es_este'),
  );
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

  /// true si quien consulta (según el token de la sesión) creó el reporte.
  final bool esAutor;
  final List<String> imagenes;
  final EntidadEmergencia? emergencia;
  final int confirmaciones;
  final int desmentidos;
  final TipoVoto? miVoto;

  /// Comentarios publicados (el número del botón de la tarjeta del mapa).
  final int totalComentarios;

  /// Privado de un grupo: solo lo ven el autor y los vecinos del grupo.
  final bool soloGrupo;

  /// Todos los reportes del mismo hecho (incluido este), del primero al último.
  final List<ReporteDelIncidente> reportesDelIncidente;

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
    required this.totalComentarios,
    this.soloGrupo = false,
    this.reportesDelIncidente = const [],
  });

  /// Otros vecinos reportaron lo mismo: el reporte es parte de un incidente mayor.
  bool get esIncidenteAgrupado => reportesDelIncidente.length > 1;

  bool get activo => estado == 'PENDIENTE' || estado == 'VALIDADO';

  factory DetalleReporte.desdeJson(Map<String, dynamic> json) {
    final emergencia = json['emergencia'];
    return DetalleReporte(
      id: json.entero('id_reporte'),
      categoriaCodigo: json.texto('categoria_codigo'),
      categoria: json.texto('categoria'),
      colorHex: json.textoOpcional('color_hex'),
      latitud: json.decimal('latitud'),
      longitud: json.decimal('longitud'),
      direccion: json.textoOpcional('direccion'),
      descripcion: json.texto('descripcion'),
      estado: json.texto('estado'),
      fechaCreacion: json.fecha('fecha_creacion'),
      autor: json.texto('autor'),
      esAutor: json.booleano('es_autor'),
      imagenes: json.textos('imagenes'),
      emergencia: emergencia is Map<String, dynamic> ? EntidadEmergencia.desdeJson(emergencia) : null,
      confirmaciones: json.entero('total_confirmaciones'),
      desmentidos: json.entero('total_desmentidos'),
      miVoto: TipoVoto.desdeApi(json['mi_voto']),
      totalComentarios: json.entero('total_comentarios'),
      soloGrupo: json['visibilidad'] == 'GRUPO',
      reportesDelIncidente: json.mapa('incidente').lista('reportes', ReporteDelIncidente.desdeJson),
    );
  }
}

/// Foto o video que se adjunta a un reporte o comentario.
class Evidencia {
  final String nombreArchivo;
  final Uint8List bytes;

  Evidencia({required this.nombreArchivo, required this.bytes});
}
