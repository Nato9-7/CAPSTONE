import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:rb_alertas/config/api_config.dart';

class ZonasServicioException implements Exception {
  final String mensaje;
  ZonasServicioException(this.mensaje);
}

/// Tipo de zona segura.
enum TipoZona {
  casa('CASA', 'Casa', Icons.home_outlined),
  trabajo('TRABAJO', 'Trabajo', Icons.work_outline),
  estudio('ESTUDIO', 'Estudio', Icons.school_outlined),
  otro('OTRO', 'Otro lugar', Icons.place_outlined);

  const TipoZona(this.codigo, this.etiqueta, this.icono);

  final String codigo;
  final String etiqueta;
  final IconData icono;

  /// El único tipo que permite escribir un nombre propio.
  bool get nombreLibre => this == TipoZona.otro;

  static TipoZona desdeApi(String? codigo) {
    return TipoZona.values.firstWhere(
      (t) => t.codigo == codigo,
      orElse: () => TipoZona.otro,
    );
  }
}

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

  /// "500 m" o "1 km": el mismo texto que muestran el chip y las marcas del slider.
  String get radioTexto => radioMetros < 1000
      ? '$radioMetros m'
      : '${(radioMetros / 1000).toStringAsFixed(radioMetros % 1000 == 0 ? 0 : 1)} km';

  factory ZonaSegura.desdeJson(Map<String, dynamic> json) {
    return ZonaSegura(
      id: (json['id_zona_segura'] as num).toInt(),
      tipo: TipoZona.desdeApi(json['tipo']?.toString()),
      nombre: (json['nombre'] ?? '').toString(),
      latitud: (json['latitud'] as num).toDouble(),
      longitud: (json['longitud'] as num).toDouble(),
      radioMetros: (json['radio_metros'] as num?)?.toInt() ?? 1000,
      direccion: json['direccion_referencia']?.toString(),
    );
  }
}

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

  factory ZonasUsuario.desdeJson(Map<String, dynamic> json) {
    return ZonasUsuario(
      zonas: [
        for (final z in (json['zonas'] as List? ?? []))
          ZonaSegura.desdeJson(z as Map<String, dynamic>),
      ],
      maximo: (json['maximo'] as num?)?.toInt() ?? 3,
      radiosPermitidos: [
        for (final r
            in (json['radios_permitidos'] as List? ?? [500, 1000, 2000]))
          (r as num).toInt(),
      ],
    );
  }
}

class ZonasServicio {
  static const String baseUrl = ApiConfig.baseUrl;
  static const String _ruta = '/api/usuarios/zonas/';

  Future<ZonasUsuario> listar(String token) async {
    final respuesta = await http.get(
      Uri.parse('$baseUrl$_ruta'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (respuesta.statusCode == 200) {
      return ZonasUsuario.desdeJson(
        jsonDecode(utf8.decode(respuesta.bodyBytes)) as Map<String, dynamic>,
      );
    }
    throw ZonasServicioException(
      _mensaje(respuesta, 'No se pudieron cargar tus zonas seguras'),
    );
  }

  Future<ZonaSegura> crear({
    required String token,
    required TipoZona tipo,
    String? nombre,
    required double latitud,
    required double longitud,
    required int radioMetros,
    String? direccion,
  }) async {
    final respuesta = await http.post(
      Uri.parse('$baseUrl$_ruta'),
      headers: _cabeceras(token),
      body: jsonEncode(
        _cuerpo(
          tipo: tipo,
          nombre: nombre,
          latitud: latitud,
          longitud: longitud,
          radioMetros: radioMetros,
          direccion: direccion,
        ),
      ),
    );
    if (respuesta.statusCode == 201) {
      return ZonaSegura.desdeJson(
        jsonDecode(utf8.decode(respuesta.bodyBytes)) as Map<String, dynamic>,
      );
    }
    throw ZonasServicioException(
      _mensaje(respuesta, 'No se pudo guardar la zona'),
    );
  }

  Future<ZonaSegura> actualizar({
    required String token,
    required int idZona,
    required TipoZona tipo,
    String? nombre,
    required double latitud,
    required double longitud,
    required int radioMetros,
    String? direccion,
  }) async {
    final respuesta = await http.put(
      Uri.parse('$baseUrl/api/usuarios/zonas/$idZona'),
      headers: _cabeceras(token),
      body: jsonEncode(
        _cuerpo(
          tipo: tipo,
          nombre: nombre,
          latitud: latitud,
          longitud: longitud,
          radioMetros: radioMetros,
          direccion: direccion,
        ),
      ),
    );
    if (respuesta.statusCode == 200) {
      return ZonaSegura.desdeJson(
        jsonDecode(utf8.decode(respuesta.bodyBytes)) as Map<String, dynamic>,
      );
    }
    throw ZonasServicioException(
      _mensaje(respuesta, 'No se pudieron guardar los cambios'),
    );
  }

  Future<void> eliminar({required String token, required int idZona}) async {
    final respuesta = await http.delete(
      Uri.parse('$baseUrl/api/usuarios/zonas/$idZona'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (respuesta.statusCode == 204 || respuesta.statusCode == 200) return;
    throw ZonasServicioException(
      _mensaje(respuesta, 'No se pudo eliminar la zona'),
    );
  }

  Map<String, String> _cabeceras(String token) => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json; charset=utf-8',
  };

  Map<String, dynamic> _cuerpo({
    required TipoZona tipo,
    String? nombre,
    required double latitud,
    required double longitud,
    required int radioMetros,
    String? direccion,
  }) {
    final referencia = (direccion ?? '').trim();
    return {
      'tipo': tipo.codigo,
      // Solo OTRO manda nombre: en los demás lo fija el servidor.
      if (tipo.nombreLibre) 'nombre': (nombre ?? '').trim(),
      'latitud': latitud,
      'longitud': longitud,
      'radio_metros': radioMetros,
      'direccion_referencia': referencia.isEmpty ? null : referencia,
    };
  }

  String _mensaje(http.Response respuesta, String porDefecto) {
    try {
      final cuerpo = jsonDecode(utf8.decode(respuesta.bodyBytes));
      final detalle = cuerpo is Map ? cuerpo['detail'] : null;
      if (detalle is String) return detalle;
    } catch (_) {
      // se usa el mensaje por defecto
    }
    return porDefecto;
  }
}
