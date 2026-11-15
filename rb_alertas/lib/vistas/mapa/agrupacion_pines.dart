// Agrupación de pines del mapa según su distancia en pantalla.
//
// Dos pines se agrupan si a ese zoom sus centros quedan a menos de
// [radioAgrupacionPx]: es decir, si se taparían. Al acercar el mapa la
// distancia en pantalla crece y el grupo se separa solo.
import 'dart:math';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rb_alertas/modelos/reporte.dart';

/// Diámetro de un pin: a menos de esta distancia, dos pines se tapan.
const radioAgrupacionPx = 44.0;

/// Zoom más cercano al que se intenta separar un grupo. Si a este zoom sus
/// pines siguen tapándose, se muestran en abanico o en una lista.
const zoomSeparacion = 18.0;

/// Hasta esta cantidad, los pines superpuestos se abren en abanico; con más,
/// en una lista.
const maximoAbanico = 6;

const _crs = Epsg3857();

/// Uno o más reportes que se dibujan como un solo elemento del mapa.
class GrupoPines {
  final List<ReporteMapa> reportes;

  /// Promedio de las posiciones de sus reportes.
  final LatLng centro;

  GrupoPines(this.reportes) : centro = _promedio(reportes);

  bool get esUnico => reportes.length == 1;

  /// Suma de los reportes de cada incidente del grupo.
  int get totalReportes => reportes.fold(0, (suma, r) => suma + r.totalReportes);

  /// Reporte de la categoría con más reportes del grupo; da el color del grupo.
  ReporteMapa get dominante {
    final porCategoria = <String, int>{};
    for (final r in reportes) {
      porCategoria[r.categoriaCodigo] = (porCategoria[r.categoriaCodigo] ?? 0) + r.totalReportes;
    }
    final codigo = porCategoria.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    return reportes.firstWhere((r) => r.categoriaCodigo == codigo);
  }

  /// true si al zoom de separación sus pines todavía se tapan entre sí.
  bool get siguenJuntos {
    final base = _enPantalla(reportes.first, zoomSeparacion);
    return reportes.every((r) => _enPantalla(r, zoomSeparacion).distanceTo(base) < radioAgrupacionPx);
  }

  static LatLng _promedio(List<ReporteMapa> reportes) {
    final n = reportes.length;
    return LatLng(
      reportes.fold(0.0, (s, r) => s + r.latitud) / n,
      reportes.fold(0.0, (s, r) => s + r.longitud) / n,
    );
  }
}

/// Agrupa los [reportes] que se tapan al [zoom] dado. Cada reporte queda en
/// un solo grupo; el orden de entrada decide cuál es el centro de búsqueda.
List<GrupoPines> agruparPines(List<ReporteMapa> reportes, double zoom) {
  final puntos = [for (final r in reportes) _enPantalla(r, zoom)];
  final asignado = List.filled(reportes.length, false);
  final grupos = <GrupoPines>[];
  for (var i = 0; i < reportes.length; i++) {
    if (asignado[i]) continue;
    asignado[i] = true;
    final miembros = [reportes[i]];
    for (var j = i + 1; j < reportes.length; j++) {
      if (!asignado[j] && puntos[j].distanceTo(puntos[i]) < radioAgrupacionPx) {
        asignado[j] = true;
        miembros.add(reportes[j]);
      }
    }
    grupos.add(GrupoPines(miembros));
  }
  return grupos;
}

/// Posiciones en círculo alrededor de [centro] para abrir [cantidad] pines en
/// abanico, a [radioPx] en pantalla al [zoom] actual.
List<LatLng> posicionesAbanico(LatLng centro, int cantidad, double zoom, {double radioPx = 60}) {
  final origen = _crs.latLngToPoint(centro, zoom);
  return [
    for (var i = 0; i < cantidad; i++)
      _crs.pointToLatLng(
        origen +
            Point(
              radioPx * cos(-pi / 2 + 2 * pi * i / cantidad),
              radioPx * sin(-pi / 2 + 2 * pi * i / cantidad),
            ),
        zoom,
      ),
  ];
}

Point<double> _enPantalla(ReporteMapa r, double zoom) =>
    _crs.latLngToPoint(LatLng(r.latitud, r.longitud), zoom);
