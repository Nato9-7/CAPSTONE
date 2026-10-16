// Recorre las pantallas de la app en varios tamaños de celular y falla si
// algún elemento se desborda (los avisos "RenderFlex overflowed" de Flutter).
//
//   flutter test test/pantallas_responsive_test.dart
//
// Para guardar además una captura PNG de cada pantalla:
//   flutter test test/pantallas_responsive_test.dart --dart-define=CAPTURAS=C:/ruta/carpeta
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rb_alertas/servicios/estado_alertas_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/admin_vista.dart';
import 'package:rb_alertas/vistas/alertas_vista.dart';
import 'package:rb_alertas/vistas/detalle_incidente_vista.dart';
import 'package:rb_alertas/vistas/grupos_vista.dart';
import 'package:rb_alertas/vistas/inicio_sesion_vista.dart';
import 'package:rb_alertas/vistas/mapa_vista.dart';
import 'package:rb_alertas/vistas/perfil_vista.dart';
import 'package:rb_alertas/vistas/recuperar_contrasena_vista.dart';
import 'package:rb_alertas/vistas/registro_vista.dart';
import 'package:rb_alertas/vistas/reportar_incidente_vista.dart';
import 'package:rb_alertas/vistas/zonas_seguras_vista.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

import 'soporte/api_falsa.dart';

const _carpetaCapturas = String.fromEnvironment('CAPTURAS');

/// Tamaños lógicos de celulares comunes, del más chico al más grande.
const _tamanos = <String, Size>{
  '320x568': Size(320, 568), // iPhone SE (1.ª gen.), Android compactos
  '360x640': Size(360, 640), // Android pequeño
  '375x667': Size(375, 667), // iPhone SE (2.ª/3.ª gen.)
  '412x915': Size(412, 915), // Android grande
};

/// Una pantalla a probar: cómo construirla y qué hacer antes de revisarla.
class _Caso {
  final String nombre;
  final Widget Function() pantalla;
  final bool conSesion;
  final bool admin;
  final Future<void> Function(WidgetTester tester)? preparar;

  const _Caso(this.nombre, this.pantalla, {this.conSesion = false, this.admin = false, this.preparar});
}

Future<void> _tocar(WidgetTester tester, Finder buscador) async {
  await tester.ensureVisible(buscador.first);
  await tester.pump();
  await tester.tap(buscador.first, warnIfMissed: false);
  await _asentar(tester);
}

/// Deja avanzar las llamadas a la API simulada y las animaciones.
Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

final _casos = <_Caso>[
  _Caso('01_login', () => const InicioSesionVista()),
  _Caso('02_registro', () => const RegistroVista()),
  _Caso('03_recuperar', () => const RecuperarContrasenaVista()),
  _Caso('04_mapa', () => const MapaVista()),
  _Caso('05_mapa_tarjeta', () => const MapaVista(), conSesion: true, preparar: (t) async {
    await _tocar(t, find.byType(PinIncidente));
  }),
  _Caso('05b_mapa_filtros', () => const MapaVista(), preparar: (t) async {
    await _tocar(t, find.text('Filtrar'));
  }),
  _Caso('06_emergencias', () => const MapaVista(), conSesion: true, preparar: (t) async {
    await _tocar(t, find.text('Emergencias'));
  }),
  _Caso('07_reportar', () => const ReportarIncidenteVista(), conSesion: true),
  _Caso('08_detalle', () => const DetalleIncidenteVista(idReporte: 1), conSesion: true),
  _Caso('09_cerca', () => const AlertasVista(), conSesion: true),
  _Caso('10_mis_zonas', () => const AlertasVista(pestanaInicial: 1), conSesion: true),
  _Caso('11_mis_reportes', () => const AlertasVista(pestanaInicial: 2), conSesion: true),
  _Caso('12_grupos', () => const GruposVista()),
  _Caso('13_perfil', () => const PerfilVista(), conSesion: true),
  _Caso('14_perfil_sin_sesion', () => const PerfilVista()),
  _Caso('15_zonas', () => const ZonasSegurasVista(), conSesion: true),
  _Caso('16_editar_zona', () => const ZonasSegurasVista(), conSesion: true, preparar: (t) async {
    await _tocar(t, find.text('Casa de mis padres en Pelluco'));
  }),
  _Caso('17_admin_resumen', () => const AdminVista(), conSesion: true, admin: true),
  _Caso('18_admin_reportes', () => const AdminVista(), conSesion: true, admin: true,
      preparar: (t) async => _tocar(t, find.text('Reportes'))),
  _Caso('19_admin_usuarios', () => const AdminVista(), conSesion: true, admin: true,
      preparar: (t) async => _tocar(t, find.text('Usuarios'))),
  _Caso('20_admin_grafo', () => const AdminVista(), conSesion: true, admin: true,
      preparar: (t) async => _tocar(t, find.text('Grafo'))),
];

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
  // Íconos de Material, desde el SDK de Flutter, para que las capturas se lean.
  final raizFlutter = Platform.environment['FLUTTER_ROOT'];
  if (raizFlutter != null) {
    final iconos = File('$raizFlutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (iconos.existsSync()) await cargar('MaterialIcons', [iconos.path]);
  }
}

void main() {
  setUpAll(_cargarFuentes);

  for (final MapEntry(key: nombreTamano, value: tamano) in _tamanos.entries) {
    for (final caso in _casos) {
      testWidgets('${caso.nombre} en $nombreTamano', (tester) async {
        tester.view.devicePixelRatio = 2;
        tester.view.physicalSize = tamano * 2;
        tester.view.padding = const FakeViewPadding(top: 48, bottom: 32);
        addTearDown(tester.view.reset);

        Sesion.token = caso.conSesion ? 'token-de-prueba' : null;
        Sesion.usuario = caso.conSesion
            ? {'nombres': 'Renato', 'apellidos': 'Díaz', 'es_admin': caso.admin}
            : null;
        EstadoAlertas.registrarZonasSinLeer(caso.conSesion ? 2 : 0);

        final desbordes = <String>[];
        final manejadorOriginal = FlutterError.onError;
        FlutterError.onError = (detalle) {
          final texto = detalle.exceptionAsString();
          if (texto.contains('overflowed')) {
            desbordes.add(texto.split('\n').first);
          } else if (detalle.library != 'image resource service' &&
              !texto.contains('HTTP request failed')) {
            manejadorOriginal?.call(detalle);
          }
        };

        final llave = GlobalKey();
        try {
          await http.runWithClient(() async {
            await tester.pumpWidget(
              MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: temaRBAlertas(),
                builder: (context, hijo) => RepaintBoundary(
                  key: llave,
                  child: ajusteResponsivo(context, hijo),
                ),
                home: caso.pantalla(),
              ),
            );
            await _asentar(tester);
            if (caso.preparar != null) await caso.preparar!(tester);

            if (_carpetaCapturas.isNotEmpty) {
              await tester.runAsync(() async {
                final limite = llave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
                final imagen = await limite.toImage(pixelRatio: 1.5);
                final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
                final archivo = File('$_carpetaCapturas/${nombreTamano}_${caso.nombre}.png');
                archivo.parent.createSync(recursive: true);
                archivo.writeAsBytesSync(datos!.buffer.asUint8List());
              });
            }

            // Se desmonta dentro de la zona para cerrar temporizadores pendientes.
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(seconds: 6));
          }, clienteApiFalsa);
        } finally {
          FlutterError.onError = manejadorOriginal;
          Sesion.token = null;
          Sesion.usuario = null;
          EstadoAlertas.limpiar();
        }

        expect(desbordes, isEmpty, reason: '${caso.nombre} en $nombreTamano:\n${desbordes.join('\n')}');
      });
    }
  }
}
