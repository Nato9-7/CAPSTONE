/// Datos visibles de la versión de la app (bienvenida y pie del perfil).
class AppInfo {
  static const String version = 'Alpha 1.0.0';

  /// Enlace para descargar el APK, que va en el mensaje de invitación a un
  /// grupo. Vacío, el mensaje sale solo con el código:
  ///   flutter build apk --dart-define=URL_DESCARGA=https://...
  static const String urlDescarga = String.fromEnvironment('URL_DESCARGA');
}
