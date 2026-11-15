import 'package:rb_alertas/modelos/lectura_json.dart';

/// Comuna con cobertura que se puede elegir al crear una cuenta.
class Comuna {
  final int id;
  final String nombre;

  Comuna({required this.id, required this.nombre});

  factory Comuna.desdeJson(Map<String, dynamic> json) =>
      Comuna(id: json.entero('id_comuna'), nombre: json.texto('nombre'));
}

/// Región con sus comunas operativas (GET /api/usuarios/comunas).
class Region {
  final int id;
  final String nombre;
  final String? numeroRomano;
  final List<Comuna> comunas;

  Region({required this.id, required this.nombre, required this.numeroRomano, required this.comunas});

  /// "X · Los Lagos", o solo el nombre si no trae número.
  String get etiqueta =>
      (numeroRomano == null || numeroRomano!.isEmpty) ? nombre : '$numeroRomano · $nombre';

  factory Region.desdeJson(Map<String, dynamic> json) => Region(
    id: json.entero('id_region'),
    nombre: json.texto('nombre'),
    numeroRomano: json.textoOpcional('numero_romano'),
    comunas: json.lista('comunas', Comuna.desdeJson),
  );
}
