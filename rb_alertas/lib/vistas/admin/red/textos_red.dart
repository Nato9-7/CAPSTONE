/// Nombre visible de cada tipo de elemento.
String nombreTipoRed(String tipo) => switch (tipo) {
  'Usuario' => 'Vecino',
  'Reporte' => 'Reporte',
  'Categoria' => 'Categoría',
  'Comuna' => 'Comuna',
  'Localidad' => 'Localidad',
  'ZonaSegura' => 'Zona segura',
  'Coordinacion' => 'Cuentas coordinadas',
  'Incidente' => 'Incidente',
  'Grupo' => 'Grupo de vecinos',
  _ => tipo,
};

/// Estado de un reporte o de una cuenta, como se lee en el panel de detalle.
String textoEstadoRed(String? estado) => switch (estado) {
  'PENDIENTE' => 'Pendiente',
  'VALIDADO' => 'Validado',
  'RESUELTO' => 'Resuelto',
  'DESCARTADO' => 'Descartado',
  'EXPIRADO' => 'Expirado',
  'ACTIVO' => 'Cuenta activa',
  'SUSPENDIDO' => 'Suspendida',
  _ => estado ?? '',
};

/// Cómo se dice cada sección de hallazgos y qué muestra.
const seccionesHallazgos = [
  (
    'Sospechosos',
    'Cuentas que se confirman los reportes entre ellas mucho más que a los demás. '
        'Puede ser una persona con varias cuentas inflando sus reportes.',
  ),
  (
    'Reputación',
    'De 0 a 100. Sube si lo confirman vecinos confiables y si sus reportes terminan '
        'validados; baja con desmentidos y reportes descartados.',
  ),
  (
    'Incidentes',
    'Reportes del mismo hecho (misma categoría, a menos de 300 m y 3 horas) que la app '
        'muestra como un solo incidente.',
  ),
  (
    'Zonas',
    'Los lugares con más hechos en el período de la línea de tiempo (si varios vecinos '
        'reportan el mismo robo, cuenta una vez). Elige una categoría para ver, por '
        'ejemplo, dónde hay más robos.',
  ),
];
