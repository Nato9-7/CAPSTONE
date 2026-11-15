// Validadores de los formularios de cuenta. Devuelven el texto del error o
// null si el valor es válido, como espera TextFormField.validator.

final _regexEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _regexRut = RegExp(r'^\d{7,8}-[\dkK]$');
final _regexMovil = RegExp(r'^\d{8}$');

String? validarRequerido(String? valor, String campo) =>
    (valor == null || valor.trim().isEmpty) ? 'Ingresa tu $campo' : null;

String? validarEmail(String? valor) {
  if (valor == null || valor.trim().isEmpty) return 'Ingresa tu correo electrónico';
  if (!_regexEmail.hasMatch(valor.trim())) return 'Ingresa un correo válido';
  return null;
}

/// El RUT se puede escribir con puntos (12.345.678-9), pero se valida y se
/// envía sin ellos: 12345678-9.
String rutSinPuntos(String valor) => valor.trim().replaceAll('.', '');

String? validarRut(String? valor) {
  if (valor == null || valor.trim().isEmpty) return 'Ingresa tu RUT';
  if (!_regexRut.hasMatch(rutSinPuntos(valor))) return 'Formato inválido (ej: 12.345.678-9)';
  return null;
}

/// Los 8 dígitos del móvil que van después del prefijo fijo +56 9.
String? validarMovil(String? valor) {
  if (valor == null || valor.trim().isEmpty) return 'Ingresa tu teléfono móvil';
  if (!_regexMovil.hasMatch(valor.replaceAll(' ', ''))) return 'Ingresa los 8 dígitos de tu móvil';
  return null;
}

String? validarPasswordNueva(String? valor) {
  if (valor == null || valor.isEmpty) return 'Ingresa una contraseña';
  if (valor.length < 8) return 'Debe tener al menos 8 caracteres';
  return null;
}
