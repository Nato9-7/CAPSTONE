import 'package:flutter/material.dart';
import 'package:rb_alertas/config/api_config.dart';
import 'package:rb_alertas/servicios/admin_servicio.dart';
import 'package:rb_alertas/servicios/estado_alertas_servicio.dart';
import 'package:rb_alertas/servicios/perfil_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/admin_grafo_vista.dart';
import 'package:rb_alertas/vistas/mapa_vista.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Etiqueta y color de cada estado de reporte o de cuenta.
(String, Color) _estiloEstado(String estado) {
  switch (estado) {
    case 'PENDIENTE':
      return ('Pendiente', RBColores.azul);
    case 'VALIDADO':
      return ('Validado', RBColores.verde);
    case 'RESUELTO':
      return ('Resuelto', RBColores.verde);
    case 'DESCARTADO':
      return ('Descartado', RBColores.rojo);
    case 'EXPIRADO':
      return ('Expirado', RBColores.texto2);
    case 'ACTIVO':
      return ('Activa', RBColores.verde);
    case 'SUSPENDIDO':
      return ('Suspendida', RBColores.rojo);
    case 'ELIMINADO':
      return ('Eliminada', RBColores.texto2);
    default:
      return (estado, RBColores.texto2);
  }
}

String _fecha(DateTime? fecha) {
  if (fecha == null) return '';
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(fecha.day)}-${dos(fecha.month)}-${fecha.year} '
      '${dos(fecha.hour)}:${dos(fecha.minute)}';
}

void _avisar(BuildContext context, String mensaje) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(mensaje)));
}

/// Estado de un reporte con la píldora del sistema visual.
Widget _chipReporte(String estado) => ChipEstado(
  estado: EstadoVisual.desdeApi(estado),
  texto: _estiloEstado(estado).$1,
);

/// Estado de una cuenta: Activa en verde, Pendiente en azul y Suspendida en rojo.
Widget _chipCuenta(String estado) {
  final (fondo, color) = switch (estado) {
    'ACTIVO' => (RBColores.verde50, RBColores.verde),
    'PENDIENTE' => (RBColores.azul50, RBColores.azul),
    'SUSPENDIDO' => (RBColores.rojo50, RBColores.rojo),
    _ => (RBColores.linea, RBColores.texto2),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: fondo,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      _estiloEstado(estado).$1,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
}

Widget _mensajeCentro(String texto, {VoidCallback? reintentar}) {
  return ListView(
    // ListView para que el gesto de recargar funcione también con el aviso.
    padding: const EdgeInsets.all(32),
    children: [
      const SizedBox(height: 60),
      Text(
        texto,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 15, color: RBColores.texto2),
      ),
      if (reintentar != null) ...[
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton(
            onPressed: reintentar,
            child: const Text('Reintentar'),
          ),
        ),
      ],
    ],
  );
}

/// Panel de administración: es la única pantalla de la cuenta admin (el login
/// la abre en vez del mapa). La API vuelve a comprobarlo en cada ruta /api/admin.
class AdminVista extends StatelessWidget {
  const AdminVista({super.key});

  Future<void> _cerrarSesion(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Quieres salir del panel de administración?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: RBColores.rojo),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    final token = Sesion.token;
    if (token != null && token.isNotEmpty) {
      await PerfilServicio().cerrarSesion(token);
    }
    Sesion.cerrar();
    EstadoAlertas.limpiar();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const MapaVista()),
      (ruta) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: RBColores.fondo,
        body: SafeArea(
          child: Column(
            children: [
              _encabezado(context),
              const _SelectorPestanas(),
              const SizedBox(height: 8),
              const Expanded(
                child: TabBarView(
                  children: [
                    _PestanaResumen(),
                    _PestanaReportes(),
                    _PestanaUsuarios(),
                    PestanaGrafo(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Suricata y marca de la app, como en el inicio de sesión.
  Widget _encabezado(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
      child: Row(
        children: [
          const AvatarSuricata(tamano: 46),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarcaRB(tamano: 23),
                SizedBox(height: 2),
                Text(
                  'Panel de Administración',
                  style: TextStyle(fontSize: 13.5, color: RBColores.texto2),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout_rounded, color: RBColores.rojo),
            onPressed: () => _cerrarSesion(context),
          ),
        ],
      ),
    );
  }
}

/// Pestañas segmentadas, iguales a las de la pantalla Alertas.
class _SelectorPestanas extends StatelessWidget {
  const _SelectorPestanas();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SelectorSegmentado(
        controlador: DefaultTabController.of(context),
        opciones: const ['Resumen', 'Reportes', 'Usuarios', 'Grafo'],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Resumen

class _PestanaResumen extends StatefulWidget {
  const _PestanaResumen();

  @override
  State<_PestanaResumen> createState() => _PestanaResumenState();
}

class _PestanaResumenState extends State<_PestanaResumen>
    with AutomaticKeepAliveClientMixin {
  final _servicio = AdminServicio();
  ResumenAdmin? _resumen;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final resumen = await _servicio.resumen(Sesion.token ?? '');
      if (!mounted) return;
      setState(() => _resumen = resumen);
    } on AdminServicioException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo conectar con el servidor');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final r = _resumen;
    if (r == null) {
      return _error == null
          ? const Center(child: CircularProgressIndicator(color: RBColores.azul))
          : _mensajeCentro(_error!, reintentar: _cargar);
    }

    final maximoCategoria = r.categorias30d.fold<int>(
      1,
      (m, c) => c.total > m ? c.total : m,
    );

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _titulo('Reportes'),
          _filaCifras([
            ('Vigentes', r.reportesVigentes, RBColores.azul),
            ('Últimas 24 h', r.reportes24h, RBColores.azul),
            ('Últimos 7 días', r.reportes7d, RBColores.verde),
          ]),
          const SizedBox(height: 12),
          _desglose(r.reportesPorEstado, _chipReporte),
          const SizedBox(height: 28),
          _titulo('Usuarios'),
          _filaCifras([
            ('Cuentas', r.totalUsuarios, RBColores.azul),
            ('Nuevas (7 días)', r.usuariosNuevos7d, RBColores.verde),
            (
              'Suspendidas',
              r.usuariosPorEstado['SUSPENDIDO'] ?? 0,
              RBColores.rojo,
            ),
          ]),
          const SizedBox(height: 12),
          _desglose(r.usuariosPorEstado, _chipCuenta),
          const SizedBox(height: 28),
          _titulo('Reportes por categoría (30 días)'),
          TarjetaRB(
            child: Column(
              children: [
                for (final c in r.categorias30d)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            c.nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              color: RBColores.tinta,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: c.total / maximoCategoria,
                              minHeight: 10,
                              backgroundColor: RBColores.linea,
                              color: colorCategoria('', colorHex: c.colorHex),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: Text(
                            '${c.total}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: RBColores.tinta,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _titulo(String texto) => Padding(
    padding: const EdgeInsets.only(bottom: 10, left: 4),
    child: EtiquetaSeccion(texto),
  );

  Widget _filaCifras(List<(String, int, Color)> cifras) {
    return Row(
      children: [
        for (final (i, (etiqueta, valor, color)) in cifras.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: TarjetaRB(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
              child: Column(
                children: [
                  Text(
                    '$valor',
                    style: TextStyle(
                      fontFamily: RBFuentes.titulos,
                      fontSize: 28,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    etiqueta,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: RBColores.texto2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _desglose(
    Map<String, int> conteo,
    Widget Function(String estado) chip,
  ) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final e in conteo.entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              chip(e.key),
              const SizedBox(width: 5),
              Text(
                '${e.value}',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: RBColores.tinta,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Reportes

class _PestanaReportes extends StatefulWidget {
  const _PestanaReportes();

  @override
  State<_PestanaReportes> createState() => _PestanaReportesState();
}

class _PestanaReportesState extends State<_PestanaReportes>
    with AutomaticKeepAliveClientMixin {
  static const _filtros = [
    (null, 'Todos'),
    ('PENDIENTE', 'Pendientes'),
    ('VALIDADO', 'Validados'),
    ('RESUELTO', 'Resueltos'),
    ('DESCARTADO', 'Descartados'),
    ('EXPIRADO', 'Expirados'),
  ];

  final _servicio = AdminServicio();
  List<ReporteAdmin>? _reportes;
  String? _error;
  String? _filtro;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final reportes = await _servicio.reportes(
        Sesion.token ?? '',
        estado: _filtro,
      );
      if (!mounted) return;
      setState(() => _reportes = reportes);
    } on AdminServicioException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo conectar con el servidor');
      }
    }
  }

  void _filtrar(String? estado) {
    setState(() {
      _filtro = estado;
      _reportes = null;
    });
    _cargar();
  }

  Future<void> _cambiarEstado(ReporteAdmin reporte, String estado) async {
    final motivo = TextEditingController();
    final (texto, color) = _estiloEstado(estado);
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Marcar como ${texto.toLowerCase()}'),
        content: TextField(
          controller: motivo,
          maxLength: 200,
          decoration: const InputDecoration(
            labelText: 'Motivo (opcional)',
            hintText: 'Queda en el historial del reporte',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    await _ejecutar(
      () => _servicio.cambiarEstadoReporte(
        Sesion.token ?? '',
        reporte.id,
        estado,
        motivo: motivo.text.trim().isEmpty ? null : motivo.text.trim(),
      ),
      'Reporte #${reporte.id} marcado como ${texto.toLowerCase()}',
    );
  }

  Future<void> _suspenderAutor(ReporteAdmin reporte) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Suspender a quien reportó'),
        content: Text(
          'La cuenta de «${reporte.autor}» no podrá volver a entrar ni crear '
          'reportes hasta que la reactives en la pestaña Usuarios. '
          'Se cerrarán todas sus sesiones.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: RBColores.rojo),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Suspender'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    await _ejecutar(
      () => _servicio.suspenderAutor(Sesion.token ?? '', reporte.id),
      'Cuenta de «${reporte.autor}» suspendida',
    );
  }

  Future<void> _verComentarios(ReporteAdmin reporte) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: RBColores.fondo,
      builder: (_) => _HojaComentarios(reporte: reporte),
    );
  }

  Future<void> _ejecutar(Future<void> Function() accion, String exito) async {
    try {
      await accion();
      if (!mounted) return;
      _avisar(context, exito);
      _cargar();
    } on AdminServicioException catch (e) {
      if (mounted) _avisar(context, e.mensaje);
    } catch (_) {
      if (mounted) _avisar(context, 'No se pudo conectar con el servidor');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        SizedBox(
          height: 64,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            children: [
              for (final (estado, etiqueta) in _filtros)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChipFiltro(
                    etiqueta: etiqueta,
                    activo: _filtro == estado,
                    onTap: () => _filtrar(estado),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _lista()),
      ],
    );
  }

  Widget _lista() {
    final reportes = _reportes;
    if (reportes == null) {
      return _error == null
          ? const Center(child: CircularProgressIndicator(color: RBColores.azul))
          : _mensajeCentro(_error!, reintentar: _cargar);
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: reportes.isEmpty
          ? _mensajeCentro('No hay reportes con este filtro.')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              itemCount: reportes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _tarjeta(reportes[i]),
            ),
    );
  }

  Widget _tarjeta(ReporteAdmin r) {
    final icono = IconoCategoria(
      codigo: r.categoriaCodigo,
      colorHex: r.colorHex,
      tamano: 56,
    );
    final lugar = [
      r.direccion,
      r.zona,
    ].whereType<String>().where((p) => p.isNotEmpty).join(' · ');

    return TarjetaRB(
      padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r.imagen != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                ApiConfig.urlArchivo(r.imagen!),
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => icono,
              ),
            )
          else
            icono,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '#${r.id} ${r.categoria}',
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: RBColores.tinta,
                      ),
                    ),
                    _chipReporte(r.estado),
                    if (r.vencido && r.estado != 'EXPIRADO')
                      _chipReporte('EXPIRADO'),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  r.descripcion,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    color: RBColores.tinta,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (lugar.isNotEmpty) lugar,
                    '${r.autor} · ${_fecha(r.fechaCreacion?.toLocal())}',
                    '${r.confirmaciones} confirman · ${r.desmentidos} desmienten',
                  ].join('\n'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: RBColores.texto2,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Acciones',
            color: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(RBRadios.campo),
            ),
            icon: const Icon(Icons.more_vert, color: RBColores.texto2),
            onSelected: (accion) => switch (accion) {
              'SUSPENDER_AUTOR' => _suspenderAutor(r),
              'COMENTARIOS' => _verComentarios(r),
              _ => _cambiarEstado(r, accion),
            },
            itemBuilder: (_) => [
              for (final estado in const [
                'VALIDADO',
                'RESUELTO',
                'DESCARTADO',
                'PENDIENTE',
              ])
                if (estado != r.estado)
                  PopupMenuItem(
                    value: estado,
                    child: Text(
                      'Marcar ${_estiloEstado(estado).$1.toLowerCase()}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: estado == 'DESCARTADO'
                            ? RBColores.rojo
                            : RBColores.tinta,
                      ),
                    ),
                  ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'COMENTARIOS',
                child: Text(
                  'Ver comentarios',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: RBColores.tinta,
                  ),
                ),
              ),
              const PopupMenuItem(
                value: 'SUSPENDER_AUTOR',
                child: Text(
                  'Suspender a quien reportó',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: RBColores.rojo,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Comentarios de un reporte para moderar: ocultar o volver a publicar.
class _HojaComentarios extends StatefulWidget {
  final ReporteAdmin reporte;

  const _HojaComentarios({required this.reporte});

  @override
  State<_HojaComentarios> createState() => _HojaComentariosState();
}

class _HojaComentariosState extends State<_HojaComentarios> {
  final _servicio = AdminServicio();
  List<ComentarioAdmin>? _comentarios;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final comentarios = await _servicio.comentarios(
        Sesion.token ?? '',
        widget.reporte.id,
      );
      if (mounted) setState(() => _comentarios = comentarios);
    } on AdminServicioException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo conectar con el servidor');
      }
    }
  }

  Future<void> _cambiarEstado(ComentarioAdmin c, String estado) async {
    try {
      await _servicio.cambiarEstadoComentario(Sesion.token ?? '', c.id, estado);
      if (!mounted) return;
      _avisar(
        context,
        estado == 'OCULTO' ? 'Comentario oculto' : 'Comentario publicado de nuevo',
      );
      _cargar();
    } on AdminServicioException catch (e) {
      if (mounted) _avisar(context, e.mensaje);
    } catch (_) {
      if (mounted) _avisar(context, 'No se pudo conectar con el servidor');
    }
  }

  @override
  Widget build(BuildContext context) {
    final comentarios = _comentarios;
    final Widget cuerpo;
    if (comentarios == null) {
      cuerpo = _error == null
          ? const Center(child: CircularProgressIndicator(color: RBColores.azul))
          : _mensajeCentro(_error!, reintentar: _cargar);
    } else if (comentarios.isEmpty) {
      cuerpo = _mensajeCentro('Este reporte no tiene comentarios.');
    } else {
      cuerpo = ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        itemCount: comentarios.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _tarjeta(comentarios[i]),
      );
    }

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Comentarios del reporte #${widget.reporte.id}',
                    style: const TextStyle(
                      fontFamily: RBFuentes.titulos,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: RBColores.azul,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: RBColores.texto2),
                ),
              ],
            ),
          ),
          Expanded(child: cuerpo),
        ],
      ),
    );
  }

  Widget _tarjeta(ComentarioAdmin c) {
    final (texto, fondo, color) = switch (c.estado) {
      'PUBLICADO' => ('Publicado', RBColores.verde50, RBColores.verde),
      'OCULTO' => ('Oculto', RBColores.rojo50, RBColores.rojo),
      _ => ('Eliminado por su autor', RBColores.linea, RBColores.texto2),
    };
    return TarjetaRB(
      padding: EdgeInsets.fromLTRB(c.idPadre == null ? 16 : 32, 12, 6, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (c.idPadre != null)
                      const Icon(Icons.subdirectory_arrow_right_rounded,
                          size: 16, color: RBColores.texto2),
                    Text(
                      c.autor ?? 'Vecino',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: RBColores.tinta,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: fondo,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        texto,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
                      ),
                    ),
                  ],
                ),
                if (c.contenido.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    c.contenido,
                    style: const TextStyle(fontSize: 14, height: 1.35, color: RBColores.tinta),
                  ),
                ],
                if (c.imagen != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      ApiConfig.urlArchivo(c.imagen!),
                      height: 110,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        color: RBColores.texto2,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _fecha(c.fechaCreacion?.toLocal()),
                  style: const TextStyle(fontSize: 12.5, color: RBColores.texto2),
                ),
              ],
            ),
          ),
          if (c.estado == 'PUBLICADO')
            IconButton(
              tooltip: 'Ocultar comentario',
              onPressed: () => _cambiarEstado(c, 'OCULTO'),
              icon: const Icon(Icons.visibility_off_outlined, color: RBColores.rojo),
            )
          else if (c.estado == 'OCULTO')
            IconButton(
              tooltip: 'Publicar de nuevo',
              onPressed: () => _cambiarEstado(c, 'PUBLICADO'),
              icon: const Icon(Icons.visibility_outlined, color: RBColores.verde),
            ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Usuarios

class _PestanaUsuarios extends StatefulWidget {
  const _PestanaUsuarios();

  @override
  State<_PestanaUsuarios> createState() => _PestanaUsuariosState();
}

class _PestanaUsuariosState extends State<_PestanaUsuarios>
    with AutomaticKeepAliveClientMixin {
  final _servicio = AdminServicio();
  final _buscador = TextEditingController();
  List<UsuarioAdmin>? _usuarios;
  String? _error;
  bool _soloSuspendidas = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final usuarios = await _servicio.usuarios(
        Sesion.token ?? '',
        buscar: _buscador.text,
        estado: _soloSuspendidas ? 'SUSPENDIDO' : null,
      );
      if (!mounted) return;
      setState(() => _usuarios = usuarios);
    } on AdminServicioException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo conectar con el servidor');
      }
    }
  }

  Future<void> _cambiarEstado(UsuarioAdmin u) async {
    final suspender = u.estado != 'SUSPENDIDO';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(suspender ? 'Suspender cuenta' : 'Reactivar cuenta'),
        content: Text(
          suspender
              ? '${u.nombreCompleto} (${u.email}) no podrá entrar a la app. '
                    'Se cerrarán todas sus sesiones.'
              : '${u.nombreCompleto} (${u.email}) podrá volver a entrar a la app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: suspender ? RBColores.rojo : RBColores.verde,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(suspender ? 'Suspender' : 'Reactivar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await _servicio.cambiarEstadoUsuario(
        Sesion.token ?? '',
        u.id,
        suspender ? 'SUSPENDIDO' : 'ACTIVO',
      );
      if (!mounted) return;
      _avisar(context, suspender ? 'Cuenta suspendida' : 'Cuenta reactivada');
      _cargar();
    } on AdminServicioException catch (e) {
      if (mounted) _avisar(context, e.mensaje);
    } catch (_) {
      if (mounted) _avisar(context, 'No se pudo conectar con el servidor');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _buscador,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _cargar(),
            decoration: InputDecoration(
              hintText: 'Buscar por nombre, correo o RUT',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                tooltip: 'Buscar',
                icon: const Icon(
                  Icons.arrow_forward_rounded,
                  color: RBColores.azul,
                ),
                onPressed: _cargar,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: const Text(
            'Solo cuentas suspendidas',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: RBColores.tinta,
            ),
          ),
          value: _soloSuspendidas,
          activeThumbColor: Colors.white,
          activeTrackColor: RBColores.azul,
          onChanged: (valor) {
            setState(() => _soloSuspendidas = valor);
            _cargar();
          },
        ),
        Expanded(child: _lista()),
      ],
    );
  }

  Widget _lista() {
    final usuarios = _usuarios;
    if (usuarios == null) {
      return _error == null
          ? const Center(child: CircularProgressIndicator(color: RBColores.azul))
          : _mensajeCentro(_error!, reintentar: _cargar);
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: usuarios.isEmpty
          ? _mensajeCentro('No se encontraron cuentas.')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              itemCount: usuarios.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _tarjeta(usuarios[i]),
            ),
    );
  }

  Widget _tarjeta(UsuarioAdmin u) {
    final iniciales = [
      u.nombres,
      u.apellidos,
    ].where((x) => x.isNotEmpty).map((x) => x[0].toUpperCase()).join();
    final moderable = !u.esAdmin && u.estado != 'ELIMINADO';

    return TarjetaRB(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: RBColores.azul50,
            child: Text(
              iniciales.isEmpty ? '?' : iniciales,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: RBColores.azul,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      u.nombreCompleto.isEmpty ? u.email : u.nombreCompleto,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: RBColores.tinta,
                      ),
                    ),
                    if (u.esAdmin)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: RBColores.azul,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Admin',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      )
                    else
                      _chipCuenta(u.estado),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    u.email + (u.emailVerificado ? '' : ' (sin verificar)'),
                    [
                      if (u.rut != null) 'RUT ${u.rut}',
                      if (u.telefono != null) u.telefono!,
                    ].join(' · '),
                    '${u.totalReportes} reportes · desde '
                        '${_fecha(u.fechaCreacion?.toLocal()).split(' ').first}',
                  ].where((l) => l.isNotEmpty).join('\n'),
                  style: const TextStyle(
                    fontSize: 13,
                    color: RBColores.texto2,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (moderable)
            TextButton(
              onPressed: () => _cambiarEstado(u),
              style: TextButton.styleFrom(
                foregroundColor: u.estado == 'SUSPENDIDO'
                    ? RBColores.verde
                    : RBColores.rojo,
              ),
              child: Text(u.estado == 'SUSPENDIDO' ? 'Reactivar' : 'Suspender'),
            ),
        ],
      ),
    );
  }
}
