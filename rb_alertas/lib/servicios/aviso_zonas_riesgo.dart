// Aviso al pasar por una zona de riesgo (robos o accidentes frecuentes).
//
// - Con la app abierta: el mapa sigue la ubicación en vivo y, al entrar a una
//   zona, muestra el banner y manda el aviso ([alEntrar]).
// - Con la app cerrada: Android vigila las zonas con geocercas
//   (android/.../ZonasRiesgo.kt) y manda el aviso él mismo. Necesita el
//   permiso de ubicación "Permitir todo el tiempo".
//
// La misma zona no avisa dos veces en 6 horas, venga el aviso de donde venga.
// Solo en Android; en web y en las pruebas no hace nada.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rb_alertas/servicios/reporte_servicio.dart';
import 'package:rb_alertas/widgets/zonas_riesgo_mapa.dart';

/// Resultado de pedir que se active el aviso con la app cerrada.
enum ActivacionAviso { activado, soloConAppAbierta, sinPermiso }

class AvisoZonasRiesgo {
  static const _canal = MethodChannel('cl.rbalertas/zonas_riesgo');
  static const _almacen = FlutterSecureStorage();
  static const _clave = 'aviso_zonas_riesgo';

  /// Si el usuario quiere el aviso. null mientras no se sepa (o no se le
  /// haya preguntado). Lo escucha el interruptor de la tarjeta de zona.
  static final activo = ValueNotifier<bool?>(null);

  static List<ZonaRiesgo> _ultimasZonas = const [];

  static bool get soportado => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Lee la preferencia guardada. Devuelve null si nunca se preguntó.
  static Future<bool?> cargarPreferencia() async {
    if (!soportado) return false;
    try {
      final valor = await _almacen.read(key: _clave);
      activo.value = valor == null ? null : valor == 'si';
    } catch (_) {
      // Sin almacenamiento (p. ej. en pruebas) no se pregunta ni se avisa.
      activo.value = false;
    }
    return activo.value;
  }

  static Future<void> _guardar(bool valor) async {
    activo.value = valor;
    try {
      await _almacen.write(key: _clave, value: valor ? 'si' : 'no');
    } catch (_) {}
  }

  /// Id estable de una zona: mismo tipo y mismo centro, misma zona.
  static String idZona(ZonaRiesgo z) =>
      '${z.tipo}:${z.latitud.toStringAsFixed(4)},${z.longitud.toStringAsFixed(4)}';

  static String textoAviso(ZonaRiesgo z) {
    final que = z.esSeguridad ? 'robos frecuentes' : 'accidentes frecuentes';
    return 'Estás pasando por una zona con $que. ${z.recomendacion}'.trim();
  }

  /// Entrega las zonas a Android para que las vigile con la app cerrada.
  /// Se llama cada vez que el mapa carga zonas nuevas.
  static Future<void> sincronizar(List<ZonaRiesgo> zonas) async {
    _ultimasZonas = zonas;
    if (!soportado || activo.value != true) return;
    final datos = [
      for (final z in zonas)
        {
          'id': idZona(z),
          'latitud': z.latitud,
          'longitud': z.longitud,
          'radio': z.radioMetros,
          'titulo': tituloZona(z),
          'texto': textoAviso(z),
        },
    ];
    try {
      await _canal.invokeMethod('registrar', {'zonas': jsonEncode(datos)});
    } catch (error) {
      debugPrint('[zonas] no se pudieron vigilar: $error');
    }
  }

  /// Con la app abierta: el usuario acaba de entrar a [zona].
  static Future<void> alEntrar(ZonaRiesgo zona) async {
    if (!soportado || activo.value != true) return;
    try {
      await _canal.invokeMethod('notificar', {
        'id': idZona(zona),
        'titulo': tituloZona(zona),
        'texto': textoAviso(zona),
      });
    } catch (_) {}
  }

  /// ¿Android está vigilando con la app cerrada?
  static Future<bool> vigilaConAppCerrada() async {
    if (!soportado) return false;
    try {
      return await _canal.invokeMethod<bool>('tienePermisoDeFondo') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Pide los permisos (notificaciones y ubicación "todo el tiempo") y deja
  /// el aviso activado. Llamar después de explicarle al usuario para qué.
  static Future<ActivacionAviso> activar() async {
    if (!soportado) return ActivacionAviso.sinPermiso;
    await _pedirPermisoNotificaciones();

    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }
    if (permiso == LocationPermission.denied || permiso == LocationPermission.deniedForever) {
      return ActivacionAviso.sinPermiso;
    }
    // Segunda vez: Android pregunta por "Permitir todo el tiempo" (desde
    // Android 11 abre los ajustes de la app para elegirlo).
    if (permiso == LocationPermission.whileInUse) {
      permiso = await Geolocator.requestPermission();
    }

    await _guardar(true);
    await sincronizar(_ultimasZonas);
    return permiso == LocationPermission.always
        ? ActivacionAviso.activado
        : ActivacionAviso.soloConAppAbierta;
  }

  static Future<void> desactivar() async {
    await _guardar(false);
    if (!soportado) return;
    try {
      await _canal.invokeMethod('quitar');
    } catch (_) {}
  }

  /// El usuario dijo que no al ofrecerle el aviso: no se vuelve a preguntar.
  static Future<void> rechazar() => _guardar(false);

  static Future<void> _pedirPermisoNotificaciones() async {
    try {
      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }
}
