import 'package:flutter/material.dart';
import 'package:rb_alertas/tema/rb_tema.dart';

/// Píldora "Admin" junto al nombre del grupo o del vecino.
class ChipAdmin extends StatelessWidget {
  const ChipAdmin({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: RBColores.azul50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'Admin',
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: RBColores.azul),
      ),
    );
  }
}
