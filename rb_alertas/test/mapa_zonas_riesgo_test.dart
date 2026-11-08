// Zonas de riesgo en el mapa: círculos, botón para ocultarlas y tarjeta con
// la recomendación.
//
//   flutter test test/mapa_zonas_riesgo_test.dart
//   flutter test test/mapa_zonas_riesgo_test.dart --dart-define=CAPTURAS=C:/ruta/carpeta
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/mapa_vista.dart';
import 'package:rb_alertas/widgets/capa_calor.dart';
import 'package:rb_alertas/widgets/zonas_riesgo_mapa.dart';

import 'soporte/api_falsa.dart';

const _carpetaCapturas = String.fromEnvironment('CAPTURAS');

Future<void> _cargarFuentes() async {
  Future<void> cargar(String familia, List<String> archivos) async {
    final cargador = FontLoader(familia);
    for (final archivo in archivos) {
      final bytes = File(archivo).readAsBytesSync();
      cargador.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await cargador.load();
  }

  final fuentes = Directory('assets/fonts').listSync().whereType<File>().map((f) => f.path);
  await cargar('Figtree', fuentes.where((f) => f.contains('Figtree')).toList());
  await cargar(
    'BricolageGrotesque',
    fuentes.where((f) => f.contains('BricolageGrotesque') && f.endsWith('.ttf')).toList(),
  );
  final raizFlutter = Platform.environment['FLUTTER_ROOT'];
  if (raizFlutter != null) {
    final iconos = File('$raizFlutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (iconos.existsSync()) await cargar('MaterialIcons', [iconos.path]);
  }
}

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _capturar(WidgetTester tester, GlobalKey llave, String nombre) async {
  if (_carpetaCapturas.isEmpty) return;
  await tester.runAsync(() async {
    final limite = llave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final imagen = await limite.toImage(pixelRatio: 1);
    final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
    final archivo = File('$_carpetaCapturas/$nombre.png');
    archivo.parent.createSync(recursive: true);
    archivo.writeAsBytesSync(datos!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_cargarFuentes);

  testWidgets('el mapa marca las zonas de riesgo y recomienda no transitar', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);

    final llave = GlobalKey();
    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaRBAlertas(),
          home: RepaintBoundary(key: llave, child: const MapaVista()),
        ),
      );
      await _asentar(tester);

      // Tres zonas: dos de seguridad y una vial.
      final circulos = tester.widget<CircleLayer>(find.byType(CircleLayer));
      expect(circulos.circles, hasLength(3));
      expect(find.text('Zonas de riesgo · 3'), findsOneWidget);
      await _capturar(tester, llave, 'mapa_zonas');

      // Tocar dentro del círculo rojo (lejos de los pines) abre su tarjeta.
      expect(find.bySemanticsLabel('Zona de riesgo alto'), findsOneWidget);
      await tester.tapAt(const Offset(255, 420));
      await _asentar(tester);
      expect(find.byType(TarjetaZonaRiesgo), findsOneWidget);
      expect(find.textContaining('Evita transitar por aquí'), findsOneWidget);
      expect(find.text('5 robos y 1 sospechoso en los últimos 60 días'), findsOneWidget);
      await _capturar(tester, llave, 'mapa_zona_tarjeta');

      await tester.tap(find.byTooltip('Cerrar'));
      await _asentar(tester);
      expect(find.byType(TarjetaZonaRiesgo), findsNothing);

      // De cerca no hay calor; al alejar, el calor reemplaza a los círculos.
      expect(find.byType(CapaCalor), findsNothing);
      for (var i = 0; i < 2; i++) {
        tester.binding.handlePointerEvent(
          const PointerScrollEvent(position: Offset(206, 450), scrollDelta: Offset(0, 120)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _asentar(tester);
      expect(find.byType(CapaCalor), findsOneWidget);
      expect(find.byType(CircleLayer), findsNothing);
      expect(find.text('Robos y accidentes · 60 días'), findsOneWidget);
      await _capturar(tester, llave, 'mapa_calor');

      // El botón las oculta.
      await tester.tap(find.text('Zonas de riesgo · 3'));
      await _asentar(tester);
      expect(find.byType(CircleLayer), findsNothing);
      expect(find.byType(CapaCalor), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    }, clienteApiFalsa);
  });
}
