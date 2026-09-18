import 'package:flutter/material.dart';

/// Ícono de una categoria_incidente según su código (ACCIDENTE, ROBO, ...).
IconData iconoCategoria(String codigo) {
  final c = codigo.toLowerCase();
  if (c.contains('accidente')) return Icons.car_crash_rounded;
  if (c.contains('robo') || c.contains('asalto')) return Icons.back_hand_outlined;
  if (c.contains('mascota')) return Icons.pets_rounded;
  if (c.contains('incendio')) return Icons.local_fire_department_rounded;
  if (c.contains('sospech')) return Icons.visibility_outlined;
  if (c.contains('medic') || c.contains('salud')) return Icons.medical_services_outlined;
  return Icons.report_gmailerrorred_rounded;
}

/// Color de la categoría: usa color_hex de la BD si viene, si no uno por código.
Color colorCategoria(String codigo, {String? colorHex}) {
  final hex = colorHex?.replaceFirst('#', '');
  final valor = hex != null && hex.length == 6 ? int.tryParse(hex, radix: 16) : null;
  if (valor != null) return Color(0xFF000000 | valor);

  final c = codigo.toLowerCase();
  if (c.contains('accidente')) return const Color(0xFFE53935);
  if (c.contains('robo') || c.contains('asalto')) return const Color(0xFFF59E0B);
  if (c.contains('mascota')) return const Color(0xFF10B981);
  return const Color(0xFF0056D2);
}
