import 'package:rb_alertas/modelos/lectura_json.dart';

/// Elemento de la red de Neo4j: una calle, un sector, una categoría...
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

/// Relación entre dos nodos (p. ej. cuántos hechos de una categoría hubo en una calle).
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

  RedGrafo({required this.nodos, required this.aristas});

  factory RedGrafo.desdeJson(Map<String, dynamic> json) => RedGrafo(
    nodos: json.lista('nodos', NodoGrafo.desdeJson),
    aristas: json.lista('aristas', AristaGrafo.desdeJson),
  );
}

/// Cifras del análisis para la tarjeta del Resumen (últimos 30 días).
class ResumenGrafo {
  final int callesConHechos;
  final List<({String nombre, String? sector, int total, String tendencia})> callesTop;
  final int sectoresEnAlza;
  final int incidentesAbiertos;

  /// Fecha (texto ISO) de la última copia de MySQL a Neo4j, si hubo.
  final String? sincronizadoEn;

  ResumenGrafo({
    required this.callesConHechos,
    required this.callesTop,
    required this.sectoresEnAlza,
    required this.incidentesAbiertos,
    required this.sincronizadoEn,
  });

  factory ResumenGrafo.desdeJson(Map<String, dynamic> json) => ResumenGrafo(
    callesConHechos: json.entero('calles_con_hechos'),
    callesTop: json.lista(
      'calles_top',
      (c) => (
        nombre: c.texto('nombre'),
        sector: c.textoOpcional('sector'),
        total: c.entero('total'),
        tendencia: c.texto('tendencia', 'igual'),
      ),
    ),
    sectoresEnAlza: json.entero('sectores_en_alza'),
    incidentesAbiertos: json.entero('incidentes_abiertos'),
    sincronizadoEn: json.mapa('sincronizacion').textoOpcional('fecha'),
  );
}
