import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Períodos de la línea de tiempo (null = toda la historia).
const periodosRed = <(int?, String)>[
  (7, '7 días'),
  (30, '30 días'),
  (90, '3 meses'),
  (365, '1 año'),
  (null, 'Todo'),
];

/// Capas que se pueden sumar en la vista "Red completa".
const capasRed = <(String, String, IconData)>[
  ('lugares', 'Lugares', Icons.place_rounded),
  ('categorias', 'Categorías', Icons.category_rounded),
  ('incidentes', 'Incidentes', Icons.layers_rounded),
  ('sospechosos', 'Grupos sospechosos', Icons.gpp_maybe_rounded),
  ('grupos', 'Grupos de vecinos', Icons.groups_rounded),
  ('zonas', 'Zonas seguras', Icons.shield_rounded),
];

/// Categorías que se pueden filtrar en la red: robos y accidentes de tránsito.
const categoriasFiltrablesRed = {'ROBO', 'ACCIDENTE'};

/// Qué parte de la red se pide a la API.
@immutable
class FiltrosRed {
  /// 'vecinos' (quién apoya a quién), 'completa' o 'zonas' (dónde ocurre más).
  final String modo;

  /// Índice en [periodosRed].
  final int periodo;
  final Set<String> capas;

  /// Categoría elegida para la red y el ranking de zonas (null = todas).
  final String? categoria;

  const FiltrosRed({
    this.modo = 'vecinos',
    this.periodo = 4,
    this.capas = const {'lugares', 'incidentes', 'sospechosos', 'grupos'},
    this.categoria,
  });

  int? get dias => periodosRed[periodo].$1;
  String get nombrePeriodo => periodosRed[periodo].$2;

  FiltrosRed conModo(String valor) => FiltrosRed(modo: valor, periodo: periodo, capas: capas, categoria: categoria);

  FiltrosRed conPeriodo(int valor) => FiltrosRed(modo: modo, periodo: valor, capas: capas, categoria: categoria);

  FiltrosRed conCategoria(String? valor) => FiltrosRed(modo: modo, periodo: periodo, capas: capas, categoria: valor);

  /// Agrega la capa si no estaba, o la quita si estaba.
  FiltrosRed alternarCapa(String capa) => FiltrosRed(
    modo: modo,
    periodo: periodo,
    capas: capas.contains(capa) ? ({...capas}..remove(capa)) : {...capas, capa},
    categoria: categoria,
  );

  @override
  bool operator ==(Object other) =>
      other is FiltrosRed &&
      other.modo == modo &&
      other.periodo == periodo &&
      other.categoria == categoria &&
      setEquals(other.capas, capas);

  @override
  int get hashCode => Object.hash(modo, periodo, categoria, Object.hashAllUnordered(capas));
}
