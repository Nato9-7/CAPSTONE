import 'package:rb_alertas/config/api_config.dart';
import 'package:rb_alertas/modelos/lectura_json.dart';

/// Comentario de un reporte. Los comentarios raíz traen sus respuestas.
class Comentario {
  final int id;
  final int? idPadre;

  /// PUBLICADO, o ELIMINADO/OCULTO si solo queda el marcador del hilo.
  final String estado;

  /// Alias de suricata (lo arma la API); null en un marcador.
  final String? autor;
  final bool esAutorReporte;
  final bool esMio;
  final String? contenido;
  final String? imagen;
  final DateTime? fechaCreacion;
  final List<Comentario> respuestas;

  Comentario({
    required this.id,
    required this.idPadre,
    required this.estado,
    required this.autor,
    required this.esAutorReporte,
    required this.esMio,
    required this.contenido,
    required this.imagen,
    required this.fechaCreacion,
    required this.respuestas,
  });

  bool get publicado => estado == 'PUBLICADO';

  /// URL completa de la foto adjunta, o null si no trae.
  String? get imagenUrl =>
      imagen == null || imagen!.isEmpty ? null : ApiConfig.urlArchivo(imagen!);

  factory Comentario.desdeJson(Map<String, dynamic> json) => Comentario(
    id: json.entero('id_comentario'),
    idPadre: json.enteroOpcional('id_comentario_padre'),
    estado: json.texto('estado'),
    autor: json.textoOpcional('autor'),
    esAutorReporte: json.booleano('es_autor_reporte'),
    esMio: json.booleano('es_mio'),
    contenido: json.textoOpcional('contenido'),
    imagen: json.textoOpcional('imagen'),
    fechaCreacion: json.fecha('fecha_creacion'),
    respuestas: json.lista('respuestas', Comentario.desdeJson),
  );
}

/// Respuesta de GET /api/reportes/{id}/comentarios.
class ConversacionReporte {
  /// Comentarios visibles (raíz y respuestas), sin contar los marcadores.
  final int total;

  /// false si el reporte ya no está vigente: la conversación queda de solo lectura.
  final bool puedeComentar;
  final List<Comentario> comentarios;

  ConversacionReporte({
    required this.total,
    required this.puedeComentar,
    required this.comentarios,
  });

  factory ConversacionReporte.desdeJson(Map<String, dynamic> json) => ConversacionReporte(
    total: json.entero('total'),
    puedeComentar: json.booleano('puede_comentar'),
    comentarios: json.lista('comentarios', Comentario.desdeJson),
  );
}
