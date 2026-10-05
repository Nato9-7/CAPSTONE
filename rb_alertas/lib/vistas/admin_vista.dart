import 'package:flutter/material.dart';
import 'package:rb_alertas/config/api_config.dart';
import 'package:rb_alertas/servicios/admin_servicio.dart';
import 'package:rb_alertas/servicios/estado_alertas_servicio.dart';
import 'package:rb_alertas/servicios/perfil_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/vistas/mapa_vista.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';

const _colorAzul = Color(0xFF0056D2);
const _colorFondo = Color(0xFFF7F8FC);
const _colorTitulo = Color(0xFF111827);
const _colorTextoGris = Color(0xFF6B7280);
const _colorBorde = Color(0xFFE5E7EB);
const _colorVerde = Color(0xFF16A34A);
const _colorRojo = Color(0xFFDC2626);
const _colorAmbar = Color(0xFFF59E0B);

final _estiloTarjeta = BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(14),
  border: Border.all(color: _colorBorde),
);

/// Etiqueta y color de cada estado de reporte o de cuenta.
(String, Color) _estiloEstado(String estado) {
  switch (estado) {
    case 'PENDIENTE':
      return ('Pendiente', _colorAmbar);
    case 'VALIDADO':
      return ('Validado', _colorAzul);
    case 'RESUELTO':
      return ('Resuelto', _colorVerde);
    case 'DESCARTADO':
      return ('Descartado', _colorRojo);
    case 'EXPIRADO':
      return ('Expirado', _colorTextoGris);
    case 'ACTIVO':
      return ('Activa', _colorVerde);
    case 'SUSPENDIDO':
      return ('Suspendida', _colorRojo);
    case 'ELIMINADO':
      return ('Eliminada', _colorTextoGris);
    default:
      return (estado, _colorTextoGris);
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

Widget _chipEstado(String estado) {
  final (texto, color) = _estiloEstado(estado);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      texto,
      style: TextStyle(
        fontSize: 11.5,
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
        style: const TextStyle(color: _colorTextoGris),
      ),
      if (reintentar != null) ...[
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton(
            onPressed: reintentar,
            child: const Text('Reintentar', style: TextStyle(color: _colorAzul)),
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
            style: FilledButton.styleFrom(backgroundColor: _colorRojo),
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
      length: 3,
      child: Scaffold(
        backgroundColor: _colorFondo,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          foregroundColor: _colorTitulo,
          title: const Text(
            'Panel de Administración',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          actions: [
            IconButton(
              tooltip: 'Cerrar sesión',
              icon: const Icon(Icons.logout, color: _colorRojo),
              onPressed: () => _cerrarSesion(context),
            ),
          ],
          bottom: const TabBar(
            labelColor: _colorAzul,
            unselectedLabelColor: _colorTextoGris,
            indicatorColor: _colorAzul,
            labelStyle: TextStyle(fontWeight: FontWeight.w700),
            tabs: [
              Tab(text: 'Resumen'),
              Tab(text: 'Reportes'),
              Tab(text: 'Usuarios'),
            ],
          ),
        ),
        body: const SafeArea(
          child: TabBarView(
            children: [_PestanaResumen(), _PestanaReportes(), _PestanaUsuarios()],
          ),
        ),
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
      if (mounted) setState(() => _error = 'No se pudo conectar con el servidor');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final r = _resumen;
    if (r == null) {
      return _error == null
          ? const Center(child: CircularProgressIndicator(color: _colorAzul))
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
            ('Vigentes', r.reportesVigentes, _colorAzul),
            ('Últimas 24 h', r.reportes24h, _colorAmbar),
            ('Últimos 7 días', r.reportes7d, _colorVerde),
          ]),
          const SizedBox(height: 10),
          _desglose(r.reportesPorEstado),
          const SizedBox(height: 24),
          _titulo('Usuarios'),
          _filaCifras([
            ('Cuentas', r.totalUsuarios, _colorAzul),
            ('Nuevas (7 días)', r.usuariosNuevos7d, _colorVerde),
            ('Suspendidas', r.usuariosPorEstado['SUSPENDIDO'] ?? 0, _colorRojo),
          ]),
          const SizedBox(height: 10),
          _desglose(r.usuariosPorEstado),
          const SizedBox(height: 24),
          _titulo('Reportes por categoría (30 días)'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _estiloTarjeta,
            child: Column(
              children: [
                for (final c in r.categorias30d)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            c.nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: _colorTitulo,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: c.total / maximoCategoria,
                              minHeight: 8,
                              backgroundColor: const Color(0xFFF1F3F7),
                              color: colorCategoria('', colorHex: c.colorHex),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 36,
                          child: Text(
                            '${c.total}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _colorTitulo,
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
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      texto,
      style: const TextStyle(
        fontSize: 16.5,
        fontWeight: FontWeight.w800,
        color: _colorTitulo,
      ),
    ),
  );

  Widget _filaCifras(List<(String, int, Color)> cifras) {
    return Row(
      children: [
        for (final (i, (etiqueta, valor, color)) in cifras.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    '$valor',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    etiqueta,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: _colorTextoGris,
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

  Widget _desglose(Map<String, int> conteo) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in conteo.entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _chipEstado(e.key),
              const SizedBox(width: 4),
              Text(
                '${e.value}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _colorTitulo,
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
      if (mounted) setState(() => _error = 'No se pudo conectar con el servidor');
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
            style: FilledButton.styleFrom(backgroundColor: _colorRojo),
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
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            children: [
              for (final (estado, etiqueta) in _filtros)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(etiqueta),
                    selected: _filtro == estado,
                    onSelected: (_) => _filtrar(estado),
                    selectedColor: _colorAzul.withValues(alpha: 0.12),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _filtro == estado ? _colorAzul : _colorTextoGris,
                    ),
                    showCheckmark: false,
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
          ? const Center(child: CircularProgressIndicator(color: _colorAzul))
          : _mensajeCentro(_error!, reintentar: _cargar);
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: reportes.isEmpty
          ? _mensajeCentro('No hay reportes con este filtro.')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              itemCount: reportes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _tarjeta(reportes[i]),
            ),
    );
  }

  Widget _tarjeta(ReporteAdmin r) {
    final color = colorCategoria(r.categoriaCodigo, colorHex: r.colorHex);
    final lugar = [r.direccion, r.zona]
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .join(' · ');

    return Container(
      decoration: _estiloTarjeta,
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r.imagen != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                ApiConfig.urlArchivo(r.imagen!),
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _iconoCategoria(r, color),
              ),
            )
          else
            _iconoCategoria(r, color),
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
                      '#${r.id} ${r.categoria}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _colorTitulo,
                      ),
                    ),
                    _chipEstado(r.estado),
                    if (r.vencido && r.estado != 'EXPIRADO')
                      _chipEstado('EXPIRADO'),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  r.descripcion,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: _colorTitulo),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (lugar.isNotEmpty) lugar,
                    '${r.autor} · ${_fecha(r.fechaCreacion?.toLocal())}',
                    '${r.confirmaciones} confirman · ${r.desmentidos} desmienten',
                  ].join('\n'),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: _colorTextoGris,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Acciones',
            icon: const Icon(Icons.more_vert, color: _colorTextoGris),
            onSelected: (accion) => accion == 'SUSPENDER_AUTOR'
                ? _suspenderAutor(r)
                : _cambiarEstado(r, accion),
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
                    ),
                  ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'SUSPENDER_AUTOR',
                child: Text(
                  'Suspender a quien reportó',
                  style: TextStyle(color: _colorRojo),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconoCategoria(ReporteAdmin r, Color color) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(iconoCategoria(r.categoriaCodigo), color: color),
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
      if (mounted) setState(() => _error = 'No se pudo conectar con el servidor');
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
              backgroundColor: suspender ? _colorRojo : _colorVerde,
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
              prefixIcon: const Icon(Icons.search, color: _colorTextoGris),
              suffixIcon: IconButton(
                tooltip: 'Buscar',
                icon: const Icon(Icons.arrow_forward, color: _colorAzul),
                onPressed: _cargar,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _colorBorde),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _colorBorde),
              ),
            ),
          ),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const Text(
            'Solo cuentas suspendidas',
            style: TextStyle(fontSize: 13.5, color: _colorTitulo),
          ),
          value: _soloSuspendidas,
          activeThumbColor: _colorAzul,
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
          ? const Center(child: CircularProgressIndicator(color: _colorAzul))
          : _mensajeCentro(_error!, reintentar: _cargar);
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: usuarios.isEmpty
          ? _mensajeCentro('No se encontraron cuentas.')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              itemCount: usuarios.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _tarjeta(usuarios[i]),
            ),
    );
  }

  Widget _tarjeta(UsuarioAdmin u) {
    final iniciales = [u.nombres, u.apellidos]
        .where((x) => x.isNotEmpty)
        .map((x) => x[0].toUpperCase())
        .join();
    final moderable = !u.esAdmin && u.estado != 'ELIMINADO';

    return Container(
      decoration: _estiloTarjeta,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFE5EDFF),
            child: Text(
              iniciales.isEmpty ? '?' : iniciales,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: _colorAzul,
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
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _colorTitulo,
                      ),
                    ),
                    if (u.esAdmin)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _colorTitulo,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Admin',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      )
                    else
                      _chipEstado(u.estado),
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
                    fontSize: 12,
                    color: _colorTextoGris,
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
                    ? _colorVerde
                    : _colorRojo,
              ),
              child: Text(u.estado == 'SUSPENDIDO' ? 'Reactivar' : 'Suspender'),
            ),
        ],
      ),
    );
  }
}
