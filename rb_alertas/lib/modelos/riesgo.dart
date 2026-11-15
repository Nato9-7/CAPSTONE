import 'package:rb_alertas/modelos/lectura_json.dart';

/// Lugar donde se repiten robos, asaltos o accidentes (GET /api/reportes/zonas-riesgo).
class ZonaRiesgo {
  /// 'SEGURIDAD' (robos, asaltos...) o 'VIAL' (accidentes, problemas en la vía).
  final String tipo;

  /// 'ALTO' o 'MEDIO'.
  final String nivel;
  final double latitud;
  final double longitud;
  final double radioMetros;
  final int totalIncidentes;
  final int incidentesDeNoche;
  final List<({String codigo, String nombre, String? colorHex, int total})> porCategoria;
  final DateTime? ultimoIncidente;
  final String recomendacion;

  ZonaRiesgo({
    required this.tipo,
    required this.nivel,
    required this.latitud,
    required this.longitud,
    required this.radioMetros,
    required this.totalIncidentes,
    required this.incidentesDeNoche,
    required this.porCategoria,
    required this.ultimoIncidente,
    required this.recomendacion,
  });

  bool get esSeguridad => tipo == 'SEGURIDAD';
  bool get esAlto => nivel == 'ALTO';

  String get titulo {
    if (esSeguridad) return esAlto ? 'Zona de riesgo alto' : 'Zona de precaución';
    return 'Zona de riesgo vial';
  }

  /// Igual que tipo_riesgo() de la API: 'SEGURIDAD', 'VIAL' o null.
  static String? tipoDeCategoria(String codigo) {
    final c = codigo.toUpperCase();
    const seguridad = ['ROBO', 'ASALTO', 'HURTO', 'SOSPECH', 'VANDAL', 'VIOLEN', 'RINA', 'DROGA', 'AGRESION'];
    const vial = ['ACCIDENTE', 'VIAL', 'CHOQUE', 'ATROPELL'];
    if (seguridad.any(c.contains)) return 'SEGURIDAD';
    if (vial.any(c.contains)) return 'VIAL';
    return null;
  }

  factory ZonaRiesgo.desdeJson(Map<String, dynamic> json) => ZonaRiesgo(
    tipo: json.texto('tipo'),
    nivel: json.texto('nivel'),
    latitud: json.decimal('latitud'),
    longitud: json.decimal('longitud'),
    radioMetros: json.decimal('radio_metros'),
    totalIncidentes: json.entero('total_incidentes'),
    incidentesDeNoche: json.entero('incidentes_de_noche'),
    porCategoria: json.lista(
      'por_categoria',
      (c) => (
        codigo: c.texto('codigo'),
        nombre: c.texto('nombre'),
        colorHex: c.textoOpcional('color_hex'),
        total: c.entero('total'),
      ),
    ),
    ultimoIncidente: json.fecha('ultimo_incidente'),
    recomendacion: json.texto('recomendacion'),
  );
}

/// Mancha del mapa de calor (GET /api/reportes/calor): robos y accidentes de
/// tránsito cercanos juntos en un solo lugar, que crece con cuántos son.
class PuntoCalor {
  final double latitud;
  final double longitud;

  /// Hechos que se juntaron en esta mancha.
  final int peso;

  /// De esos hechos, cuántos son robos y cuántos accidentes de tránsito.
  final int robos;
  final int accidentes;

  /// Radio de la mancha en el terreno; crece con [peso].
  final double radioMetros;

  const PuntoCalor({
    required this.latitud,
    required this.longitud,
    required this.peso,
    this.robos = 0,
    this.accidentes = 0,
    this.radioMetros = 150,
  });

  factory PuntoCalor.desdeJson(Map<String, dynamic> json) => PuntoCalor(
    latitud: json.decimal('latitud'),
    longitud: json.decimal('longitud'),
    peso: json.entero('peso'),
    // Versiones anteriores de la API llamaban "seguridad" a los robos.
    robos: json.enteroOpcional('robos') ?? json.entero('seguridad'),
    accidentes: json.entero('accidentes'),
    radioMetros: json.decimal('radio_metros', 150),
  );
}
