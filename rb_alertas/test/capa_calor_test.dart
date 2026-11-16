// Escala fija del mapa de calor: el color depende de la intensidad de cada
// mancha y no de cuál es la más grande del mapa.
import 'package:flutter_test/flutter_test.dart';
import 'package:rb_alertas/modelos/riesgo.dart';
import 'package:rb_alertas/widgets/capa_calor.dart';

void main() {
  test('la escala va de amarillo (1) a naranjo (3) y rojo (6 o más)', () {
    expect(nivelCalor(0.4), 0);
    expect(nivelCalor(1), 0);
    expect(nivelCalor(2), 0.25);
    expect(nivelCalor(3), 0.5);
    expect(nivelCalor(4.5), 0.75);
    expect(nivelCalor(6), 1);
    expect(nivelCalor(20), 1);
  });

  test('sin intensidad de la API, se usa la cantidad de hechos', () {
    final antiguo = PuntoCalor.desdeJson({'latitud': -41.47, 'longitud': -72.94, 'peso': 3});
    expect(antiguo.intensidad, 3);
    final nuevo = PuntoCalor.desdeJson({'latitud': -41.47, 'longitud': -72.94, 'peso': 3, 'intensidad': 1.25});
    expect(nuevo.intensidad, 1.25);
  });
}
