import 'package:rb_alertas/modelos/grupo.dart';
import 'package:rb_alertas/modelos/lectura_json.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';

/// Grupos vecinales: creación, invitaciones, miembros y el "chat" de reportes.
class GruposServicio {
  static const String _ruta = '/api/grupos';

  /// Reportes que trae cada página del chat.
  static const int reportesPorPagina = 30;

  Future<MisGrupos> listar() async {
    final cuerpo = await ApiCliente.get('$_ruta/', error: 'No se pudieron cargar tus grupos');
    return MisGrupos.desdeJson(cuerpo as Map<String, dynamic>);
  }

  /// Grupos donde se puede compartir un reporte hecho en este punto.
  Future<List<GrupoEnPunto>> enPunto({required double latitud, required double longitud}) async {
    final cuerpo = await ApiCliente.get(
      '$_ruta/en-punto',
      consulta: {'latitud': '$latitud', 'longitud': '$longitud'},
      error: 'No se pudieron revisar tus grupos',
    );
    return listaDesdeJson(cuerpo, GrupoEnPunto.desdeJson);
  }

  Future<Grupo> detalle(int idGrupo) async {
    final cuerpo = await ApiCliente.get('$_ruta/$idGrupo', error: 'No se pudo cargar el grupo');
    return Grupo.desdeJson(cuerpo as Map<String, dynamic>);
  }

  Future<Grupo> crear({
    required String nombre,
    String? descripcion,
    required double latitud,
    required double longitud,
    required int radioMetros,
    String? direccion,
  }) async {
    final cuerpo = await ApiCliente.post(
      '$_ruta/',
      cuerpo: _cuerpo(nombre, descripcion, latitud, longitud, radioMetros, direccion),
      error: 'No se pudo crear el grupo',
    );
    return Grupo.desdeJson(cuerpo as Map<String, dynamic>);
  }

  Future<Grupo> actualizar({
    required int idGrupo,
    required String nombre,
    String? descripcion,
    required double latitud,
    required double longitud,
    required int radioMetros,
    String? direccion,
  }) async {
    final cuerpo = await ApiCliente.put(
      '$_ruta/$idGrupo',
      cuerpo: _cuerpo(nombre, descripcion, latitud, longitud, radioMetros, direccion),
      error: 'No se pudieron guardar los cambios',
    );
    return Grupo.desdeJson(cuerpo as Map<String, dynamic>);
  }

  Future<void> eliminar(int idGrupo) async {
    await ApiCliente.delete('$_ruta/$idGrupo', error: 'No se pudo eliminar el grupo');
  }

  Future<InvitacionGrupo> verInvitacion(String codigo) async {
    final cuerpo = await ApiCliente.get(
      '$_ruta/invitacion/${Uri.encodeComponent(codigo.trim())}',
      error: 'No se pudo revisar el código',
    );
    return InvitacionGrupo.desdeJson(cuerpo as Map<String, dynamic>);
  }

  Future<Grupo> unirse(String codigo) async {
    final cuerpo = await ApiCliente.post(
      '$_ruta/unirse',
      cuerpo: {'codigo': codigo.trim()},
      error: 'No se pudo entrar al grupo',
    );
    return Grupo.desdeJson(cuerpo as Map<String, dynamic>);
  }

  Future<Grupo> regenerarCodigo(int idGrupo) async {
    final cuerpo = await ApiCliente.post('$_ruta/$idGrupo/codigo', error: 'No se pudo generar un código nuevo');
    return Grupo.desdeJson(cuerpo as Map<String, dynamic>);
  }

  Future<List<MiembroGrupo>> miembros(int idGrupo) async {
    final cuerpo = await ApiCliente.get('$_ruta/$idGrupo/miembros', error: 'No se pudieron cargar los vecinos');
    return listaDesdeJson(cuerpo, MiembroGrupo.desdeJson);
  }

  Future<void> expulsar({required int idGrupo, required int idMiembro}) async {
    await ApiCliente.delete('$_ruta/$idGrupo/miembros/$idMiembro', error: 'No se pudo quitar al vecino');
  }

  Future<void> salir(int idGrupo) async {
    await ApiCliente.post('$_ruta/$idGrupo/salir', error: 'No se pudo salir del grupo');
  }

  /// Reportes del grupo, del más reciente al más antiguo. Con [antesDe]
  /// (id del último reporte recibido) trae la página siguiente.
  Future<List<ReporteGrupo>> reportes({required int idGrupo, int? antesDe}) async {
    final cuerpo = await ApiCliente.get(
      '$_ruta/$idGrupo/reportes',
      consulta: {
        'limite': '$reportesPorPagina',
        if (antesDe != null) 'antes_de': '$antesDe',
      },
      error: 'No se pudieron cargar los reportes del grupo',
    );
    return listaDesdeJson(cuerpo, ReporteGrupo.desdeJson);
  }

  Map<String, dynamic> _cuerpo(
    String nombre,
    String? descripcion,
    double latitud,
    double longitud,
    int radioMetros,
    String? direccion,
  ) {
    final textoDescripcion = (descripcion ?? '').trim();
    final referencia = (direccion ?? '').trim();
    return {
      'nombre': nombre.trim(),
      'descripcion': textoDescripcion.isEmpty ? null : textoDescripcion,
      'latitud': latitud,
      'longitud': longitud,
      'radio_metros': radioMetros,
      'direccion_referencia': referencia.isEmpty ? null : referencia,
    };
  }
}
