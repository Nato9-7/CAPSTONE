import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rb_alertas/config/api_config.dart';
import 'package:rb_alertas/servicios/estado_alertas_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/vistas/alertas_vista.dart';
import 'package:rb_alertas/vistas/detalle_incidente_vista.dart';

/// Avisos push (Firebase Cloud Messaging): alertas de zona segura, reportes
/// nuevos en los grupos y comentarios nuevos en los reportes propios o
/// respuestas a un comentario.
///
/// Por ahora solo en Android. Si falta android/app/google-services.json,
/// Firebase no arranca y la app sigue igual, solo que sin avisos push:
/// las alertas se ven de todas formas en la pestaña Alertas.
class PushServicio {
  static const String baseUrl = ApiConfig.baseUrl;
  static const String _ruta = '/api/usuarios/dispositivos';

  /// Mismo id que CANAL_ANDROID en la API (app/push.py).
  static const _canal = AndroidNotificationChannel(
    'alertas_zona',
    'Alertas de zonas seguras',
    description: 'Reportes nuevos cerca de tus zonas seguras',
    importance: Importance.high,
  );

  /// Mismo id que CANAL_COMENTARIOS en la API (app/push.py).
  static const _canalComentarios = AndroidNotificationChannel(
    'comentarios',
    'Comentarios',
    description: 'Comentarios en tus reportes y respuestas a tus comentarios',
    importance: Importance.high,
  );

  /// Lo usa MaterialApp: permite abrir Alertas al tocar un aviso desde
  /// cualquier pantalla.
  static final navegador = GlobalKey<NavigatorState>();

  static final _locales = FlutterLocalNotificationsPlugin();
  static bool _disponible = false;

  /// Datos del aviso con que se abrió la app (si se abrió tocando uno).
  static Map<String, dynamic>? avisoInicial;
  static String? _tokenRegistrado;

  // El identificador del teléfono en FCM (FID) solo llega por onRegistered, y
  // no siempre se repite al volver a registrarse: se guarda para poder
  // asociarlo de nuevo cuando otra cuenta inicia sesión en el mismo teléfono.
  static const _almacen = FlutterSecureStorage();
  static const _claveFid = 'push_fid';

  static bool get _soportado =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Se llama una vez, en la pantalla de bienvenida.
  /// Devuelve `true` si la app se abrió tocando un aviso.
  static Future<bool> inicializar() async {
    if (!_soportado || _disponible) return false;
    try {
      await Firebase.initializeApp();
    } catch (error) {
      debugPrint('[push] Firebase no arrancó: $error');
      return false;
    }
    _disponible = true;
    debugPrint('[push] Firebase listo');

    await _locales.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (respuesta) =>
          abrirDesdeAviso(_datosDeCarga(respuesta.payload)),
    );
    final android = _locales
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(_canal);
    await android?.createNotificationChannel(_canalComentarios);

    // Con la app cerrada o en segundo plano, Android muestra el aviso solo.
    // Con la app abierta FCM no lo muestra, así que se muestra aquí.
    FirebaseMessaging.onMessage.listen(_mostrarEnPrimerPlano);
    FirebaseMessaging.onMessageOpenedApp.listen(
      (mensaje) => abrirDesdeAviso(mensaje.data),
    );
    FirebaseMessaging.instance.onRegistered.listen(_recibirFid);

    avisoInicial = (await FirebaseMessaging.instance.getInitialMessage())?.data;
    return avisoInicial != null;
  }

  /// Pide permiso y registra el teléfono en la API para la cuenta actual.
  /// Se llama al iniciar sesión y al abrir la app con una sesión guardada.
  static Future<void> registrar() async {
    debugPrint(
      '[push] registrar: firebase=$_disponible, sesion=${Sesion.token != null}',
    );
    if (!_disponible || Sesion.token == null) return;
    try {
      final permiso = await FirebaseMessaging.instance.requestPermission();
      debugPrint('[push] permiso: ${permiso.authorizationStatus}');
      if (permiso.authorizationStatus == AuthorizationStatus.denied) return;
      final guardado = await _almacen.read(key: _claveFid);
      debugPrint('[push] FID guardado: $guardado');
      if (guardado != null && guardado.isNotEmpty) {
        await _enviarToken(guardado);
      }
      // Si el FID es nuevo o cambió, llega por onRegistered.
      await FirebaseMessaging.instance.register();
      debugPrint('[push] register() terminó, esperando onRegistered');
    } catch (error) {
      debugPrint('[push] registrar falló: $error');
      // se reintenta la próxima vez que se abra la app
    }
  }

  /// Al cerrar sesión, antes de revocar el token de sesión en la API:
  /// el teléfono deja de recibir avisos de esa cuenta.
  static Future<void> darDeBaja(String tokenSesion) async {
    final tokenPush = _tokenRegistrado;
    if (tokenPush == null) return;
    _tokenRegistrado = null;
    try {
      await http.post(
        Uri.parse('$baseUrl$_ruta/baja'),
        headers: {
          'Authorization': 'Bearer $tokenSesion',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'token_push': tokenPush}),
      );
    } catch (_) {
      // aunque falle, la sesión se cierra igual en la app
    }
  }

  /// Id del reporte si el aviso abre un reporte (comentario o reporte de un
  /// grupo); null si es una alerta de zona, que abre la pestaña Alertas.
  static int? reporteDeAviso(Map<String, dynamic>? datos) {
    final tipo = datos?['tipo'];
    if (tipo != 'COMENTARIO' && tipo != 'GRUPO') return null;
    return int.tryParse('${datos!['id_reporte'] ?? ''}');
  }

  /// Los avisos de comentario bajan hasta la conversación y van por su canal.
  static bool esAvisoDeComentario(Map<String, dynamic>? datos) =>
      datos?['tipo'] == 'COMENTARIO';

  /// Un aviso de comentario o de grupo abre su reporte; el resto, la pestaña Alertas.
  static void abrirDesdeAviso(Map<String, dynamic>? datos) {
    final idReporte = reporteDeAviso(datos);
    idReporte != null
        ? abrirReporte(idReporte, irAComentarios: esAvisoDeComentario(datos))
        : abrirAlertas();
  }

  /// Abre el detalle encima de la pantalla actual, para volver a ella con «atrás».
  static void abrirReporte(int idReporte, {bool irAComentarios = true}) {
    if (Sesion.token == null || Sesion.esAdmin) return;
    navegador.currentState?.push(
      MaterialPageRoute(
        builder: (context) =>
            DetalleIncidenteVista(idReporte: idReporte, irAComentarios: irAComentarios),
      ),
    );
  }

  static Map<String, dynamic>? _datosDeCarga(String? carga) {
    if (carga == null || carga.isEmpty) return null;
    try {
      return jsonDecode(carga) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static void abrirAlertas() {
    if (Sesion.token == null || Sesion.esAdmin) return;
    navegador.currentState?.pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (context, animacion, animacionSecundaria) =>
            const AlertasVista(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      (ruta) => false,
    );
  }

  static Future<void> _recibirFid(String fid) async {
    debugPrint('[push] onRegistered: $fid');
    try {
      await _almacen.write(key: _claveFid, value: fid);
    } catch (_) {
      // solo se pierde el respaldo; el envío de abajo no depende de él
    }
    if (fid != _tokenRegistrado) await _enviarToken(fid);
  }

  static Future<void> _enviarToken(String tokenPush) async {
    final tokenSesion = Sesion.token;
    if (tokenSesion == null) return;
    try {
      final equipo = await DeviceInfoPlugin().androidInfo;
      final paquete = await PackageInfo.fromPlatform();
      final respuesta = await http.post(
        Uri.parse('$baseUrl$_ruta/'),
        headers: {
          'Authorization': 'Bearer $tokenSesion',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'token_push': tokenPush,
          'plataforma': 'ANDROID',
          'modelo': _recortar('${equipo.manufacturer} ${equipo.model}', 100),
          'version_so': _recortar('Android ${equipo.version.release}', 40),
          'version_app': _recortar(
            '${paquete.version}+${paquete.buildNumber}',
            20,
          ),
        }),
      );
      debugPrint(
        '[push] API dispositivos: ${respuesta.statusCode} ${respuesta.body}',
      );
      if (respuesta.statusCode == 204) _tokenRegistrado = tokenPush;
    } catch (error) {
      debugPrint('[push] envío a la API falló: $error');
      // se reintenta la próxima vez que se abra la app
    }
  }

  static Future<void> _mostrarEnPrimerPlano(RemoteMessage mensaje) async {
    final esComentario = esAvisoDeComentario(mensaje.data);
    // Las alertas de zona y de grupo suman a la insignia de Alertas.
    if (!esComentario) EstadoAlertas.refrescarZonasSinLeer();
    final aviso = mensaje.notification;
    if (aviso == null) return;
    final canal = esComentario ? _canalComentarios : _canal;
    await _locales.show(
      id: int.tryParse(mensaje.data['id_notificacion'] ?? '') ??
          mensaje.hashCode,
      title: aviso.title,
      body: aviso.body,
      // Al tocarlo, abrirDesdeAviso recibe estos mismos datos.
      payload: jsonEncode(mensaje.data),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          canal.id,
          canal.name,
          channelDescription: canal.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  static String _recortar(String texto, int largo) =>
      texto.length <= largo ? texto : texto.substring(0, largo);
}
