class ApiConfig {
  // API desplegada en el VPS (ver Documentacion_docker_rbAlerta.md).
  // Para apuntar a una API local:
  //   flutter run --dart-define=API_URL=http://localhost:8000
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://129.213.86.163:8000',
  );

  /// URL completa de un archivo servido por la API (p. ej. "/uploads/reportes/x.jpg").
  static String urlArchivo(String ruta) =>
      ruta.startsWith('http') ? ruta : '$baseUrl$ruta';
}
