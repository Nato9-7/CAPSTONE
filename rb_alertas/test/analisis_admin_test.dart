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
    expect(find.textContaining('reportes no tienen calle identificada'), findsOneWidget);

    // Sectores con su tendencia.
    await tester.scrollUntilVisible(find.text('Sectores en el tiempo'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Mirasol'), findsOneWidget);
    expect(find.byType(MiniSerie), findsWidgets);

    // Red de calles unidas a categorías.
    await tester.scrollUntilVisible(find.byType(LienzoGrafo), 300, scrollable: find.byType(Scrollable).first);
    final lienzo = tester.widget<LienzoGrafo>(find.byType(LienzoGrafo));
    expect(lienzo.nodos.where((n) => n.tipo == 'Calle'), isNotEmpty);
    expect(lienzo.aristas.every((a) => a.tipo == 'OCURREN'), isTrue);

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
