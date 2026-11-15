import 'package:flutter/material.dart';
import 'package:rb_alertas/config/api_config.dart';
import 'package:rb_alertas/modelos/modelos.dart';
import 'package:rb_alertas/servicios/admin_servicio.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/vistas/admin/comun_admin.dart';
import 'package:rb_alertas/vistas/admin/moderacion_reporte.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Todos los reportes, filtrables por estado, con su menú de moderación.
class PestanaReportes extends StatefulWidget {
  const PestanaReportes({super.key});

  @override
  State<PestanaReportes> createState() => _PestanaReportesState();
}

class _PestanaReportesState extends State<PestanaReportes> with AutomaticKeepAliveClientMixin {
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
      final reportes = await _servicio.reportes(estado: _filtro);
      if (mounted) setState(() => _reportes = reportes);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  void _filtrar(String? estado) {
    setState(() {
      _filtro = estado;
      _reportes = null;
    });
    _cargar();
  }

  /// Aplica una acción de moderación y recarga la lista si cambió algo.
  Future<void> _moderar(Future<bool> accion) async {
    if (await accion && mounted) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        FiltrosAdmin<String?>(opciones: _filtros, seleccionado: _filtro, alElegir: _filtrar),
        Expanded(
          child: ListaAdmin<ReporteAdmin>(
            elementos: _reportes,
            error: _error,
            recargar: _cargar,
            textoVacio: 'No hay reportes con este filtro.',
            tarjeta: _tarjeta,
          ),
        ),
      ],
    );
  }

  Widget _tarjeta(ReporteAdmin r) {
    final icono = IconoCategoria(codigo: r.categoriaCodigo, colorHex: r.colorHex, tamano: 56);
    final lugar = [r.direccion, r.zona].whereType<String>().where((p) => p.isNotEmpty).join(' · ');

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
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: RBColores.tinta),
                    ),
                    chipReporte(r.estado),
                    if (r.vencido && r.estado != 'EXPIRADO') chipReporte('EXPIRADO'),
                    if (r.soloGrupo) const ChipSoloGrupo(),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  r.descripcion,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, height: 1.35, color: RBColores.tinta),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (lugar.isNotEmpty) lugar,
                    '${r.autor} · ${fechaHora(r.fechaCreacion?.toLocal())}',
                    '${r.confirmaciones} confirman · ${r.desmentidos} desmienten',
                  ].join('\n'),
                  style: const TextStyle(fontSize: 12.5, color: RBColores.texto2, height: 1.4),
                ),
              ],
            ),
          ),
          _menuAcciones(r),
        ],
      ),
    );
  }

  Widget _menuAcciones(ReporteAdmin r) {
    PopupMenuItem<String> opcion(String valor, String texto, {Color color = RBColores.tinta, FontWeight peso = FontWeight.w600}) =>
        PopupMenuItem(
          value: valor,
          child: Text(texto, style: TextStyle(fontWeight: peso, color: color)),
        );

    return PopupMenuButton<String>(
      tooltip: 'Acciones',
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RBRadios.campo)),
      icon: const Icon(Icons.more_vert, color: RBColores.texto2),
      onSelected: (accion) => _moderar(switch (accion) {
        'SUSPENDER_AUTOR' => suspenderAutorReporte(context, r),
        'COMENTARIOS' => verComentariosReporte(context, r),
        'ELIMINAR' => eliminarReporte(context, r),
        _ => cambiarEstadoReporte(context, r, accion),
      }),
      itemBuilder: (_) => [
        for (final estado in estadosModerables)
          if (estado != r.estado)
            opcion(
              estado,
              'Marcar ${estiloEstado(estado).$1.toLowerCase()}',
              color: estado == 'DESCARTADO' ? RBColores.rojo : RBColores.tinta,
            ),
        const PopupMenuDivider(),
        opcion('COMENTARIOS', 'Ver comentarios'),
        opcion('SUSPENDER_AUTOR', 'Suspender a quien reportó', color: RBColores.rojo),
        opcion('ELIMINAR', 'Eliminar reporte', color: RBColores.rojo, peso: FontWeight.w700),
      ],
    );
  }
}
