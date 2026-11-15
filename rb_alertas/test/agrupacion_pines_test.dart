// Agrupación de pines del mapa: cálculo de grupos y comportamiento al tocar
// reportes que están en el mismo punto.
//
//   flutter test test/agrupacion_pines_test.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:rb_alertas/modelos/reporte.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/mapa/agrupacion_pines.dart';
import 'package:rb_alertas/vistas/mapa/mapa_vista.dart';
import 'package:rb_alertas/vistas/mapa/widgets/pin_grupo.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

import 'soporte/api_falsa.dart';

const _centro = LatLng(-41.4693, -72.9424);

Map<String, Object?> _json(int id, {String categoria = 'ROBO', double dLat = 0, double dLon = 0, int total = 1}) => {
  'id_reporte': id,
  'categoria_codigo': categoria,
  'categoria': categoria,
  'color_hex': null,
  'latitud': _centro.latitude + dLat,
  'longitud': _centro.longitude + dLon,
  'direccion': 'Calle Urmeneta $id, Puerto Montt',
  'descripcion': 'Reporte $id',
  'estado': 'PENDIENTE',
  'fecha_creacion': DateTime.now().subtract(Duration(minutes: id)).toIso8601String(),
  'total_reportes': total,
};

ReporteMapa _reporte(int id, {String categoria = 'ROBO', double dLat = 0, double dLon = 0, int total = 1}) =>
    ReporteMapa.desdeJson(_json(id, categoria: categoria, dLat: dLat, dLon: dLon, total: total));

/// API simulada en la que el mapa recibe [reportes]; el resto, como siempre.
MockClient _cliente(List<Map<String, Object?>> reportes) {
  final base = clienteApiFalsa();
  return MockClient((peticion) async {
    if (peticion.url.path == '/api/reportes/') {
      return http.Response.bytes(utf8.encode(jsonEncode(reportes)), 200);
    }
    return base.send(peticion).then(http.Response.fromStream);
  });
}

Future<void> _abrirMapa(WidgetTester tester, List<Map<String, Object?>> reportes) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(412, 915);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(theme: temaRBAlertas(), home: const MapaVista()),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('agruparPines', () {
    test('los reportes en el mismo punto quedan en un grupo que no se separa', () {
      final grupos = agruparPines([_reporte(1), _reporte(2, categoria: 'ACCIDENTE')], 14);
      expect(grupos, hasLength(1));
      expect(grupos.single.reportes, hasLength(2));
      expect(grupos.single.siguenJuntos, isTrue);
    });

    test('un grupo de lejos se separa al acercar el mapa', () {
      final reportes = [_reporte(1), _reporte(2, dLat: 0.003, dLon: 0.003)];
      expect(agruparPines(reportes, 12), hasLength(1));
      expect(agruparPines(reportes, 17), hasLength(2));
      expect(agruparPines(reportes, 12).single.siguenJuntos, isFalse);
    });

    test('el color sale de la categoría con más reportes y el total los suma', () {
      final grupo = agruparPines([
        _reporte(1, categoria: 'ACCIDENTE'),
        _reporte(2, categoria: 'ROBO', total: 3),
        _reporte(3, categoria: 'ACCIDENTE'),
      ], 14).single;
      expect(grupo.dominante.categoriaCodigo, 'ROBO');
      expect(grupo.totalReportes, 5);
    });

    test('el abanico reparte los pines alrededor del centro sin repetir posiciones', () {
      final posiciones = posicionesAbanico(_centro, 5, 16);
      expect(posiciones.toSet(), hasLength(5));
      for (final p in posiciones) {
        final metros = const Distance().as(LengthUnit.Meter, _centro, p);
        expect(metros, greaterThan(10));
      }
    });
  });

  testWidgets('pocos reportes en el mismo punto se abren en abanico', (tester) async {
    await http.runWithClient(() async {
      await _abrirMapa(tester, [_json(1), _json(2, categoria: 'ACCIDENTE'), _json(3)]);
      expect(find.byType(PinGrupo), findsOneWidget);
      expect(find.byType(PinIncidente), findsNothing);

      await tester.tap(find.byType(PinGrupo));
      await tester.pump();
      expect(find.byType(PinGrupo), findsNothing);
      expect(find.byType(PinIncidente), findsNWidgets(3));
      expect(find.byType(PolylineLayer), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 21));
    }, () => _cliente([_json(1), _json(2, categoria: 'ACCIDENTE'), _json(3)]));
  });

  testWidgets('muchos reportes en el mismo punto se eligen de una lista', (tester) async {
    final reportes = [for (var id = 1; id <= 8; id++) _json(id)];
    await http.runWithClient(() async {
      await _abrirMapa(tester, reportes);
      await tester.tap(find.byType(PinGrupo));
      await tester.pumpAndSettle();
      expect(find.text('8 reportes en este lugar'), findsOneWidget);
      expect(find.byType(FilaIncidente), findsWidgets);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 21));
    }, () => _cliente(reportes));
  });
}
