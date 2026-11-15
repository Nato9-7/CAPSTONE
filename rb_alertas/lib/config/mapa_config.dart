import 'package:latlong2/latlong.dart';

/// Capa base de todos los mapas de la app (teselas estándar de OpenStreetMap).
class MapaConfig {
  static const String urlTeselas = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String paquete = 'com.rbalertas.rb_alertas';
  static const String atribucion = '© OpenStreetMap contributors';

  /// Centro de Puerto Montt: punto de partida cuando no se conoce la ubicación.
  static const LatLng centroPorDefecto = LatLng(-41.4693, -72.9424);
}
