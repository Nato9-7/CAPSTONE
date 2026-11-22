import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// API simulada para las pruebas de pantallas: responde con datos de ejemplo
/// (con textos largos a propósito) para que cada vista se dibuje con contenido.
MockClient clienteApiFalsa() {
  return MockClient((peticion) async {
    final ruta = peticion.url.path;
    // Teselas del mapa: un PNG gris de 1x1 basta para que el mapa se dibuje.
    if (peticion.url.host.contains('openstreetmap')) {
      return http.Response.bytes(_teselaGris, 200, headers: {'content-type': 'image/png'});
    }
    final cuerpo = _responder(peticion.method, ruta, peticion.url.queryParameters);
    if (cuerpo == null) {
      return http.Response(jsonEncode({'detail': 'No encontrado'}), 404);
    }
    return http.Response.bytes(
      utf8.encode(jsonEncode(cuerpo)),
      peticion.method == 'POST' && ruta == '/api/reportes/' ? 201 : 200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

final _teselaGris = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAFUlEQVR4nGN88eotAzbAhFV00EoAACbbAs+kK2qeAAAAAElFTkSuQmCC',
);

final _ahora = DateTime.now();
String _hace(Duration d) => _ahora.subtract(d).toIso8601String();

Object? _responder(String metodo, String ruta, [Map<String, String> consulta = const {}]) {
  if (ruta == '/api/reportes/categorias') return _categorias;
  if (ruta == '/api/reportes/') return _reportesMapa;
  if (ruta == '/api/reportes/cercanos') {
    return {'radio_metros': 2000, 'total': _cercanos.length, 'reportes': _cercanos};
  }
  if (ruta == '/api/reportes/mios') return _misReportes;
  if (ruta == '/api/reportes/calor') return {'dias': 60, 'puntos': _calor};
  if (ruta == '/api/reportes/zonas-riesgo') return {'dias': 60, 'zonas': _zonasRiesgo};
  if (RegExp(r'^/api/reportes/\d+$').hasMatch(ruta)) return _detalle;
  if (RegExp(r'^/api/reportes/\d+/comentarios$').hasMatch(ruta)) return _comentarios;
  if (ruta == '/api/usuarios/comunas') return _regiones;
  if (ruta == '/api/usuarios/perfil') return _perfil;
  if (ruta == '/api/usuarios/zonas/') return _zonas;
  if (ruta == '/api/grupos/') return _grupos;
  if (ruta == '/api/grupos/en-punto') return _gruposEnPunto;
  if (ruta == '/api/grupos/1') return _grupoAdmin;
  if (ruta == '/api/grupos/2') return _grupoMiembro;
  if (RegExp(r'^/api/grupos/\d+/reportes$').hasMatch(ruta)) return _reportesGrupo;
  if (RegExp(r'^/api/grupos/\d+/miembros$').hasMatch(ruta)) return _miembrosGrupo;
  if (ruta.startsWith('/api/grupos/invitacion/')) return _invitacionGrupo;
  if (ruta == '/api/usuarios/notificaciones/') return _notificaciones;
  if (ruta == '/api/admin/resumen') return _resumenAdmin;
  if (ruta == '/api/admin/reportes') return _paginaReportesAdmin(consulta['estado']);
  if (ruta == '/api/admin/usuarios') return _usuariosAdmin;
  if (ruta == '/api/admin/grupos') return _gruposAdmin;
  if (RegExp(r'^/api/admin/grupos/\d+/reportes$').hasMatch(ruta)) return _reportesGrupoAdmin;
  if (ruta == '/api/admin/grafo/resumen') return _resumenGrafo;
  if (ruta == '/api/admin/grafo/zonas') return _zonasCalientes(consulta['categoria']);
  if (ruta == '/api/admin/grafo/red') return _redGrafo(consulta['categoria']);
  if (ruta == '/api/admin/analisis/filtros') return _filtrosAnalisis;
  if (ruta == '/api/admin/analisis/por-dia') return _porDia(int.tryParse(consulta['dias'] ?? '') ?? 30);
  if (ruta == '/api/admin/analisis/calles') return _callesAnalisis(consulta['categoria']);
  if (ruta == '/api/admin/analisis/sectores') return _sectoresAnalisis;
  return null;
}

const _categorias = [
  {'id_categoria': 1, 'codigo': 'ACCIDENTE', 'nombre': 'Accidente de tránsito', 'color_hex': '#C62828'},
  {'id_categoria': 2, 'codigo': 'ROBO', 'nombre': 'Robo o asalto', 'color_hex': '#6D28D9'},
  {'id_categoria': 3, 'codigo': 'MASCOTA', 'nombre': 'Mascota perdida', 'color_hex': '#B45309'},
  {'id_categoria': 4, 'codigo': 'INCENDIO', 'nombre': 'Incendio', 'color_hex': '#D2490B'},
  {'id_categoria': 5, 'codigo': 'SOSPECHOSO', 'nombre': 'Actividad sospechosa', 'color_hex': '#475569'},
  {'id_categoria': 6, 'codigo': 'EMERGENCIA_MEDICA', 'nombre': 'Emergencia médica', 'color_hex': '#BE185D'},
  {'id_categoria': 7, 'codigo': 'VIAL', 'nombre': 'Problema vial', 'color_hex': '#8A6A00'},
  {'id_categoria': 8, 'codigo': 'OTRO', 'nombre': 'Otro', 'color_hex': '#002366'},
];

Map<String, Object?> _reporte(
  int id,
  String codigo,
  String categoria,
  String direccion,
  String estado,
  Duration hace, {
  double distancia = 350,
  int confirmaciones = 8,
}) =>
    {
      'id_reporte': id,
      'categoria_codigo': codigo,
      'categoria': categoria,
      'color_hex': null,
      'latitud': -41.4693 + id * 0.002,
      'longitud': -72.9424 + id * 0.002,
      'direccion': direccion,
      'descripcion': 'Choque entre dos autos frente a la Costanera. Hay una pista '
          'bloqueada en dirección a Angelmó y mucho taco.',
      'estado': estado,
      'fecha_creacion': _hace(hace),
      'distancia_metros': distancia,
      'total_confirmaciones': confirmaciones,
      'total_desmentidos': 1,
    };

final _cercanos = [
  _reporte(1, 'ACCIDENTE', 'Accidente de tránsito', 'Avenida Diego Portales 1150, Puerto Montt',
      'VALIDADO', const Duration(minutes: 12)),
  _reporte(2, 'MASCOTA', 'Mascota perdida', 'Sector Pelluco Alto, Puerto Montt', 'PENDIENTE',
      const Duration(minutes: 40), distancia: 1200, confirmaciones: 3),
  _reporte(3, 'ROBO', 'Robo o asalto', 'Calle Urmeneta, Puerto Montt', 'PENDIENTE',
      const Duration(hours: 1), distancia: 800, confirmaciones: 5),
  _reporte(4, 'VIAL', 'Problema vial', 'Avenida Presidente Ibáñez, Puerto Montt', 'VALIDADO',
      const Duration(hours: 26), distancia: 1600, confirmaciones: 12),
];

final _reportesMapa = _cercanos;

final _misReportes = [
  {..._reporte(2, 'MASCOTA', 'Mascota perdida', 'Sector Pelluco', 'PENDIENTE', const Duration(minutes: 40)), 'estado_visual': 'ACTIVA', 'zona': 'Pelluco'},
  {..._reporte(4, 'VIAL', 'Problema vial', 'Avenida Presidente Ibáñez', 'RESUELTO', const Duration(days: 1)), 'estado_visual': 'RESUELTA', 'zona': 'Centro'},
  {..._reporte(5, 'VIAL', 'Problema vial', 'Calle Benavente', 'EXPIRADO', const Duration(days: 5)), 'estado_visual': 'VENCIDA', 'zona': null},
  {..._reporte(6, 'SOSPECHOSO', 'Actividad sospechosa', 'Avenida Angelmó', 'DESCARTADO', const Duration(days: 15)), 'estado_visual': 'DESCARTADA', 'zona': null},
];

Map<String, Object?> _comentario(
  int id,
  String autor,
  String contenido,
  Duration hace, {
  int? padre,
  String estado = 'PUBLICADO',
  bool esMio = false,
  bool esAutorReporte = false,
  List<Object?> respuestas = const [],
}) =>
    {
      'id_comentario': id,
      'id_comentario_padre': padre,
      'estado': estado,
      'autor': estado == 'PUBLICADO' ? autor : null,
      'es_autor_reporte': esAutorReporte,
      'es_mio': esMio,
      'contenido': estado == 'PUBLICADO' ? contenido : null,
      'imagen': null,
      'fecha_creacion': _hace(hace),
      if (padre == null) 'respuestas': respuestas,
    };

final _comentarios = {
  'total': 4,
  'puede_comentar': true,
  'comentarios': [
    _comentario(
      1,
      'Suricata Alerta 07',
      'Pasé por ahí recién: ya llegó Carabineros y están desviando el tránsito por Urmeneta '
          'y por la costanera hacia el sector de Angelmó.',
      const Duration(minutes: 8),
      respuestas: [
        _comentario(2, 'Suricata Centinela 42', 'Gracias por avisar, voy por otra ruta.',
            const Duration(minutes: 6), padre: 1, esAutorReporte: true),
      ],
    ),
    _comentario(3, '', '', const Duration(minutes: 5), estado: 'ELIMINADO', respuestas: [
      _comentario(4, 'Suricata Exploradora Intrépida 58', 'Ojo con el taco hacia Angelmó, mejor tomar otra ruta.',
          const Duration(minutes: 2), padre: 3, esMio: true),
    ]),
    _comentario(5, 'Suricata Atenta 34', 'Se ve una ambulancia en el lugar, al parecer no hay heridos graves.',
        const Duration(minutes: 1)),
  ],
};

final _detalle = {
  ..._reporte(1, 'ACCIDENTE', 'Accidente de tránsito', 'Avenida Diego Portales 1150, Puerto Montt',
      'VALIDADO', const Duration(minutes: 12)),
  'autor': 'Suricata Despierta 21',
  'es_autor': false,
  'imagenes': <String>[],
  'emergencia': {'nombre': 'SAMU Puerto Montt', 'tipo': 'SAMU', 'telefono': '131'},
  'mi_voto': 'CONFIRMA',
  'total_comentarios': 4,
};

const _perfil = {
  'nombres': 'Renato Alejandro',
  'apellidos': 'Díaz Valenzuela',
  'email': 'vecino@correo.cl',
  'url_foto_perfil': null,
  'email_verificado': true,
  'comuna': 'Puerto Montt',
  'region': 'Los Lagos',
  'total_reportes': 4,
  'total_resueltos': 1,
  'emergencias': [
    {'nombre': 'Carabineros', 'tipo': 'CARABINEROS', 'telefono': '133'},
    {'nombre': 'Bomberos', 'tipo': 'BOMBEROS', 'telefono': '132'},
    {'nombre': 'SAMU', 'tipo': 'SAMU', 'telefono': '131'},
    {'nombre': 'Seguridad Ciudadana', 'tipo': 'SEGURIDAD_CIUDADANA', 'telefono': '+56 65 226 1000'},
  ],
};

final _zonas = {
  'maximo': 3,
  'radios_permitidos': [500, 1000, 1500, 2000],
  'zonas': [
    {'id_zona_segura': 1, 'tipo': 'CASA', 'nombre': 'Casa', 'latitud': -41.468, 'longitud': -72.94, 'radio_metros': 500, 'direccion_referencia': 'Avenida Presidente Ibáñez 1234, Puerto Montt'},
    {'id_zona_segura': 2, 'tipo': 'ESTUDIO', 'nombre': 'Estudio', 'latitud': -41.472, 'longitud': -72.935, 'radio_metros': 1000, 'direccion_referencia': 'Calle Benavente 550'},
    {'id_zona_segura': 3, 'tipo': 'OTRO', 'nombre': 'Casa de mis padres en Pelluco', 'latitud': -41.48, 'longitud': -72.9, 'radio_metros': 2000, 'direccion_referencia': 'Sector Pelluco'},
  ],
};

Map<String, Object?> _grupo(int id, String nombre, String rol, int miembros) => {
      'id_grupo': id,
      'nombre': nombre,
      'descripcion': 'Para avisarnos entre vecinos del pasaje y de la plaza del sector',
      'latitud': -41.468,
      'longitud': -72.94,
      'radio_metros': 1000,
      'direccion_referencia': 'Avenida Presidente Ibáñez 1234, Puerto Montt',
      'rol': rol,
      'es_admin': rol == 'ADMIN',
      'total_miembros': miembros,
      'ultimo_reporte': _hace(const Duration(hours: 2)),
      'codigo_invitacion': rol == 'ADMIN' ? 'K7Q2MXAB' : null,
      'codigo_expira': rol == 'ADMIN' ? _ahora.add(const Duration(days: 5)).toIso8601String() : null,
      'codigo_vencido': rol == 'ADMIN' ? false : null,
    };

final _grupoAdmin = _grupo(1, 'Junta de vecinos Villa Los Notros de Puerto Montt', 'ADMIN', 128);
final _grupoMiembro = _grupo(2, 'Condominio Parque Austral', 'MIEMBRO', 1);

final _grupos = {
  'maximo': 5,
  'puede_crear': false,
  'radios_permitidos': [500, 1000, 2000],
  'grupos': [_grupoAdmin, _grupoMiembro],
};

final _reportesGrupo = [
  {
    ..._reporte(3, 'ROBO', 'Robo o asalto', 'Calle Urmeneta esquina Avenida Diego Portales, Puerto Montt',
        'PENDIENTE', const Duration(minutes: 20)),
    'autor': 'Suricata Centinela 42',
    'es_mio': false,
    'visibilidad': 'GRUPO',
    'fecha_publicacion': _hace(const Duration(minutes: 20)),
    'total_comentarios': 12,
  },
  {
    ..._reporte(4, 'SOSPECHOSO', 'Actividad sospechosa', 'Pasaje Los Aromos', 'VALIDADO',
        const Duration(hours: 5)),
    'autor': 'Suricata Protectora 17',
    'es_mio': true,
    'visibilidad': 'PUBLICO',
    'fecha_publicacion': _hace(const Duration(hours: 5)),
    'total_comentarios': 1,
  },
];

final _gruposAdmin = [
  {
    'id_grupo': 1,
    'nombre': 'Junta de vecinos Villa Los Notros de Puerto Montt',
    'descripcion': 'Para avisarnos entre vecinos del pasaje y de la plaza del sector',
    'radio_metros': 1000,
    'direccion': 'Avenida Presidente Ibáñez 1234, Puerto Montt',
    'activo': true,
    'fecha_creacion': _hace(const Duration(days: 40)),
    'codigo_vencido': true,
    'creador': 'María Fernanda Soto Riquelme',
    'creador_email': 'maria.fernanda.soto.riquelme@correo-largo.cl',
    'total_miembros': 128,
    'total_reportes': 37,
    'reportes_privados': 12,
    'ultimo_reporte': _hace(const Duration(hours: 2)),
  },
  {
    'id_grupo': 2,
    'nombre': 'Condominio Parque Austral',
    'descripcion': null,
    'radio_metros': 500,
    'direccion': null,
    'activo': false,
    'fecha_creacion': _hace(const Duration(days: 3)),
    'codigo_vencido': false,
    'creador': 'Pedro Díaz',
    'creador_email': 'pedro@correo.cl',
    'total_miembros': 1,
    'total_reportes': 0,
    'reportes_privados': 0,
    'ultimo_reporte': null,
  },
];

final _reportesGrupoAdmin = [
  for (final r in _reportesGrupo)
    {...r, 'fecha_publicacion': r['fecha_publicacion'], 'vencido': false},
];

const _gruposEnPunto = [
  {'id_grupo': 1, 'nombre': 'Junta de vecinos Villa Los Notros de Puerto Montt'},
  {'id_grupo': 2, 'nombre': 'Condominio Parque Austral'},
];

final _miembrosGrupo = [
  {'id_miembro': 1, 'alias': 'Suricata Protectora 17', 'rol': 'ADMIN', 'soy_yo': true, 'fecha_union': _hace(const Duration(days: 30))},
  {'id_miembro': 2, 'alias': 'Suricata Intrépida 88', 'rol': 'MIEMBRO', 'soy_yo': false, 'fecha_union': _hace(const Duration(days: 2))},
];

const _invitacionGrupo = {
  'id_grupo': 1,
  'nombre': 'Junta de vecinos Villa Los Notros de Puerto Montt',
  'descripcion': 'Para avisarnos entre vecinos del pasaje y de la plaza del sector',
  'radio_metros': 1000,
  'total_miembros': 128,
  'ya_es_miembro': false,
};

final _notificaciones = {
  'no_leidas': 2,
  'notificaciones': [
    {
      'id_notificacion': 1,
      'distancia_metros': 300,
      'fecha_envio': _hace(const Duration(hours: 1)),
      'leida': false,
      'zona': {'id_zona_segura': 1, 'nombre': 'Casa', 'tipo': 'CASA'},
      'reporte': _reporte(3, 'ROBO', 'Robo o asalto', 'Calle Urmeneta, Puerto Montt', 'PENDIENTE',
          const Duration(hours: 1)),
    },
    {
      'id_notificacion': 2,
      'distancia_metros': 150,
      'fecha_envio': _hace(const Duration(hours: 3)),
      'leida': true,
      'zona': {'id_zona_segura': 3, 'nombre': 'Casa de mis padres en Pelluco', 'tipo': 'OTRO'},
      'reporte': _reporte(5, 'SOSPECHOSO', 'Actividad sospechosa', 'Cerca del colegio San Javier',
          'PENDIENTE', const Duration(hours: 3)),
    },
  ],
};

const _resumenAdmin = {
  'usuarios_por_estado': {'ACTIVO': 128, 'PENDIENTE': 14, 'SUSPENDIDO': 3},
  'usuarios_nuevos_7d': 9,
  'reportes_por_estado': {'PENDIENTE': 21, 'VALIDADO': 12, 'RESUELTO': 40, 'EXPIRADO': 18, 'DESCARTADO': 4},
  'reportes_24h': 6,
  'reportes_7d': 31,
  'reportes_vigentes': 33,
  'categorias_30d': [
    {'nombre': 'Robo o asalto', 'color_hex': '#6D28D9', 'total': 14},
    {'nombre': 'Accidente de tránsito', 'color_hex': '#C62828', 'total': 9},
    {'nombre': 'Mascota perdida', 'color_hex': '#B45309', 'total': 4},
  ],
};

/// Acciones que la API permite según el estado efectivo del reporte.
const _accionesPorEstado = {
  'PENDIENTE': ['VALIDADO', 'RESUELTO', 'DESCARTADO'],
  'VALIDADO': ['RESUELTO', 'DESCARTADO'],
  'DESCARTADO': ['PENDIENTE'],
  'EXPIRADO': ['DESCARTADO'],
  'RESUELTO': <String>[],
};

final _reportesAdmin = [
  for (final (i, r) in _misReportes.indexed)
    {
      ...r,
      'autor': 'Renato Alejandro Díaz Valenzuela',
      'imagen': null,
      'zona': 'Mirasol',
      'acciones': _accionesPorEstado[r['estado']] ?? const <String>[],
      'denuncias_pendientes': i == 0 ? 2 : 0,
    },
];

Map<String, Object?> _paginaReportesAdmin(String? estado) {
  final conteos = <String, int>{for (final e in _accionesPorEstado.keys) e: 0};
  for (final r in _reportesAdmin) {
    final e = r['estado'] as String;
    conteos[e] = (conteos[e] ?? 0) + 1;
  }
  final filtrados = [for (final r in _reportesAdmin) if (estado == null || r['estado'] == estado) r];
  return {'reportes': filtrados, 'total': filtrados.length, 'pagina': 1, 'por_pagina': 25, 'conteos': conteos};
}

final _usuariosAdmin = [
  {
    'id_usuario': 1,
    'nombres': 'Renato Alejandro',
    'apellidos': 'Díaz Valenzuela',
    'email': 're••••@correo-largo.cl',
    'rut': '1234••••-9',
    'telefono': '••••••••5678',
    'estado': 'ACTIVO',
    'email_verificado': true,
    'fecha_creacion': _hace(const Duration(days: 40)),
    'total_reportes': 4,
    'es_admin': false,
  },
  {
    'id_usuario': 2,
    'nombres': 'María José',
    'apellidos': 'Soto',
    'email': 'mj••••@correo.cl',
    'rut': '9876•••-2',
    'telefono': '••••••••4321',
    'estado': 'SUSPENDIDO',
    'email_verificado': true,
    'fecha_creacion': _hace(const Duration(days: 4)),
    'total_reportes': 12,
    'es_admin': false,
  },
];

Map<String, Object?> _nodo(String tipo, int id, String etiqueta, Map<String, Object?> datos, {String? detalle}) => {
      'clave': '$tipo:$id',
      'tipo': tipo,
      'etiqueta': etiqueta,
      'datos': {'id': id, ...datos},
      'detalle': detalle,
    };

final _resumenGrafo = {
  'calles_con_hechos': 4,
  'calles_top': [
    {'nombre': 'Avenida Presidente Ibáñez', 'total': 10, 'tendencia': 'sube'},
    {'nombre': 'Avenida Diego Portales', 'total': 9, 'tendencia': 'igual'},
    {'nombre': 'Calle Urmeneta', 'total': 5, 'tendencia': 'baja'},
  ],
  'sectores_en_alza': 2,
  'incidentes_abiertos': 1,
  'sincronizacion': {'fecha': _hace(const Duration(minutes: 5))},
};

final _filtrosAnalisis = {
  'categorias': [
    for (final c in _categorias) {'codigo': c['codigo'], 'nombre': c['nombre'], 'color': c['color_hex']},
  ],
  'comunas': [
    {'id': 1, 'nombre': 'Puerto Montt'},
    {'id': 2, 'nombre': 'Puerto Varas'},
  ],
  'sectores': [
    {'id': 12, 'nombre': 'Alerce Norte', 'id_comuna': 1},
    {'id': 3, 'nombre': 'Centro', 'id_comuna': 1},
    {'id': 5, 'nombre': 'Mirasol', 'id_comuna': 1},
  ],
};

Map<String, Object?> _porDia(int dias) {
  final hoy = DateTime.now();
  final serie = <Map<String, Object?>>[];
  for (var i = dias - 1; i >= 0; i--) {
    final total = (i * 7 + 3) % 5;
    serie.add({
      'dia': hoy.subtract(Duration(days: i)).toIso8601String().substring(0, 10),
      'total': total,
      'reportes': total,
      'por_categoria': {if (total > 0) 'ROBO': total},
    });
  }
  final total = serie.fold<int>(0, (s, d) => s + (d['total'] as int));
  return {
    'desde': serie.first['dia'],
    'hasta': serie.last['dia'],
    'dias': serie,
    'total': total,
    'anterior': total - 6,
    'tendencia': 'sube',
    'variacion': 12.5,
    'promedio_diario': total / dias,
    'dia_pico': {'dia': serie.last['dia'], 'total': 4},
    'categorias': (_filtrosAnalisis['categorias']! as List).take(2).toList(),
    'sincronizacion': {'fecha': _hace(const Duration(minutes: 5))},
  };
}

Map<String, Object?> _callesAnalisis(String? categoria) {
  final calles = [
    for (final l in _zonasCalientes(categoria))
      {
        'id': (l['datos']! as Map)['id'],
        'nombre': (l['datos']! as Map)['nombre'],
        'comuna': (l['datos']! as Map)['comuna'],
        'sector': (l['datos']! as Map)['sector'],
        'id_sector': (l['datos']! as Map)['id_localidad'],
        'latitud': -41.47,
        'longitud': -72.94,
        'total': l['total'],
        'reportes': (l['datos']! as Map)['reportes'],
        'anterior': 2,
        'tendencia': (l['total']! as int) > 2 ? 'sube' : 'igual',
        'variacion': (l['total']! as int) > 2 ? ((l['total']! as int) - 2) / 2 * 100 : 0.0,
        'ultimo': _hace(const Duration(hours: 5)),
        'por_categoria': (l['datos']! as Map)['por_categoria'],
      },
  ];
  final grupos = <Object?, Map<String, Object?>>{};
  for (final c in calles) {
    final g = grupos.putIfAbsent(c['id_sector'], () => {
      'id': c['id_sector'],
      'nombre': c['sector'] ?? 'Sector sin identificar',
      'comuna': c['comuna'],
      'total': 0,
      'anterior': 0,
      'tendencia': 'sube',
      'variacion': 20.0,
      'calles': <Map<String, Object?>>[],
    });
    g['total'] = (g['total']! as int) + (c['total']! as int);
    g['anterior'] = (g['anterior']! as int) + 2;
    (g['calles']! as List).add(c);
  }
  for (final g in grupos.values) {
    final lista = g['calles']! as List;
    g['total_calles'] = lista.length;
    for (final (i, c) in lista.indexed) {
      (c as Map)['puesto_en_sector'] = i + 1;
      c['calles_en_sector'] = lista.length;
    }
  }
  final porSector = grupos.values.toList()
    ..sort((a, b) => a['id'] == null ? 1 : (b['id'] == null ? -1 : (b['total']! as int).compareTo(a['total']! as int)));
  return {'calles': calles, 'total_calles': calles.length, 'por_sector': porSector, 'reportes_sin_calle': 3};
}

final _sectoresAnalisis = {
  'tramos': [
    for (var i = 0; i < 6; i++)
      {
        'desde': DateTime.now().subtract(Duration(days: 30 - i * 5)).toIso8601String().substring(0, 10),
        'hasta': DateTime.now().subtract(Duration(days: 26 - i * 5)).toIso8601String().substring(0, 10),
      },
  ],
  'sectores': [
    {'clave': 'Localidad:5', 'nombre': 'Mirasol', 'comuna': 'Puerto Montt', 'serie': [0, 1, 1, 2, 3, 4], 'total': 11, 'anterior': 4, 'tendencia': 'sube', 'variacion': 175.0},
    {'clave': 'Localidad:3', 'nombre': 'Centro', 'comuna': 'Puerto Montt', 'serie': [2, 2, 1, 2, 1, 1], 'total': 9, 'anterior': 9, 'tendencia': 'igual', 'variacion': 0.0},
    {'clave': 'Localidad:12', 'nombre': 'Alerce Norte', 'comuna': 'Puerto Montt', 'serie': [3, 1, 1, 0, 0, 0], 'total': 5, 'anterior': 8, 'tendencia': 'baja', 'variacion': -37.5},
    {'clave': 'Localidad:9', 'nombre': 'Pelluco', 'comuna': 'Puerto Montt', 'serie': [0, 0, 0, 0, 2, 3], 'total': 5, 'anterior': 0, 'tendencia': 'nueva', 'variacion': null},
  ],
  'resumen': {'nueva': 1, 'sube': 1, 'baja': 1, 'igual': 1},
};

/// Hechos por calle y categoría para la red de lugares (como los cuenta la API).
const _reportesPorLugar = [
  ('Calle', 5, 'Avenida Presidente Ibáñez', 'Puerto Montt', {'ROBO': 7, 'ACCIDENTE': 2, 'VIAL': 1}),
  ('Calle', 12, 'Avenida Diego Portales', 'Puerto Montt', {'ROBO': 4, 'SOSPECHOSO': 1, 'ACCIDENTE': 4}),
  ('Calle', 3, 'Calle Urmeneta', 'Puerto Montt', {'ACCIDENTE': 3, 'ROBO': 2}),
  ('Calle', 9, 'Avenida Austral', 'Puerto Montt', {'ROBO': 3, 'MASCOTA': 2}),
  ('Calle', 2, 'San Francisco', 'Puerto Varas', {'ACCIDENTE': 3}),
  ('Calle', 6, 'Avenida Presidente Ibáñez', 'Puerto Montt', {'ROBO': 1}),
];

/// Sector de cada tramo: (id de localidad, nombre); null = sin sector identificado.
const _sectorDeTramo = {
  5: (5, 'Mirasol'),
  12: (3, 'Centro'),
  3: (3, 'Centro'),
  9: (5, 'Mirasol'),
  6: (12, 'Alerce Norte'),
  2: null,
};

List<Map<String, Object?>> _zonasCalientes(String? categoria) {
  final lugares = <Map<String, Object?>>[];
  for (final (tipo, id, nombre, comuna, conteo) in _reportesPorLugar) {
    final porCategoria = [
      for (final c in _categorias)
        if (conteo.containsKey(c['codigo']) && (categoria == null || c['codigo'] == categoria))
          {
            'id': c['id_categoria'],
            'codigo': c['codigo'],
            'nombre': c['nombre'],
            'color': c['color_hex'],
            'total': conteo[c['codigo']],
          },
    ]..sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));
    if (porCategoria.isEmpty) continue;
    final total = porCategoria.fold<int>(0, (suma, c) => suma + (c['total'] as int));
    // En Ibáñez varios vecinos reportaron el mismo robo: más reportes que hechos.
    final reportes = id == 5 ? total + 3 : total;
    final sector = _sectorDeTramo[id];
    lugares.add({
      ..._nodo(tipo, id, nombre, {
        'nombre': nombre,
        'comuna': comuna,
        'sector': sector?.$2,
        'id_localidad': sector?.$1,
        'total': total,
        'reportes': reportes,
        'por_categoria': porCategoria,
      }),
      'total': total,
    });
  }
  lugares.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));
  final maximo = lugares.isEmpty ? 1 : lugares.first['total'] as int;
  for (final l in lugares) {
    (l['datos'] as Map)['intensidad'] = (l['total'] as int) / maximo;
  }
  return lugares;
}

Map<String, Object?> _redGrafo(String? categoria) {
  final lugares = _zonasCalientes(categoria);
  final categorias = <String, Map<String, Object?>>{};
  final aristas = <Map<String, Object?>>[];
  for (final l in lugares) {
    for (final c in ((l['datos'] as Map)['por_categoria'] as List).cast<Map<String, Object?>>()) {
      final clave = 'Categoria:${c['id']}';
      final cat = categorias.putIfAbsent(
        clave,
        () => _nodo('Categoria', c['id'] as int, c['nombre'] as String, {
          'codigo': c['codigo'],
          'nombre': c['nombre'],
          'color': c['color'],
          'total': 0,
        }),
      );
      final datos = cat['datos'] as Map;
      datos['total'] = (datos['total'] as int) + (c['total'] as int);
      aristas.add({'origen': l['clave'], 'destino': clave, 'tipo': 'OCURREN', 'datos': {'peso': c['total']}});
    }
  }
  final sectores = <String, Map<String, Object?>>{};
  for (final l in lugares) {
    final datos = l['datos']! as Map;
    if (datos['id_localidad'] == null) continue;
    final clave = 'Localidad:${datos['id_localidad']}';
    final s = sectores.putIfAbsent(
      clave,
      () => _nodo('Localidad', datos['id_localidad'] as int, datos['sector'] as String, {
        'nombre': datos['sector'],
        'comuna': datos['comuna'],
        'total': 0,
      }),
    );
    final ds = s['datos']! as Map;
    ds['total'] = (ds['total'] as int) + (l['total']! as int);
    aristas.add({'origen': clave, 'destino': l['clave'], 'tipo': 'CONTIENE', 'datos': {'peso': l['total']}});
  }
  return {
    'nodos': [...lugares, ...categorias.values, ...sectores.values],
    'aristas': aristas,
    'sincronizacion': {'fecha': _hace(const Duration(minutes: 5))},
  };
}

// Zonas de riesgo alrededor del centro inicial del mapa (Puerto Montt).
final _zonasRiesgo = [
  {
    'tipo': 'SEGURIDAD',
    'nivel': 'ALTO',
    'latitud': -41.4672,
    'longitud': -72.9395,
    'radio_metros': 320,
    'total_incidentes': 6,
    'incidentes_de_noche': 5,
    'por_categoria': [
      {'codigo': 'ROBO', 'nombre': 'Robo o asalto', 'color_hex': '#6D28D9', 'total': 5},
      {'codigo': 'SOSPECHOSO', 'nombre': 'Actividad sospechosa', 'color_hex': '#475569', 'total': 1},
    ],
    'ultimo_incidente': _hace(const Duration(days: 2)),
    'recomendacion': 'Evita transitar por aquí, sobre todo de noche. Si debes pasar, hazlo acompañado, '
        'por calles iluminadas y sin exponer tu celular.',
  },
  {
    'tipo': 'SEGURIDAD',
    'nivel': 'MEDIO',
    'latitud': -41.4735,
    'longitud': -72.9500,
    'radio_metros': 180,
    'total_incidentes': 2,
    'incidentes_de_noche': 0,
    'por_categoria': [
      {'codigo': 'ROBO', 'nombre': 'Robo o asalto', 'color_hex': '#6D28D9', 'total': 2},
    ],
    'ultimo_incidente': _hace(const Duration(days: 9)),
    'recomendacion': 'Transita con precaución por aquí. Si debes pasar, hazlo acompañado, '
        'por calles iluminadas y sin exponer tu celular.',
  },
  {
    'tipo': 'VIAL',
    'nivel': 'MEDIO',
    'latitud': -41.4650,
    'longitud': -72.9480,
    'radio_metros': 200,
    'total_incidentes': 3,
    'incidentes_de_noche': 1,
    'por_categoria': [
      {'codigo': 'ACCIDENTE', 'nombre': 'Accidente de tránsito', 'color_hex': '#C62828', 'total': 3},
    ],
    'ultimo_incidente': _hace(const Duration(days: 4)),
    'recomendacion': 'Se han reportado problemas en la vía: reduce la velocidad y cruza solo por pasos peatonales.',
  },
];

// Manchas del mapa de calor (robos y accidentes): un foco grande en la zona
// roja y otros más chicos.
final _calor = [
  for (final (lat, lng, robos, accidentes) in [
    (-41.4672, -72.9395, 9, 2),
    (-41.4735, -72.9500, 1, 1),
    (-41.4650, -72.9480, 3, 0),
    (-41.4600, -72.9300, 0, 1),
    (-41.4710, -72.9250, 1, 1),
    (-41.4550, -72.9450, 1, 0),
  ])
    {
      'latitud': lat,
      'longitud': lng,
      'peso': robos + accidentes,
      'robos': robos,
      'accidentes': accidentes,
      'seguridad': robos,
      'radio_metros': (150 + 60 * (robos + accidentes - 1)).clamp(150, 600),
    },
];

const _regiones = [
  {
    'id_region': 1,
    'nombre': 'Los Lagos',
    'numero_romano': 'X',
    'comunas': [
      {'id_comuna': 1, 'nombre': 'Puerto Montt'},
    ],
  },
];
