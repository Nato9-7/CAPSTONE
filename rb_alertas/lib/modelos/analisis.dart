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

/// Calle con sus hechos en el período.
class CalleAnalisis {
  final int id;
  final String nombre;
  final String? comuna;
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

  factory CalleAnalisis.desdeJson(Map<String, dynamic> json) => CalleAnalisis(
    id: json.entero('id'),
    nombre: json.texto('nombre'),
    comuna: json.textoOpcional('comuna'),
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

class RankingCalles {
  final List<CalleAnalisis> calles;
  final int totalCalles;
  final int reportesSinCalle;

  RankingCalles({required this.calles, required this.totalCalles, required this.reportesSinCalle});

  factory RankingCalles.desdeJson(Map<String, dynamic> json) => RankingCalles(
    calles: json.lista('calles', CalleAnalisis.desdeJson),
    totalCalles: json.entero('total_calles'),
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

  FiltrosDisponibles({required this.categorias, required this.comunas});

  factory FiltrosDisponibles.desdeJson(Map<String, dynamic> json) => FiltrosDisponibles(
    categorias: json.lista('categorias', _categoria),
    comunas: json.lista('comunas', (c) => (id: c.entero('id'), nombre: c.texto('nombre'))),
  );
}
