import 'package:rb_alertas/modelos/lectura_json.dart';

/// Tendencia de un lugar o del total frente al período anterior.
enum Tendencia {
  nueva,
  sube,
  baja,
  igual;

  static Tendencia desdeApi(String? valor) =>
      Tendencia.values.firstWhere((t) => t.name == valor, orElse: () => Tendencia.igual);
}

/// Categoría para filtros y leyendas.
typedef CategoriaAnalisis = ({String codigo, String nombre, String? color});

CategoriaAnalisis _categoria(Map<String, dynamic> c) =>
    (codigo: c.texto('codigo'), nombre: c.texto('nombre'), color: c.textoOpcional('color'));

/// Hechos de un día, con su desglose por código de categoría.
class DiaAnalisis {
  final DateTime dia;
  final int total;
  final Map<String, int> porCategoria;

  DiaAnalisis({required this.dia, required this.total, required this.porCategoria});

  factory DiaAnalisis.desdeJson(Map<String, dynamic> json) => DiaAnalisis(
    dia: DateTime.parse(json.texto('dia')),
    total: json.entero('total'),
    porCategoria: {for (final e in json.mapa('por_categoria').entries) e.key: (e.value as num?)?.toInt() ?? 0},
  );
}

/// Serie de hechos por día del período y su comparación con el anterior.
class SerieDiaria {
  final List<DiaAnalisis> dias;
  final int total;
  final int anterior;
  final Tendencia tendencia;
  final double? variacion;
  final double promedioDiario;
  final ({DateTime dia, int total})? diaPico;
  final List<CategoriaAnalisis> categorias;
  final DateTime? sincronizadoEn;

  SerieDiaria({
    required this.dias,
    required this.total,
    required this.anterior,
    required this.tendencia,
    required this.variacion,
    required this.promedioDiario,
    required this.diaPico,
    required this.categorias,
    required this.sincronizadoEn,
  });

  factory SerieDiaria.desdeJson(Map<String, dynamic> json) {
    final pico = json['dia_pico'] as Map<String, dynamic>?;
    return SerieDiaria(
      dias: json.lista('dias', DiaAnalisis.desdeJson),
      total: json.entero('total'),
      anterior: json.entero('anterior'),
      tendencia: Tendencia.desdeApi(json.textoOpcional('tendencia')),
      variacion: json.decimalOpcional('variacion'),
      promedioDiario: json.decimal('promedio_diario'),
      diaPico: pico == null ? null : (dia: DateTime.parse(pico.texto('dia')), total: pico.entero('total')),
      categorias: json.lista('categorias', _categoria),
      sincronizadoEn: json.mapa('sincronizacion').fechaLocal('fecha'),
    );
  }
}

/// Tramo de calle (la calle dentro de un sector) con sus hechos en el período.
class CalleAnalisis {
  final int id;
  final String nombre;
  final String? comuna;

  /// Sector (localidad) del tramo; null si el punto quedó fuera de las localidades conocidas.
  final String? sector;
  final int? idSector;

  /// Puesto del tramo entre las calles de su sector (1 = la con más hechos) y cuántas hay.
  final int? puestoEnSector;
  final int? callesEnSector;
  final double? latitud;
  final double? longitud;
  final int total;
  final int reportes;
  final int anterior;
  final Tendencia tendencia;
  final double? variacion;
  final DateTime? ultimo;
  final List<({CategoriaAnalisis categoria, int total})> porCategoria;

  CalleAnalisis({
    required this.id,
    required this.nombre,
    required this.comuna,
    this.sector,
    this.idSector,
    this.puestoEnSector,
    this.callesEnSector,
    required this.latitud,
    required this.longitud,
    required this.total,
    required this.reportes,
    required this.anterior,
    required this.tendencia,
    required this.variacion,
    required this.ultimo,
    required this.porCategoria,
  });

  /// "Mirasol · Puerto Montt", o solo la comuna si no hay sector.
  String? get lugar => [sector, comuna].whereType<String>().toSet().join(' · ').ifEmptyNull;

  factory CalleAnalisis.desdeJson(Map<String, dynamic> json) => CalleAnalisis(
    id: json.entero('id'),
    nombre: json.texto('nombre'),
    comuna: json.textoOpcional('comuna'),
    sector: json.textoOpcional('sector'),
    idSector: json.enteroOpcional('id_sector'),
    puestoEnSector: json.enteroOpcional('puesto_en_sector'),
    callesEnSector: json.enteroOpcional('calles_en_sector'),
    latitud: json.decimalOpcional('latitud'),
    longitud: json.decimalOpcional('longitud'),
    total: json.entero('total'),
    reportes: json.entero('reportes'),
    anterior: json.entero('anterior'),
    tendencia: Tendencia.desdeApi(json.textoOpcional('tendencia')),
    variacion: json.decimalOpcional('variacion'),
    ultimo: json.fechaLocal('ultimo'),
    porCategoria: json.lista('por_categoria', (c) => (categoria: _categoria(c), total: c.entero('total'))),
  );
}

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}

/// Un sector con sus tramos de calle con más hechos (ranking agrupado).
class GrupoSector {
  /// null = "Sector sin identificar".
  final int? id;
  final String nombre;
  final String? comuna;

  /// Suma de los hechos de sus calles (solo los que tienen calle identificada).
  final int total;
  final int anterior;
  final Tendencia tendencia;
  final double? variacion;
  final int totalCalles;
  final List<CalleAnalisis> calles;

  GrupoSector({
    required this.id,
    required this.nombre,
    required this.comuna,
    required this.total,
    required this.anterior,
    required this.tendencia,
    required this.variacion,
    required this.totalCalles,
    required this.calles,
  });

  factory GrupoSector.desdeJson(Map<String, dynamic> json) => GrupoSector(
    id: json.enteroOpcional('id'),
    nombre: json.texto('nombre', 'Sector sin identificar'),
    comuna: json.textoOpcional('comuna'),
    total: json.entero('total'),
    anterior: json.entero('anterior'),
    tendencia: Tendencia.desdeApi(json.textoOpcional('tendencia')),
    variacion: json.decimalOpcional('variacion'),
    totalCalles: json.entero('total_calles'),
    calles: json.lista('calles', CalleAnalisis.desdeJson),
  );
}

class RankingCalles {
  final List<CalleAnalisis> calles;
  final int totalCalles;
  final List<GrupoSector> porSector;
  final int reportesSinCalle;

  RankingCalles({
    required this.calles,
    required this.totalCalles,
    this.porSector = const [],
    required this.reportesSinCalle,
  });

  factory RankingCalles.desdeJson(Map<String, dynamic> json) => RankingCalles(
    calles: json.lista('calles', CalleAnalisis.desdeJson),
    totalCalles: json.entero('total_calles'),
    porSector: json.lista('por_sector', GrupoSector.desdeJson),
    reportesSinCalle: json.entero('reportes_sin_calle'),
  );
}

/// Sector (localidad o comuna) con su evolución por tramos del período.
class SectorAnalisis {
  final String clave;
  final String nombre;
  final String? comuna;
  final List<int> serie;
  final int total;
  final int anterior;
  final Tendencia tendencia;
  final double? variacion;

  SectorAnalisis({
    required this.clave,
    required this.nombre,
    required this.comuna,
    required this.serie,
    required this.total,
    required this.anterior,
    required this.tendencia,
    required this.variacion,
  });

  factory SectorAnalisis.desdeJson(Map<String, dynamic> json) => SectorAnalisis(
    clave: json.texto('clave'),
    nombre: json.texto('nombre', 'Sin nombre'),
    comuna: json.textoOpcional('comuna'),
    serie: json.enteros('serie'),
    total: json.entero('total'),
    anterior: json.entero('anterior'),
    tendencia: Tendencia.desdeApi(json.textoOpcional('tendencia')),
    variacion: json.decimalOpcional('variacion'),
  );
}

class SectoresEnElTiempo {
  final List<({DateTime desde, DateTime hasta})> tramos;
  final List<SectorAnalisis> sectores;
  final Map<Tendencia, int> resumen;

  SectoresEnElTiempo({required this.tramos, required this.sectores, required this.resumen});

  factory SectoresEnElTiempo.desdeJson(Map<String, dynamic> json) => SectoresEnElTiempo(
    tramos: json.lista(
      'tramos',
      (t) => (desde: DateTime.parse(t.texto('desde')), hasta: DateTime.parse(t.texto('hasta'))),
    ),
    sectores: json.lista('sectores', SectorAnalisis.desdeJson),
    resumen: {for (final t in Tendencia.values) t: json.mapa('resumen').entero(t.name)},
  );
}

/// Opciones de los filtros del análisis.
class FiltrosDisponibles {
  final List<CategoriaAnalisis> categorias;
  final List<({int id, String nombre})> comunas;

  /// Sectores (localidades) con reportes, con su comuna para filtrarlos por ella.
  final List<({int id, String nombre, int? idComuna})> sectores;

  FiltrosDisponibles({required this.categorias, required this.comunas, this.sectores = const []});

  factory FiltrosDisponibles.desdeJson(Map<String, dynamic> json) => FiltrosDisponibles(
    categorias: json.lista('categorias', _categoria),
    comunas: json.lista('comunas', (c) => (id: c.entero('id'), nombre: c.texto('nombre'))),
    sectores: json.lista(
      'sectores',
      (s) => (id: s.entero('id'), nombre: s.texto('nombre'), idComuna: s.enteroOpcional('id_comuna')),
    ),
  );
}
