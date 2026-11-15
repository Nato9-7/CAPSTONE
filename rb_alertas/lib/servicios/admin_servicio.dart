import 'package:rb_alertas/modelos/admin.dart';
import 'package:rb_alertas/modelos/grafo.dart';
import 'package:rb_alertas/modelos/lectura_json.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';

const _errorCarga = 'No se pudo cargar';
const _errorCambio = 'No se pudo guardar el cambio';

/// Rutas /api/admin: solo responden a la cuenta administradora.
class AdminServicio {
  // ---------------------------------------------------------------------------
  // Resumen, reportes y comentarios

  Future<ResumenAdmin> resumen() async {
    final cuerpo = await ApiCliente.get('/api/admin/resumen', error: _errorCarga);
    return ResumenAdmin.desdeJson(cuerpo as Map<String, dynamic>);
  }

  Future<List<ReporteAdmin>> reportes({String? estado}) async {
    final cuerpo = await ApiCliente.get(
      '/api/admin/reportes',
      consulta: {'estado': ?estado},
      error: _errorCarga,
    );
    return listaDesdeJson(cuerpo, ReporteAdmin.desdeJson);
  }

  /// Un reporte con sus datos de moderación, o null si ya no existe.
  Future<ReporteAdmin?> reporte(int idReporte) async {
    final cuerpo = await ApiCliente.get(
      '/api/admin/reportes',
      consulta: {'id_reporte': '$idReporte'},
      error: _errorCarga,
    );
    return listaDesdeJson(cuerpo, ReporteAdmin.desdeJson).firstOrNull;
  }

  /// [estado]: VALIDADO, RESUELTO o DESCARTADO.
  Future<void> cambiarEstadoReporte(int idReporte, String estado, {String? motivo}) async {
    await ApiCliente.patch(
      '/api/admin/reportes/$idReporte/estado',
      cuerpo: {'estado': estado, 'motivo': ?motivo},
      error: _errorCambio,
    );
  }

  /// Elimina el reporte para siempre (con sus votos, comentarios y fotos).
  Future<void> eliminarReporte(int idReporte) async {
    await ApiCliente.delete('/api/admin/reportes/$idReporte', error: _errorCambio);
  }

  Future<void> suspenderAutor(int idReporte) async {
    await ApiCliente.post('/api/admin/reportes/$idReporte/suspender-autor', error: _errorCambio);
  }

  Future<List<ComentarioAdmin>> comentarios(int idReporte) async {
    final cuerpo = await ApiCliente.get('/api/admin/reportes/$idReporte/comentarios', error: _errorCarga);
    return listaDesdeJson(cuerpo, ComentarioAdmin.desdeJson);
  }

  /// [estado] es OCULTO para esconderlo de la app o PUBLICADO para restaurarlo.
  Future<void> cambiarEstadoComentario(int idComentario, String estado) async {
    await ApiCliente.patch(
      '/api/admin/comentarios/$idComentario/estado',
      cuerpo: {'estado': estado},
      error: _errorCambio,
    );
  }

  /// Elimina un comentario (y su foto). No se puede deshacer.
  Future<void> eliminarComentario(int idComentario) async {
    await ApiCliente.delete('/api/admin/comentarios/$idComentario', error: _errorCambio);
  }

  /// Suspende a quien escribió el comentario (sin revelar quién es).
  Future<void> suspenderAutorComentario(int idComentario) async {
    await ApiCliente.post('/api/admin/comentarios/$idComentario/suspender-autor', error: _errorCambio);
  }

  // ---------------------------------------------------------------------------
  // Denuncias, usuarios y grupos

  /// [estado]: PENDIENTE, ATENDIDA o DESESTIMADA.
  Future<List<DenunciaAdmin>> denuncias({String estado = 'PENDIENTE'}) async {
    final cuerpo = await ApiCliente.get(
      '/api/admin/denuncias',
      consulta: {'estado': estado},
      error: _errorCarga,
    );
    return listaDesdeJson(cuerpo, DenunciaAdmin.desdeJson);
  }

  /// Cierra las denuncias pendientes (ATENDIDA o DESESTIMADA). Desestimar un
  /// comentario que se ocultó solo lo vuelve a publicar.
  Future<void> revisarDenuncias(DenunciaAdmin d, String estado) async {
    final ruta = d.esComentario
        ? '/api/admin/denuncias/comentarios/${d.idComentario}'
        : '/api/admin/denuncias/reportes/${d.idReporte}';
    await ApiCliente.patch(ruta, cuerpo: {'estado': estado}, error: _errorCambio);
  }

  Future<List<UsuarioAdmin>> usuarios({String? buscar, String? estado}) async {
    final cuerpo = await ApiCliente.get(
      '/api/admin/usuarios',
      consulta: {
        if (buscar != null && buscar.trim().isNotEmpty) 'buscar': buscar.trim(),
        'estado': ?estado,
      },
      error: _errorCarga,
    );
    return listaDesdeJson(cuerpo, UsuarioAdmin.desdeJson);
  }

  Future<void> cambiarEstadoUsuario(int idUsuario, String estado) async {
    await ApiCliente.patch(
      '/api/admin/usuarios/$idUsuario/estado',
      cuerpo: {'estado': estado},
      error: _errorCambio,
    );
  }

  Future<List<GrupoAdmin>> grupos({String? buscar, bool? activo}) async {
    final cuerpo = await ApiCliente.get(
      '/api/admin/grupos',
      consulta: {
        if (buscar != null && buscar.trim().isNotEmpty) 'buscar': buscar.trim(),
        if (activo != null) 'activo': '$activo',
      },
      error: _errorCarga,
    );
    return listaDesdeJson(cuerpo, GrupoAdmin.desdeJson);
  }

  Future<List<ReporteDeGrupoAdmin>> reportesDeGrupo(int idGrupo) async {
    final cuerpo = await ApiCliente.get('/api/admin/grupos/$idGrupo/reportes', error: _errorCarga);
    return listaDesdeJson(cuerpo, ReporteDeGrupoAdmin.desdeJson);
  }

  Future<void> cambiarEstadoGrupo(int idGrupo, bool activo) async {
    await ApiCliente.patch(
      '/api/admin/grupos/$idGrupo/estado',
      cuerpo: {'activo': activo},
      error: _errorCambio,
    );
  }

  // ---------------------------------------------------------------------------
  // Grafo (Neo4j)

  Future<ResumenGrafo> resumenGrafo() async {
    final cuerpo = await ApiCliente.get('/api/admin/grafo/resumen', error: _errorCarga);
    return ResumenGrafo.desdeJson(cuerpo as Map<String, dynamic>);
  }

  Future<List<GrupoSospechoso>> cuentasSospechosas() async {
    final cuerpo = await ApiCliente.get('/api/admin/grafo/sospechosos', error: _errorCarga);
    return listaDesdeJson(cuerpo, GrupoSospechoso.desdeJson);
  }

  /// Suspende todas las cuentas del grupo; devuelve los ids suspendidos
  /// (para poder deshacerlo reactivándolas).
  Future<List<int>> suspenderGrupoSospechoso(int idGrupo) async {
    final cuerpo = await ApiCliente.post(
      '/api/admin/grafo/sospechosos/$idGrupo/suspender',
      error: _errorCambio,
    );
    return cuerpo is Map<String, dynamic> ? cuerpo.enteros('ids') : const [];
  }

  /// La red del explorador. [modo]: "vecinos" (quién apoya a quién),
  /// "completa" (vecinos y reportes con las [capas] pedidas) o "zonas" (dónde
  /// ocurre más; [categoria] deja solo una, p. ej. "ROBO"). [dias] limita a la
  /// actividad reciente; null es toda la historia.
  Future<RedGrafo> red({
    String modo = 'vecinos',
    int? dias,
    Set<String> capas = const {},
    String? categoria,
  }) async {
    final cuerpo = await ApiCliente.get(
      '/api/admin/grafo/red',
      consulta: {
        'modo': modo,
        if (dias != null) 'dias': '$dias',
        'capas': capas.join(','),
        'categoria': ?categoria,
      },
      error: _errorCarga,
    );
    return RedGrafo.desdeJson(cuerpo as Map<String, dynamic>);
  }

  /// Lugares con más reportes, del que tiene más al que menos. Cada lugar trae
  /// en sus datos `total`, `intensidad` (0 a 1), `comuna` y `por_categoria`.
  Future<List<NodoGrafo>> zonasCalientes({String? categoria, int? dias}) async {
    final cuerpo = await ApiCliente.get(
      '/api/admin/grafo/zonas',
      consulta: {
        'categoria': ?categoria,
        if (dias != null) 'dias': '$dias',
      },
      error: _errorCarga,
    );
    return listaDesdeJson(cuerpo, NodoGrafo.desdeJson);
  }

  Future<List<NodoGrafo>> buscarEnGrafo(String texto) async {
    final cuerpo = await ApiCliente.get('/api/admin/grafo/buscar', consulta: {'q': texto}, error: _errorCarga);
    return listaDesdeJson(cuerpo, NodoGrafo.desdeJson);
  }

  /// El camino más corto entre dos elementos (lo calcula Neo4j).
  Future<RedGrafo> camino(NodoGrafo desde, NodoGrafo hasta) async {
    final cuerpo = await ApiCliente.get(
      '/api/admin/grafo/camino',
      consulta: {'desde': desde.clave, 'hasta': hasta.clave},
      error: _errorCarga,
    );
    return RedGrafo.desdeJson(cuerpo as Map<String, dynamic>);
  }

  /// [orden]: "baja" (menos confiables primero) o "alta".
  Future<List<VecinoReputacion>> reputacion({String orden = 'baja'}) async {
    final cuerpo = await ApiCliente.get(
      '/api/admin/grafo/reputacion',
      consulta: {'orden': orden},
      error: _errorCarga,
    );
    return listaDesdeJson(cuerpo, VecinoReputacion.desdeJson);
  }

  Future<List<IncidenteGrafo>> incidentes() async {
    final cuerpo = await ApiCliente.get('/api/admin/grafo/incidentes', error: _errorCarga);
    return listaDesdeJson(cuerpo, IncidenteGrafo.desdeJson);
  }

  /// Aplica [estado] (VALIDADO, RESUELTO o DESCARTADO) a todos los reportes del incidente.
  Future<void> cambiarEstadoIncidente(int idIncidente, String estado, {String? motivo}) async {
    await ApiCliente.patch(
      '/api/admin/incidentes/$idIncidente/estado',
      cuerpo: {'estado': estado, 'motivo': ?motivo},
      error: _errorCambio,
    );
  }

  /// [nodo] en el centro, con sus conexiones hasta 2 pasos.
  Future<FocoGrafo> focoGrafo(NodoGrafo nodo) async {
    final cuerpo = await ApiCliente.get('/api/admin/grafo/nodo/${nodo.tipo}/${nodo.id}', error: _errorCarga);
    return FocoGrafo.desdeJson(cuerpo as Map<String, dynamic>);
  }

  /// Copia los datos de MySQL a Neo4j.
  Future<void> sincronizarGrafo() async {
    await ApiCliente.post('/api/admin/grafo/sincronizar', error: _errorCambio);
  }
}
