// Textos derivados que se muestran en varias pantallas.

String _dosDigitos(int n) => n.toString().padLeft(2, '0');

/// "hace 12 min", "hace 3 h", "ayer"... para fechas de reportes y alertas.
String tiempoRelativo(DateTime? fecha) {
  if (fecha == null) return '';
  final diferencia = DateTime.now().difference(fecha);
  if (diferencia.isNegative || diferencia.inMinutes < 1) return 'recién';
  if (diferencia.inMinutes < 60) return 'hace ${diferencia.inMinutes} min';
  if (diferencia.inHours < 24) return 'hace ${diferencia.inHours} h';
  if (diferencia.inDays == 1) return 'ayer';
  if (diferencia.inDays < 7) return 'hace ${diferencia.inDays} días';
  if (diferencia.inDays < 30) {
    final semanas = diferencia.inDays ~/ 7;
    return semanas == 1 ? 'hace 1 semana' : 'hace $semanas semanas';
  }
  return '${_dosDigitos(fecha.day)}/${_dosDigitos(fecha.month)}/${fecha.year}';
}

/// Igual que [tiempoRelativo], con mayúscula inicial ("Hace 12 min").
String tiempoRelativoInicio(DateTime? fecha) => capitalizar(tiempoRelativo(fecha));

/// "12 min" sin el "hace", para etiquetas compactas ("Accidente · 12 min").
String tiempoCorto(DateTime? fecha) {
  final texto = tiempoRelativo(fecha);
  return texto.startsWith('hace ') ? texto.substring(5) : texto;
}

/// "dd-mm-aaaa hh:mm", o vacío si no hay fecha.
String fechaHora(DateTime? fecha) {
  if (fecha == null) return '';
  return '${_dosDigitos(fecha.day)}-${_dosDigitos(fecha.month)}-${fecha.year} '
      '${_dosDigitos(fecha.hour)}:${_dosDigitos(fecha.minute)}';
}

String capitalizar(String texto) =>
    texto.isEmpty ? texto : texto[0].toUpperCase() + texto.substring(1);

/// "350 m" o "1,2 km", con coma decimal.
String distanciaLegible(num metros) {
  if (metros < 1000) return '${metros.round()} m';
  final km = metros / 1000;
  final texto = km.toStringAsFixed(km >= 10 || km == km.roundToDouble() ? 0 : 1);
  return '${texto.replaceAll('.', ',')} km';
}

/// Radio de un área: "500 m", "1 km" o "1,5 km".
String textoRadio(int metros) => metros < 1000
    ? '$metros m'
    : '${(metros / 1000).toStringAsFixed(metros % 1000 == 0 ? 0 : 1).replaceAll('.', ',')} km';

/// La BD no guarda un título: se arma con la categoría y la calle
/// ("Accidente en Av. Diego Portales").
String tituloReporte(String categoria, String? direccion) {
  final calle = direccion?.split(',').first.trim();
  return (calle == null || calle.isEmpty) ? categoria : '$categoria en $calle';
}
