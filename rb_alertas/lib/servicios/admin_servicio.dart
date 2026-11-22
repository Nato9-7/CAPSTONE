import 'package:rb_alertas/modelos/admin.dart';
import 'package:rb_alertas/modelos/analisis.dart';
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

  /// Una página de reportes con los filtros pedidos. El estado es el efectivo:
  /// EXPIRADO incluye los pendientes y validados cuya vigencia terminó.
  Future<PaginaReportes> reportes({FiltroReportes filtro = const FiltroReportes(), int pagina = 1}) async {
    final desde = filtro.desde;
    final cuerpo = await ApiCliente.get(
      '/api/admin/reportes',
      consulta: {
        'estado': ?filtro.estado,
        if (filtro.texto != null && filtro.texto!.trim().isNotEmpty) 'q': filtro.texto!.trim(),
        'categoria': ?filtro.categoria,
        if (desde != null)
          'desde': '${desde.year}-${'${desde.month}'.padLeft(2, '0')}-${'${desde.day}'.padLeft(2, '0')}',
        'orden': filtro.orden,
        'pagina': '$pagina',
      },
      error: _errorCarga,
    );
    return PaginaReportes.desdeJson(cuerpo as Map<String, dynamic>);
  }

  /// Un reporte con sus datos de moderación, o null si ya no existe.
  Future<ReporteAdmin?> reporte(int idReporte) async {
    final cuerpo = await ApiCliente.get(
      '/api/admin/reportes',
      consulta: {'id_reporte': '$idReporte'},
      error: _errorCarga,
    );
    return PaginaReportes.desdeJson(cuerpo as Map<String, dynamic>).reportes.firstOrNull;
  }

  /// [estado]: uno de [ReporteAdmin.acciones] (la API rechaza los demás).
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

  /// Correo, RUT y teléfono completos (la lista los trae ocultos). La API registra quién los pidió.
  Future<({String email, String? rut, String? telefono})> contactoUsuario(int idUsuario) async {
    final cuerpo = await ApiCliente.get('/api/admin/usuarios/$idUsuario/contacto', error: _errorCarga);
    final json = cuerpo as Map<String, dynamic>;
    return (email: json.texto('email'), rut: json.textoOpcional('rut'), telefono: json.textoOpcional('telefono'));
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
  // Análisis (Neo4j)

  Future<ResumenGrafo> resumenGrafo() async {
    final cuerpo = await ApiCliente.get('/api/admin/grafo/resumen', error: _errorCarga);
    return ResumenGrafo.desdeJson(cuerpo as Map<String, dynamic>);
  }

  Map<String, String> _consultaAnalisis(int dias, String? categoria, int? comuna) => {
    'dias': '$dias',
    'categoria': ?categoria,
    if (comuna != null) 'comuna': '$comuna',
  };

  Future<FiltrosDisponibles> filtrosAnalisis() async {
    final cuerpo = await ApiCliente.get('/api/admin/analisis/filtros', error: _errorCarga);
    return FiltrosDisponibles.desdeJson(cuerpo as Map<String, dynamic>);
  }

  Future<SerieDiaria> hechosPorDia({required int dias, String? categoria, int? comuna}) async {
    final cuerpo = await ApiCliente.get(
      '/api/admin/analisis/por-dia',
      consulta: _consultaAnalisis(dias, categoria, comuna),
      error: _errorCarga,
    );
    return SerieDiaria.desdeJson(cuerpo as Map<String, dynamic>);
  }

  Future<RankingCalles> rankingCalles({required int dias, String? categoria, int? comuna, int limite = 15}) async {
    final cuerpo = await ApiCliente.get(
      '/api/admin/analisis/calles',
      consulta: {..._consultaAnalisis(dias, categoria, comuna), 'limite': '$limite'},
      error: _errorCarga,
    );
    return RankingCalles.desdeJson(cuerpo as Map<String, dynamic>);
  }

  Future<SectoresEnElTiempo> sectores({required int dias, String? categoria, int? comuna, int tramos = 6}) async {
    final cuerpo = await ApiCliente.get(
      '/api/admin/analisis/sectores',
      consulta: {..._consultaAnalisis(dias, categoria, comuna), 'tramos': '$tramos'},
      error: _errorCarga,
    );
    return SectoresEnElTiempo.desdeJson(cuerpo as Map<String, dynamic>);
  }

  /// Red de lugares: las calles (o sectores) con más hechos unidas a las
  /// categorías de lo que pasó ahí. El peso de cada unión es cuántos hechos hubo.
  Future<RedGrafo> redDeLugares({int? dias, String? categoria, String nivel = 'calle'}) async {
    final cuerpo = await ApiCliente.get(
      '/api/admin/grafo/red',
      consulta: {
        if (dias != null) 'dias': '$dias',
        'categoria': ?categoria,
        'nivel': nivel,
      },
      error: _errorCarga,
    );
    return RedGrafo.desdeJson(cuerpo as Map<String, dynamic>);
  }

  /// Copia los datos de MySQL a Neo4j.
  Future<void> sincronizarGrafo() async {
    await ApiCliente.post('/api/admin/grafo/sincronizar', error: _errorCambio);
  }
}
