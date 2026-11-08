// "Dónde ocurre más" en la sección Red del panel: la red de lugares y
// categorías, el filtro por categoría y el ranking de zonas.
//
//   flutter test test/red_zonas_test.dart
//
// Para guardar además capturas PNG:
//   flutter test test/red_zonas_test.dart --dart-define=CAPTURAS=C:/ruta/carpeta
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/admin_red_vista.dart';
import 'package:rb_alertas/widgets/lienzo_grafo.dart';

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

/// Deja avanzar la API simulada y la simulación de fuerzas del lienzo.
Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _tocar(WidgetTester tester, Finder buscador) async {
  await tester.ensureVisible(buscador.first);
  await tester.pump();
  await tester.tap(buscador.first, warnIfMissed: false);
  await _asentar(tester);
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

  testWidgets('dónde ocurre más: red por lugar y categoría, filtro de robos y ranking', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);

    Sesion.token = 'token-de-prueba';
    Sesion.usuario = {'nombres': 'Renato', 'apellidos': 'Díaz', 'es_admin': true};
    addTearDown(() {
      Sesion.token = null;
      Sesion.usuario = null;
    });

    final llave = GlobalKey();
    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaRBAlertas(),
          home: RepaintBoundary(key: llave, child: const Scaffold(body: SeccionRed())),
        ),
      );
      await _asentar(tester);

      // Vista "Dónde ocurre más" con todas las categorías.
      await _tocar(tester, find.text('Dónde ocurre más'));
      final lienzo = tester.widget<LienzoGrafo>(find.byType(LienzoGrafo));
      expect(lienzo.nodos.map((n) => n.etiqueta), containsAll(['Mirasol', 'Centro', 'Robo o asalto']));
      expect(lienzo.aristas.every((a) => a.tipo == 'OCURREN'), isTrue);
      await _capturar(tester, llave, 'zonas_todas');

      // Solo robos: quedan los lugares con robos y una sola categoría.
      await _tocar(tester, find.text('Robos'));
      final soloRobos = tester.widget<LienzoGrafo>(find.byType(LienzoGrafo));
      expect(soloRobos.nodos.where((n) => n.tipo == 'Categoria').map((n) => n.etiqueta), ['Robo o asalto']);
      expect(soloRobos.nodos.map((n) => n.etiqueta), isNot(contains('Puerto Varas')));

      // Ranking de zonas: Mirasol primero, con sus 7 robos.
      await _tocar(tester, find.text('Zonas'));
      expect(find.text('Mirasol'), findsWidgets);
      expect(find.text('7'), findsWidgets);
      expect(find.text('hechos'), findsWidgets);
      await _capturar(tester, llave, 'zonas_robos');

      // La ficha de Mirasol (como al tocar su nodo) cuenta hechos y dice
      // cuántas veces se reportaron.
      final red = tester.widget<LienzoGrafo>(find.byType(LienzoGrafo));
      red.alSeleccionar!(red.nodos.firstWhere((n) => n.etiqueta == 'Mirasol'));
      await _asentar(tester);
      expect(find.textContaining('7 hechos de esta categoría'), findsOneWidget);
      expect(find.text('Reportados 10 veces por los vecinos'), findsOneWidget);
      await _capturar(tester, llave, 'zonas_ficha');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    }, clienteApiFalsa);
  });
}
