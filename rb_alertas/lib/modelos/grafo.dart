import 'package:rb_alertas/modelos/lectura_json.dart';

/// Elemento de la red de Neo4j: un vecino, un reporte, un lugar...
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

  int get id => datos.entero('id');
  String? get estado => datos.textoOpcional('estado');

  factory NodoGrafo.desdeJson(Map<String, dynamic> json) => NodoGrafo(
    clave: json.texto('clave'),
    tipo: json.texto('tipo'),
    etiqueta: json.texto('etiqueta'),
    datos: json.mapa('datos'),
    anillo: json.entero('anillo'),
    detalle: json.textoOpcional('detalle'),
    comunidad: json.enteroOpcional('comunidad'),
  );
}

/// Relación entre dos nodos (quién apoya a quién, qué reporte está en qué lugar...).
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
    origen: json.texto('origen'),
    destino: json.texto('destino'),
    tipo: json.texto('tipo'),
    datos: json.mapa('datos'),
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
    nodos: json.lista('nodos', NodoGrafo.desdeJson),
    aristas: json.lista('aristas', AristaGrafo.desdeJson),
    pasos: json.enteroOpcional('pasos'),
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
    foco: json.texto('foco'),
    nodos: json.lista('nodos', NodoGrafo.desdeJson),
    aristas: json.lista('aristas', AristaGrafo.desdeJson),
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
    sospechosos: json.entero('sospechosos'),
    bajaReputacion: json.entero('baja_reputacion'),
    incidentesAbiertos: json.entero('incidentes_abiertos'),
    sincronizadoEn: json.mapa('sincronizacion').textoOpcional('fecha'),
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
    votante: json.texto('votante'),
    autor: json.texto('autor'),
    reporte: json.entero('reporte'),
    categoria: json.texto('categoria'),
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
  String get nivel => nodo.datos.texto('nivel', 'MEDIO');

  /// Parte de las confirmaciones de sus miembros que se quedan dentro del grupo (0 a 1).
  double get reciprocidad => nodo.datos.decimal('reciprocidad');

  int get confirmacionesInternas => nodo.datos.entero('confirmaciones_internas');

  factory GrupoSospechoso.desdeJson(Map<String, dynamic> json) => GrupoSospechoso(
    nodo: NodoGrafo.desdeJson(json),
    miembros: json.lista('miembros', NodoGrafo.desdeJson),
    evidencia: json.lista('evidencia', VotoEvidencia.desdeJson),
    confirmacionesAfuera: json.entero('confirmaciones_afuera'),
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

  int get puntaje => (nodo.datos['reputacion'] as num?)?.round() ?? 50;
  int get confirmaciones => nodo.datos.entero('confirmaciones_recibidas');
  int get desmentidos => nodo.datos.entero('desmentidos_recibidos');
  int get buenos => nodo.datos.entero('reportes_buenos');
  int get descartados => nodo.datos.entero('reportes_descartados');

  factory VecinoReputacion.desdeJson(Map<String, dynamic> json) => VecinoReputacion(
    nodo: NodoGrafo.desdeJson(json),
    reportes: json.entero('reportes'),
    sospechoso: json.booleano('sospechoso'),
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
  String get categoria => nodo.datos.texto('categoria');
  DateTime? get ultimo => nodo.datos.fecha('fin');

  factory IncidenteGrafo.desdeJson(Map<String, dynamic> json) => IncidenteGrafo(
    nodo: NodoGrafo.desdeJson(json),
    lugar: json.textoOpcional('lugar'),
    vigentes: json.entero('vigentes'),
    reportes: json.lista('reportes', NodoGrafo.desdeJson),
  );
}
