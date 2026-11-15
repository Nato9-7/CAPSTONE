import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/lectura_json.dart';
import 'package:rb_alertas/utilidades/formato.dart';

/// Tipo de zona segura.
enum TipoZona {
  casa('CASA', 'Casa', Icons.home_outlined),
  trabajo('TRABAJO', 'Trabajo', Icons.work_outline),
  estudio('ESTUDIO', 'Estudio', Icons.school_outlined),
  otro('OTRO', 'Otro lugar', Icons.favorite_border_rounded);

  const TipoZona(this.codigo, this.etiqueta, this.icono);

  final String codigo;
  final String etiqueta;
  final IconData icono;

  /// El único tipo que permite escribir un nombre propio.
  bool get nombreLibre => this == TipoZona.otro;

  static TipoZona desdeApi(String? codigo) =>
      TipoZona.values.firstWhere((t) => t.codigo == codigo, orElse: () => TipoZona.otro);
}

/// Lugar del usuario (casa, trabajo...) donde recibe alertas de lo que pasa cerca.
class ZonaSegura {
  final int id;
  final TipoZona tipo;
  final String nombre;
  final double latitud;
  final double longitud;
  final int radioMetros;
  final String? direccion;

  ZonaSegura({
    required this.id,
    required this.tipo,
    required this.nombre,
    required this.latitud,
    required this.longitud,
    required this.radioMetros,
    required this.direccion,
  });

  String get radioTexto => textoRadio(radioMetros);

  factory ZonaSegura.desdeJson(Map<String, dynamic> json) => ZonaSegura(
    id: json.entero('id_zona_segura'),
    tipo: TipoZona.desdeApi(json.textoOpcional('tipo')),
    nombre: json.texto('nombre'),
    latitud: json.decimal('latitud'),
    longitud: json.decimal('longitud'),
    radioMetros: json.entero('radio_metros', 1000),
    direccion: json.textoOpcional('direccion_referencia'),
  );
}

/// Las zonas del usuario y los límites para agregar otra.
class ZonasUsuario {
  final List<ZonaSegura> zonas;
  final int maximo;
  final List<int> radiosPermitidos;

  ZonasUsuario({
    required this.zonas,
    required this.maximo,
    required this.radiosPermitidos,
  });

  bool get puedeAgregar => zonas.length < maximo;

  factory ZonasUsuario.desdeJson(Map<String, dynamic> json) => ZonasUsuario(
    zonas: json.lista('zonas', ZonaSegura.desdeJson),
    maximo: json.entero('maximo', 3),
    radiosPermitidos: json.enteros('radios_permitidos', const [500, 1000, 2000]),
  );
}
