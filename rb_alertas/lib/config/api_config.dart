class ApiConfig {
  // API desplegada en el VPS, detrás de Caddy con HTTPS (ver Documentacion_docker_rbAlerta.md).
  // El puerto 8000 ya no está publicado desde el 03-10-2026.
  // Para apuntar a una API local:
  //   flutter run --dart-define=API_URL=http://localhost:8000
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://rbalerta.duckdns.org',
  );

  /// URL completa de un archivo servido por la API (p. ej. "/uploads/reportes/x.jpg").
  static String urlArchivo(String ruta) =>
      ruta.startsWith('http') ? ruta : '$baseUrl$ruta';
}
