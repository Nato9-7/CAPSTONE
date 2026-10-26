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
    final cuerpo = _responder(peticion.method, ruta);
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

Object? _responder(String metodo, String ruta) {
  if (ruta == '/api/reportes/categorias') return _categorias;
  if (ruta == '/api/reportes/') return _reportesMapa;
  if (ruta == '/api/reportes/cercanos') {
    return {'radio_metros': 2000, 'total': _cercanos.length, 'reportes': _cercanos};
  }
  if (ruta == '/api/reportes/mios') return _misReportes;
  if (RegExp(r'^/api/reportes/\d+$').hasMatch(ruta)) return _detalle;
  if (RegExp(r'^/api/reportes/\d+/comentarios$').hasMatch(ruta)) return _comentarios;
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
  if (ruta == '/api/admin/reportes') return _reportesAdmin;
  if (ruta == '/api/admin/usuarios') return _usuariosAdmin;
  if (ruta == '/api/admin/grupos') return _gruposAdmin;
  if (RegExp(r'^/api/admin/grupos/\d+/reportes$').hasMatch(ruta)) return _reportesGrupoAdmin;
  if (ruta == '/api/admin/grafo/inicio') return _inicioGrafo;
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

final _reportesAdmin = [
  for (final r in _misReportes)
    {...r, 'autor': 'Renato Alejandro Díaz Valenzuela', 'vencido': false, 'imagen': null},
];

final _usuariosAdmin = [
  {
    'id_usuario': 1,
    'nombres': 'Renato Alejandro',
    'apellidos': 'Díaz Valenzuela',
    'email': 'renato.alejandro.diaz@correo-largo.cl',
    'rut': '12345678-9',
    'telefono': '+56912345678',
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
    'email': 'mjsoto@correo.cl',
    'rut': '9876543-2',
    'telefono': '+56987654321',
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

final _inicioGrafo = {
  'hallazgos': [
    {
      'nivel': 'alerta',
      'texto': 'Un vecino desmintió 6 reportes en las últimas 24 horas',
      'nodo': _nodo('Usuario', 2, 'Vecino 0a1b2c', {'estado': 'ACTIVO'}),
    },
  ],
  'reportes': [
    _nodo('Reporte', 1, 'Accidente en Av. Diego Portales',
        {'categoria_codigo': 'ACCIDENTE', 'categoria': 'Accidente de tránsito', 'estado': 'VALIDADO'},
        detalle: '8 confirman'),
  ],
  'vecinos': [_nodo('Usuario', 1, 'Vecino 9f8e7d', {'estado': 'ACTIVO'}, detalle: '12 acciones')],
  'lugares': [_nodo('Comuna', 1, 'Puerto Montt', {}, detalle: '33 reportes')],
  'sincronizacion': {'fecha': _hace(const Duration(minutes: 5))},
};
