// Con el teclado abierto, la barra para comentar debe quedar por encima de él
// (antes quedaba tapada y no se veía lo escrito ni el botón de enviar).
//
//   flutter test test/teclado_comentarios_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/detalle_incidente_vista.dart';

import 'soporte/api_falsa.dart';

void main() {
  testWidgets('la barra de comentarios sube con el teclado', (tester) async {
    const tamano = Size(390, 844);
    const altoTeclado = 320.0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = tamano;
    tester.view.viewInsets = const FakeViewPadding(bottom: altoTeclado);
    addTearDown(tester.view.reset);

    Sesion.token = 'token-de-prueba';
    Sesion.usuario = {'nombres': 'Renato', 'apellidos': 'Díaz', 'es_admin': false};
    addTearDown(() {
      Sesion.token = null;
      Sesion.usuario = null;
    });

    // Sin las fuentes reales, la fuente de pruebas (letras cuadradas y anchas)
    // desborda textos que en la app caben. Los desbordes ya los revisa
    // pantallas_responsive_test.dart con las fuentes reales; aquí solo importa
    // dónde queda la barra.
    final manejadorOriginal = FlutterError.onError;
    FlutterError.onError = (detalle) {
      if (!detalle.exceptionAsString().contains('overflowed')) {
        manejadorOriginal?.call(detalle);
      }
    };
    addTearDown(() => FlutterError.onError = manejadorOriginal);

    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: temaRBAlertas(),
          home: const DetalleIncidenteVista(idReporte: 1),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      final limiteTeclado = tamano.height - altoTeclado;
      final campo = tester.getRect(find.byType(TextField));
      final enviar = tester.getRect(find.byIcon(Icons.near_me_outlined));
      expect(campo.bottom, lessThanOrEqualTo(limiteTeclado));
      expect(enviar.bottom, lessThanOrEqualTo(limiteTeclado));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    }, clienteApiFalsa);
  });
}
