import 'package:rb_alertas/modelos/lectura_json.dart';
import 'package:rb_alertas/modelos/reporte.dart';
import 'package:rb_alertas/modelos/riesgo.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';

/// Reportes de incidentes: mapa, detalle, votos y envío.
class ReporteServicio {
  Future<List<CategoriaIncidente>> obtenerCategorias() async {
    final cuerpo = await ApiCliente.get(
      '/api/reportes/categorias',
      error: 'No se pudieron cargar las categorías',
      conSesion: false,
    );
    return listaDesdeJson(cuerpo, CategoriaIncidente.desdeJson);
  }

  /// Reportes vigentes del mapa público.
  Future<List<ReporteMapa>> obtenerReportes() async {
    final cuerpo = await ApiCliente.get(
      '/api/reportes/',
      error: 'No se pudieron cargar los reportes',
      conSesion: false,
    );
    return listaDesdeJson(cuerpo, ReporteMapa.desdeJson);
  }

  /// Zonas donde se repiten robos y accidentes en los últimos [dias].
  Future<List<ZonaRiesgo>> obtenerZonasRiesgo({int dias = 60}) async {
    final cuerpo = await ApiCliente.get(
      '/api/reportes/zonas-riesgo',
      consulta: {'dias': '$dias'},
      error: 'No se pudieron cargar las zonas de riesgo',
      conSesion: false,
    );
    return (cuerpo as Map<String, dynamic>).lista('zonas', ZonaRiesgo.desdeJson);
  }

  /// Mapa de calor de robos y accidentes de tránsito en los últimos [dias].
  Future<List<PuntoCalor>> obtenerCalor({int dias = 60}) async {
    final cuerpo = await ApiCliente.get(
      '/api/reportes/calor',
      consulta: {'dias': '$dias'},
      error: 'No se pudo cargar el mapa de calor',
      conSesion: false,
    );
    return (cuerpo as Map<String, dynamic>).lista('puntos', PuntoCalor.desdeJson);
  }

  /// Detalle de un reporte. Con sesión, la API indica si quien consulta es el autor.
  Future<DetalleReporte> obtenerDetalle(int idReporte) async {
    final cuerpo = await ApiCliente.get('/api/reportes/$idReporte', error: 'No se pudo cargar el reporte');
    return DetalleReporte.desdeJson(cuerpo as Map<String, dynamic>);
  }

  /// Reportes vigentes alrededor del punto, con su distancia.
  ///
  /// Sin [radioKm], la API aplica el radio que el usuario tiene en sus preferencias.
  Future<AlertasCercanas> obtenerCercanos({
    required double latitud,
    required double longitud,
    double? radioKm,
  }) async {
    final cuerpo = await ApiCliente.get(
      '/api/reportes/cercanos',
      consulta: {
        'latitud': '$latitud',
        'longitud': '$longitud',
        if (radioKm != null) 'radio_km': '$radioKm',
      },
      error: 'No se pudieron cargar las alertas cercanas',
    );
    return AlertasCercanas.desdeJson(cuerpo as Map<String, dynamic>);
  }

  /// Historial de reportes de quien tiene la sesión abierta.
  Future<List<MiReporte>> obtenerMisReportes() async {
    final cuerpo = await ApiCliente.get(
      '/api/reportes/mios',
      error: 'No se pudo cargar tu historial de reportes',
    );
    return listaDesdeJson(cuerpo, MiReporte.desdeJson);
  }

  /// Marca el reporte como resuelto (solo lo permite la API a su autor).
  Future<void> marcarResuelto(int idReporte) async {
    await ApiCliente.post('/api/reportes/$idReporte/resolver', error: 'No se pudo marcar como resuelto');
  }

  /// Confirma o desmiente un reporte. Volver a votar reemplaza el voto anterior.
  Future<ResumenVotos> votar(int idReporte, TipoVoto voto) async {
    final cuerpo = await ApiCliente.put(
      '/api/reportes/$idReporte/voto',
      cuerpo: {'tipo_voto': voto.valorApi},
      error: 'No se pudo registrar tu voto',
    );
    return ResumenVotos.desdeJson(cuerpo as Map<String, dynamic>);
  }

  /// Retira el voto propio de un reporte.
  Future<ResumenVotos> quitarVoto(int idReporte) async {
    final cuerpo = await ApiCliente.delete('/api/reportes/$idReporte/voto', error: 'No se pudo quitar tu voto');
    return ResumenVotos.desdeJson(cuerpo as Map<String, dynamic>);
  }

  /// Publica un reporte y devuelve su id. Con [idsGrupos] el reporte aparece
  /// también en esos grupos; con [soloGrupo] solo lo ven sus vecinos (no sale
  /// en el mapa público).
  Future<int> enviarReporte({
    required int idCategoria,
    required String descripcion,
    required double latitud,
    required double longitud,
    String? direccion,
    Evidencia? evidencia,
    List<int> idsGrupos = const [],
    bool soloGrupo = false,
  }) async {
    final cuerpo = await ApiCliente.multipart(
      '/api/reportes/',
      campos: {
        'id_categoria': '$idCategoria',
        'descripcion': descripcion,
        'latitud': '$latitud',
        'longitud': '$longitud',
        if (direccion != null && direccion.isNotEmpty) 'direccion': direccion,
        // Separados por comas: un formulario multipart no admite repetir el campo.
        if (idsGrupos.isNotEmpty) 'ids_grupos': idsGrupos.join(','),
        if (idsGrupos.isNotEmpty && soloGrupo) 'solo_grupo': 'true',
      },
      archivos: [
        if (evidencia != null)
          (campo: 'evidencia', nombre: evidencia.nombreArchivo, bytes: evidencia.bytes),
      ],
      error: 'No se pudo enviar el reporte',
    );
    return (cuerpo as Map<String, dynamic>).entero('id_reporte');
  }
}
