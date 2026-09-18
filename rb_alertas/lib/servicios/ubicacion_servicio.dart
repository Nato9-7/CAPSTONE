import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class UbicacionServicioException implements Exception {
  final String mensaje;
  UbicacionServicioException(this.mensaje);
}

class UbicacionServicio {
  Future<LatLng> obtenerUbicacionActual() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw UbicacionServicioException(
        'Activa la ubicación del dispositivo o toca el mapa para marcar el lugar',
      );
    }

    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }
    if (permiso == LocationPermission.denied ||
        permiso == LocationPermission.deniedForever) {
      throw UbicacionServicioException(
        'Sin permiso de ubicación: toca el mapa para marcar el lugar',
      );
    }

    final posicion = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return LatLng(posicion.latitude, posicion.longitude);
  }

  /// Dirección legible del punto ("Calle, Ciudad") usando Nominatim de
  /// OpenStreetMap. Devuelve null si no se pudo obtener.
  Future<String?> obtenerDireccion(LatLng punto) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': '${punto.latitude}',
      'lon': '${punto.longitude}',
      'zoom': '17',
      'accept-language': 'es',
    });

    try {
      // El navegador no permite cambiar el User-Agent; en web basta el Referer.
      final respuesta = await http
          .get(
            uri,
            headers: kIsWeb ? null : {'User-Agent': 'com.rbalertas.rb_alertas'},
          )
          .timeout(const Duration(seconds: 8));
      if (respuesta.statusCode != 200) return null;

      final cuerpo =
          jsonDecode(utf8.decode(respuesta.bodyBytes)) as Map<String, dynamic>;
      final direccion = (cuerpo['address'] ?? {}) as Map<String, dynamic>;
      final calle = direccion['road'] ??
          direccion['pedestrian'] ??
          direccion['neighbourhood'] ??
          direccion['suburb'];
      final ciudad =
          direccion['city'] ?? direccion['town'] ?? direccion['village'];

      final partes = [calle, ciudad].whereType<String>().toList();
      return partes.isEmpty ? null : partes.join(', ');
    } catch (_) {
      return null;
    }
  }
}
