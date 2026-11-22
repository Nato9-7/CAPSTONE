import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/modelos.dart';
import 'package:rb_alertas/servicios/admin_servicio.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/vistas/admin/comun_admin.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';
import 'package:rb_alertas/widgets/dialogos.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Grupos vecinales: búsqueda, cierre/reapertura y sus reportes.
class PestanaGrupos extends StatefulWidget {
  const PestanaGrupos({super.key});

  @override
  State<PestanaGrupos> createState() => _PestanaGruposState();
}

class _PestanaGruposState extends State<PestanaGrupos> with AutomaticKeepAliveClientMixin {
  final _servicio = AdminServicio();
  final _buscador = TextEditingController();
  List<GrupoAdmin>? _grupos;
  String? _error;
  bool _soloCerrados = false;

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
      final grupos = await _servicio.grupos(buscar: _buscador.text, activo: _soloCerrados ? false : null);
      if (mounted) setState(() => _grupos = grupos);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  Future<void> _cambiarEstado(GrupoAdmin g) async {
    final cerrar = g.activo;
    final confirmado = await confirmar(
      context,
      color: cerrar ? RBColores.rojo : RBColores.verde,
      titulo: cerrar ? 'Cerrar grupo' : 'Reabrir grupo',
      mensaje: cerrar
          ? '«${g.nombre}» dejará de verse en la app y sus reportes privados '
                'quedarán ocultos para los vecinos.'
          : '«${g.nombre}» volverá a estar disponible para sus vecinos.',
      accion: cerrar ? 'Cerrar grupo' : 'Reabrir',
    );
    if (!confirmado || !mounted) return;
    final aplicado = await ejecutarAccionAdmin(
      context,
      () => _servicio.cambiarEstadoGrupo(g.id, !cerrar),
      cerrar ? 'Grupo cerrado' : 'Grupo reabierto',
    );
    if (aplicado && mounted) _cargar();
  }

  Future<void> _verReportes(GrupoAdmin g) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _HojaReportesGrupo(grupo: g),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        BuscadorAdmin(
          controlador: _buscador,
          pista: 'Buscar por nombre o correo del creador',
          alBuscar: _cargar,
          etiquetaInterruptor: 'Solo grupos cerrados',
          valorInterruptor: _soloCerrados,
          alCambiarInterruptor: (valor) {
            setState(() => _soloCerrados = valor);
            _cargar();
          },
        ),
        Expanded(
          child: ListaAdmin<GrupoAdmin>(
            elementos: _grupos,
            error: _error,
            recargar: _cargar,
            textoVacio: 'No se encontraron grupos.',
            tarjeta: _tarjeta,
          ),
        ),
      ],
    );
  }

  Widget _tarjeta(GrupoAdmin g) {
    final palabra = g.totalReportes == 1 ? 'reporte' : 'reportes';
    final reportes = g.reportesPrivados > 0
        ? '${g.totalReportes} $palabra (${g.reportesPrivados} ${g.reportesPrivados == 1 ? 'privado' : 'privados'})'
        : '${g.totalReportes} $palabra';
    final creador = g.creador.isEmpty ? g.creadorEmail : '${g.creador} (${g.creadorEmail})';
    final descripcion = g.descripcion?.trim();

    return TarjetaRB(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: g.activo ? RBColores.azul50 : RBColores.linea,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.groups_rounded, color: g.activo ? RBColores.azul : RBColores.texto2),
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
                          '#${g.id} ${g.nombre}',
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: RBColores.tinta),
                        ),
                        // Mismos colores que una cuenta: verde activa, rojo cerrada.
                        chipCuenta(g.activo ? 'ACTIVO' : 'SUSPENDIDO', texto: g.activo ? 'Activo' : 'Cerrado'),
                      ],
                    ),
                    if (descripcion != null && descripcion.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        descripcion,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, height: 1.35, color: RBColores.tinta),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      [
                        'Creado por $creador',
                        '${g.totalMiembros} vecinos · $reportes · área de ${textoRadio(g.radioMetros)}',
                        [
                          'desde ${fechaHora(g.fechaCreacion?.toLocal()).split(' ').first}',
                          if (g.ultimoReporte != null) 'último reporte ${tiempoRelativo(g.ultimoReporte!.toLocal())}',
                          if (g.activo && g.codigoVencido) 'código vencido',
                        ].join(' · '),
                      ].join('\n'),
                      style: const TextStyle(fontSize: 13, color: RBColores.texto2, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              TextButton.icon(
                onPressed: g.totalReportes == 0 ? null : () => _verReportes(g),
                icon: const Icon(Icons.forum_outlined, size: 18),
                label: const Text('Ver reportes'),
              ),
              TextButton(
                onPressed: () => _cambiarEstado(g),
                style: TextButton.styleFrom(foregroundColor: g.activo ? RBColores.rojo : RBColores.verde),
                child: Text(g.activo ? 'Cerrar grupo' : 'Reabrir'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Reportes compartidos en un grupo. Para moderarlos (cambiar estado,
/// suspender al autor) se usan las acciones de la pestaña Reportes.
class _HojaReportesGrupo extends StatefulWidget {
  final GrupoAdmin grupo;

  const _HojaReportesGrupo({required this.grupo});

  @override
  State<_HojaReportesGrupo> createState() => _HojaReportesGrupoState();
}

class _HojaReportesGrupoState extends State<_HojaReportesGrupo> {
  final _servicio = AdminServicio();
  List<ReporteDeGrupoAdmin>? _reportes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final reportes = await _servicio.reportesDeGrupo(widget.grupo.id);
      if (mounted) setState(() => _reportes = reportes);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reportes = _reportes;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
            child: Text(
              widget.grupo.nombre,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: RBFuentes.titulos,
                fontSize: context.escala(24),
                fontWeight: FontWeight.w800,
                color: RBColores.azul,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'Reportes compartidos en el grupo. Para moderarlos, búscalos por '
              'su número en la pestaña Reportes.',
              style: TextStyle(fontSize: 13.5, height: 1.4, color: RBColores.texto2),
            ),
          ),
          Expanded(
            child: reportes == null
                ? cargandoOError(_error, _cargar)
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.of(context).viewPadding.bottom),
                    itemCount: reportes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _tarjeta(reportes[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(ReporteDeGrupoAdmin r) {
    return TarjetaRB(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconoCategoria(codigo: r.categoriaCodigo, colorHex: r.colorHex, tamano: 44),
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
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: RBColores.tinta),
                    ),
                    chipReporte(r.estadoVisible),
                    if (r.soloGrupo) const ChipSoloGrupo(),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  r.descripcion,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, height: 1.35, color: RBColores.tinta),
                ),
                const SizedBox(height: 4),
                Text(
                  '${r.autor} · ${fechaHora(r.fechaPublicacion?.toLocal())}',
                  style: const TextStyle(fontSize: 13, color: RBColores.texto2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
