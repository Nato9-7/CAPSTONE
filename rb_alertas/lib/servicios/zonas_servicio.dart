import 'package:rb_alertas/modelos/zona_segura.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';

/// Zonas seguras del usuario (casa, trabajo...).
class ZonasServicio {
  static const String _ruta = '/api/usuarios/zonas/';

  Future<ZonasUsuario> listar() async {
    final cuerpo = await ApiCliente.get(_ruta, error: 'No se pudieron cargar tus zonas seguras');
    return ZonasUsuario.desdeJson(cuerpo as Map<String, dynamic>);
  }

  Future<ZonaSegura> crear({
    required TipoZona tipo,
    String? nombre,
    required double latitud,
    required double longitud,
    required int radioMetros,
    String? direccion,
  }) async {
    final cuerpo = await ApiCliente.post(
      _ruta,
      cuerpo: _cuerpo(tipo, nombre, latitud, longitud, radioMetros, direccion),
      error: 'No se pudo guardar la zona',
    );
    return ZonaSegura.desdeJson(cuerpo as Map<String, dynamic>);
  }

  Future<ZonaSegura> actualizar({
    required int idZona,
    required TipoZona tipo,
    String? nombre,
    required double latitud,
    required double longitud,
    required int radioMetros,
    String? direccion,
  }) async {
    final cuerpo = await ApiCliente.put(
      '$_ruta$idZona',
      cuerpo: _cuerpo(tipo, nombre, latitud, longitud, radioMetros, direccion),
      error: 'No se pudieron guardar los cambios',
    );
    return ZonaSegura.desdeJson(cuerpo as Map<String, dynamic>);
  }

  Future<void> eliminar(int idZona) async {
    await ApiCliente.delete('$_ruta$idZona', error: 'No se pudo eliminar la zona');
  }

  Map<String, dynamic> _cuerpo(
    TipoZona tipo,
    String? nombre,
    double latitud,
    double longitud,
    int radioMetros,
    String? direccion,
  ) {
    final referencia = (direccion ?? '').trim();
    return {
      'tipo': tipo.codigo,
      // Solo OTRO manda nombre: en los demás lo fija el servidor.
      if (tipo.nombreLibre) 'nombre': (nombre ?? '').trim(),
      'latitud': latitud,
      'longitud': longitud,
      'radio_metros': radioMetros,
      'direccion_referencia': referencia.isEmpty ? null : referencia,
    };
  }
}
