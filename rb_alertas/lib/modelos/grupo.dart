import 'package:rb_alertas/modelos/lectura_json.dart';
import 'package:rb_alertas/utilidades/formato.dart';

/// Grupo vecinal del que el usuario es miembro.
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

  String get radioLegible => textoRadio(radioMetros);

  String get miembrosTexto => totalMiembros == 1 ? '1 vecino' : '$totalMiembros vecinos';

  factory Grupo.desdeJson(Map<String, dynamic> json) => Grupo(
    id: json.entero('id_grupo'),
    nombre: json.texto('nombre'),
    descripcion: json.textoOpcional('descripcion'),
    latitud: json.decimal('latitud'),
    longitud: json.decimal('longitud'),
    radioMetros: json.entero('radio_metros', 1000),
    direccion: json.textoOpcional('direccion_referencia'),
    esAdmin: json.booleano('es_admin'),
    totalMiembros: json.entero('total_miembros', 1),
    ultimoReporte: json.fechaLocal('ultimo_reporte'),
    codigo: json.textoOpcional('codigo_invitacion'),
    codigoExpira: json.fechaLocal('codigo_expira'),
    codigoVencido: json.booleano('codigo_vencido'),
  );
}

/// Los grupos del usuario y los límites para crear uno nuevo.
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

  factory MisGrupos.desdeJson(Map<String, dynamic> json) => MisGrupos(
    grupos: json.lista('grupos', Grupo.desdeJson),
    maximo: json.entero('maximo', 5),
    puedeCrear: json.booleano('puede_crear'),
    radiosPermitidos: json.enteros('radios_permitidos', const [500, 1000, 2000]),
  );
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

  factory InvitacionGrupo.desdeJson(Map<String, dynamic> json) => InvitacionGrupo(
    nombre: json.texto('nombre'),
    descripcion: json.textoOpcional('descripcion'),
    radioMetros: json.entero('radio_metros', 1000),
    totalMiembros: json.entero('total_miembros', 1),
    yaEsMiembro: json.booleano('ya_es_miembro'),
  );
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

  factory MiembroGrupo.desdeJson(Map<String, dynamic> json) => MiembroGrupo(
    id: json.entero('id_miembro'),
    alias: json.texto('alias', 'Vecino'),
    esAdmin: json['rol'] == 'ADMIN',
    soyYo: json.booleano('soy_yo'),
    fechaUnion: json.fechaLocal('fecha_union'),
  );
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

  factory ReporteGrupo.desdeJson(Map<String, dynamic> json) => ReporteGrupo(
    id: json.entero('id_reporte'),
    autor: json.texto('autor', 'Un vecino'),
    esMio: json.booleano('es_mio'),
    soloGrupo: json['visibilidad'] == 'GRUPO',
    categoriaCodigo: json.texto('categoria_codigo'),
    categoria: json.texto('categoria', 'Incidente'),
    colorHex: json.textoOpcional('color_hex'),
    direccion: json.textoOpcional('direccion'),
    descripcion: json.texto('descripcion'),
    estado: json.texto('estado', 'PENDIENTE'),
    fecha: json.fechaLocal('fecha_publicacion') ?? json.fechaLocal('fecha_creacion'),
    totalComentarios: json.entero('total_comentarios'),
    imagen: json.textoOpcional('imagen'),
  );
}

/// Un grupo del usuario cuyo círculo contiene el lugar del incidente.
class GrupoEnPunto {
  final int id;
  final String nombre;

  GrupoEnPunto({required this.id, required this.nombre});

  factory GrupoEnPunto.desdeJson(Map<String, dynamic> json) =>
      GrupoEnPunto(id: json.entero('id_grupo'), nombre: json.texto('nombre'));
}
