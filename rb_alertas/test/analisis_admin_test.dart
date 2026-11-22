// Sección Análisis del panel: indicadores, hechos por día, calles con más
// hechos (con tendencia), sectores en el tiempo y la red de calles.
//
//   flutter test test/analisis_admin_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/admin/analisis/graficos_analisis.dart';
import 'package:rb_alertas/vistas/admin/analisis/seccion_analisis.dart';
import 'package:rb_alertas/widgets/lienzo_grafo.dart';

import 'soporte/api_falsa.dart';

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _probarEn(WidgetTester tester, Size tamano) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = tamano;
  addTearDown(tester.view.reset);
  Sesion.token = 'token-de-prueba';
  Sesion.usuario = {'nombres': 'Admin', 'apellidos': '', 'es_admin': true};
  addTearDown(() {
    Sesion.token = null;
    Sesion.usuario = null;
  });

  await http.runWithClient(() async {
    await tester.pumpWidget(
      MaterialApp(
        theme: temaRBAlertas(),
        home: const Scaffold(body: SeccionAnalisis()),
      ),
    );
    await _asentar(tester);

    // Indicadores y gráfico por día.
    expect(find.text('Hechos en 30 días'), findsOneWidget);
    expect(find.byType(BarrasPorDia), findsOneWidget);

    // Ranking por calle (no por comuna), con la calle con más hechos primero.
    await tester.scrollUntilVisible(find.text('Calles con más hechos'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Avenida Presidente Ibáñez'), findsWidgets);
    // Agrupado por sector: Mirasol primero y el grupo sin sector al final.
    expect(find.text('Mirasol'), findsWidgets);
    expect(find.text('Sector sin identificar'), findsOneWidget);
    // "Todas": la misma avenida aparece como dos tramos, cada uno con su sector.
    await tester.ensureVisible(find.text('Todas').first);
    await tester.pump();
    await tester.tap(find.text('Todas').first);
    await _asentar(tester);
    expect(find.textContaining('Mirasol · Puerto Montt'), findsWidgets);
    expect(find.textContaining('Alerce Norte · Puerto Montt'), findsOneWidget);
    expect(find.textContaining('reportes no tienen calle identificada'), findsOneWidget);

    // Sectores con su tendencia.
    await tester.scrollUntilVisible(find.text('Sectores en el tiempo'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.byType(MiniSerie), findsWidgets);

    // Red de calles unidas a categorías.
    await tester.scrollUntilVisible(find.byType(LienzoGrafo), 300, scrollable: find.byType(Scrollable).first);
    final lienzo = tester.widget<LienzoGrafo>(find.byType(LienzoGrafo));
    expect(lienzo.nodos.where((n) => n.tipo == 'Calle'), isNotEmpty);
    // Tres niveles: sector → tramo de calle → categoría.
    expect(lienzo.nodos.where((n) => n.tipo == 'Localidad').map((n) => n.etiqueta), contains('Mirasol'));
    expect(lienzo.aristas.map((a) => a.tipo).toSet(), {'OCURREN', 'CONTIENE'});

    // Un gesto sobre la red es de la red: la página no se desplaza
    // (antes la página se quedaba con el gesto y no se podía acercar con dos dedos).
    final pagina = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    final antes = pagina.pixels;
    final dedo = await tester.startGesture(tester.getCenter(find.byType(LienzoGrafo)), pointer: 7);
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 8; i++) {
      await dedo.moveBy(const Offset(0, 15)); // hacia abajo: la página siempre podría subir
      await tester.pump(const Duration(milliseconds: 16));
    }
    await dedo.up();
    await tester.pump();
    expect(pagina.pixels, antes, reason: 'arrastrar sobre la red debe mover la red, no la página');

    // Nada de cuentas sospechosas ni reputación.
    expect(find.textContaining('cuentas sospechosas'), findsNothing);
    expect(find.textContaining('eputación'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  }, clienteApiFalsa);
}

void main() {
  testWidgets('análisis en computador', (tester) => _probarEn(tester, const Size(1440, 900)));
  testWidgets('análisis en celular', (tester) => _probarEn(tester, const Size(390, 844)));
}
