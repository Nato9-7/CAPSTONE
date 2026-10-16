import 'package:flutter/material.dart';
import 'package:rb_alertas/tema/rb_tema.dart';

/// Ícono de una categoria_incidente según su código (ACCIDENTE, ROBO, ...).
/// El ícono distingue la categoría aunque el color no se perciba.
IconData iconoCategoria(String codigo) {
  final c = codigo.toLowerCase();
  if (c.contains('accidente')) return Icons.directions_car_filled_outlined;
  if (c.contains('robo') || c.contains('asalto')) return Icons.business_center_outlined;
  if (c.contains('mascota')) return Icons.pets_rounded;
  if (c.contains('incendio')) return Icons.local_fire_department_outlined;
  if (c.contains('sospech')) return Icons.visibility_outlined;
  if (c.contains('emergencia') || c.contains('medic') || c.contains('salud')) {
    return Icons.local_hospital_outlined;
  }
  if (c.contains('vial')) return Icons.construction_rounded;
  return Icons.error_outline_rounded;
}

/// Nombre corto para espacios angostos, como los filtros del mapa
/// ("Robo o asalto" -> "Robos"). Si la categoría es nueva, usa su primera palabra.
String etiquetaCortaCategoria(String codigo, String nombre) {
  final c = codigo.toLowerCase();
  if (c.contains('accidente')) return 'Accidentes';
  if (c.contains('robo') || c.contains('asalto')) return 'Robos';
  if (c.contains('mascota')) return 'Mascotas';
  if (c.contains('incendio')) return 'Incendios';
  if (c.contains('sospech')) return 'Sospechosos';
  if (c.contains('emergencia') || c.contains('medic') || c.contains('salud')) {
    return 'Médicas';
  }
  if (c.contains('vial')) return 'Vial';
  final primera = nombre.split(' ').first;
  return primera.isEmpty ? nombre : primera;
}

/// Nombre en singular para la grilla de "¿Qué está pasando?"
/// ("Robo o asalto" -> "Robo", "Emergencia médica" -> "Médica").
String nombreCortoCategoria(String codigo, String nombre) {
  final c = codigo.toLowerCase();
  if (c.contains('accidente')) return 'Accidente';
  if (c.contains('robo') || c.contains('asalto')) return 'Robo';
  if (c.contains('mascota')) return 'Mascota';
  if (c.contains('incendio')) return 'Incendio';
  if (c.contains('sospech')) return 'Sospechoso';
  if (c.contains('emergencia') || c.contains('medic') || c.contains('salud')) {
    return 'Médica';
  }
  if (c.contains('vial')) return 'Vial';
  final primera = nombre.split(' ').first;
  return primera.isEmpty ? nombre : primera;
}

/// Color de la categoría: usa color_hex de la BD si viene; si no, el de la
/// paleta de categorías del sistema visual.
Color colorCategoria(String codigo, {String? colorHex}) {
  final hex = colorHex?.replaceFirst('#', '');
  final valor = hex != null && hex.length == 6 ? int.tryParse(hex, radix: 16) : null;
  if (valor != null) return Color(0xFF000000 | valor);

  final c = codigo.toLowerCase();
  if (c.contains('accidente')) return const Color(0xFFC62828);
  if (c.contains('robo') || c.contains('asalto')) return const Color(0xFF6D28D9);
  if (c.contains('mascota')) return const Color(0xFFB45309);
  if (c.contains('incendio')) return const Color(0xFFD2490B);
  if (c.contains('sospech')) return const Color(0xFF475569);
  if (c.contains('emergencia') || c.contains('medic') || c.contains('salud')) {
    return const Color(0xFFBE185D);
  }
  if (c.contains('vial')) return const Color(0xFF8A6A00);
  return RBColores.azul;
}

/// Cuadrado redondeado con el ícono blanco de la categoría, como en las
/// listas de alertas y en la grilla de reportar.
class IconoCategoria extends StatelessWidget {
  final String codigo;
  final String? colorHex;
  final double tamano;

  const IconoCategoria({
    super.key,
    required this.codigo,
    this.colorHex,
    this.tamano = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        color: colorCategoria(codigo, colorHex: colorHex),
        borderRadius: BorderRadius.circular(tamano * 0.28),
      ),
      child: Icon(
        iconoCategoria(codigo),
        color: Colors.white,
        size: tamano * 0.46,
      ),
    );
  }
}
