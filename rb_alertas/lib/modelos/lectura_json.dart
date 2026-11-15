/// Lectura tolerante de los campos que entrega la API: un campo ausente o
/// nulo toma el valor por defecto en vez de romper la pantalla.
extension LecturaJson on Map<String, dynamic> {
  String texto(String clave, [String porDefecto = '']) =>
      (this[clave] ?? porDefecto).toString();

  String? textoOpcional(String clave) => this[clave]?.toString();

  int entero(String clave, [int porDefecto = 0]) =>
      (this[clave] as num?)?.toInt() ?? porDefecto;

  int? enteroOpcional(String clave) => (this[clave] as num?)?.toInt();

  double decimal(String clave, [double porDefecto = 0]) =>
      (this[clave] as num?)?.toDouble() ?? porDefecto;

  double? decimalOpcional(String clave) => (this[clave] as num?)?.toDouble();

  bool booleano(String clave) => this[clave] == true;

  DateTime? fecha(String clave) => DateTime.tryParse(this[clave]?.toString() ?? '');

  /// Como [fecha], pero en la hora del teléfono.
  DateTime? fechaLocal(String clave) => fecha(clave)?.toLocal();

  /// Lista de objetos JSON convertidos con [desdeJson].
  List<T> lista<T>(String clave, T Function(Map<String, dynamic>) desdeJson) => [
    for (final e in (this[clave] as List? ?? const [])) desdeJson(e as Map<String, dynamic>),
  ];

  List<int> enteros(String clave, [List<int> porDefecto = const []]) => [
    for (final e in (this[clave] as List? ?? porDefecto)) (e as num).toInt(),
  ];

  List<String> textos(String clave) => [
    for (final e in (this[clave] as List? ?? const [])) e.toString(),
  ];

  Map<String, dynamic> mapa(String clave) =>
      (this[clave] as Map?)?.cast<String, dynamic>() ?? {};
}

/// Convierte una lista JSON (respuesta de la API) con [desdeJson].
List<T> listaDesdeJson<T>(Object? json, T Function(Map<String, dynamic>) desdeJson) => [
  for (final e in (json as List? ?? const [])) desdeJson(e as Map<String, dynamic>),
];
