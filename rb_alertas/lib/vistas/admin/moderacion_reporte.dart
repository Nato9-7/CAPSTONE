// Acciones de moderación de un reporte, compartidas por la pestaña Reportes y
// la ficha que se abre con "Moderar" desde el mapa. Cada acción devuelve true
// si cambió algo, para recargar lo que se está mostrando.
import 'package:flutter/material.dart';
import 'package:rb_alertas/config/api_config.dart';
import 'package:rb_alertas/modelos/modelos.dart';
import 'package:rb_alertas/servicios/admin_servicio.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/vistas/admin/comun_admin.dart';
import 'package:rb_alertas/vistas/admin/hoja_comentarios.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';
import 'package:rb_alertas/widgets/dialogos.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Texto de la acción que lleva un reporte a [estado]. Las acciones posibles
/// las decide la API según el estado actual ([ReporteAdmin.acciones]): un
/// reporte resuelto no se puede volver a validar, uno expirado solo se descarta, etc.
String textoAccionEstado(String estado) => switch (estado) {
  'VALIDADO' => 'Validar',
  'RESUELTO' => 'Marcar resuelto',
  'DESCARTADO' => 'Descartar',
  'PENDIENTE' => 'Restaurar a pendiente',
  _ => estiloEstado(estado).$1,
};

/// Pide un motivo opcional y cambia el estado del reporte.
Future<bool> cambiarEstadoReporte(BuildContext context, ReporteAdmin reporte, String estado) async {
  final motivo = TextEditingController();
  final (_, color) = estiloEstado(estado);
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (dialogo) => AlertDialog(
      title: Text('${textoAccionEstado(estado)} el reporte #${reporte.id}'),
      content: TextField(
        controller: motivo,
        maxLength: 200,
        decoration: const InputDecoration(
          labelText: 'Motivo (opcional)',
          hintText: 'Queda en el historial del reporte',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogo, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: color),
          onPressed: () => Navigator.pop(dialogo, true),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
  if (confirmado != true || !context.mounted) return false;
  final textoMotivo = motivo.text.trim();
  return ejecutarAccionAdmin(
    context,
    () => AdminServicio().cambiarEstadoReporte(reporte.id, estado, motivo: textoMotivo.isEmpty ? null : textoMotivo),
    'Reporte #${reporte.id}: ${estiloEstado(estado).$1.toLowerCase()}',
  );
}

/// Menú ⋮ de un reporte: solo las acciones que su estado permite.
class MenuAccionesReporte extends StatelessWidget {
  final ReporteAdmin reporte;
  final Future<void> Function(Future<bool> accion) alModerar;

  const MenuAccionesReporte({super.key, required this.reporte, required this.alModerar});

  @override
  Widget build(BuildContext context) {
    PopupMenuItem<String> opcion(String valor, String texto, IconData icono, {Color color = RBColores.tinta}) =>
        PopupMenuItem(
          value: valor,
          child: Row(
            children: [
              Icon(icono, size: 19, color: color),
              const SizedBox(width: 10),
              Text(
                texto,
                style: TextStyle(fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
        );
    final r = reporte;
    return PopupMenuButton<String>(
      tooltip: 'Acciones del reporte #${r.id}',
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RBRadios.campo)),
      icon: const Icon(Icons.more_vert, color: RBColores.texto2),
      onSelected: (accion) => alModerar(switch (accion) {
        'SUSPENDER_AUTOR' => suspenderAutorReporte(context, r),
        'COMENTARIOS' => verComentariosReporte(context, r),
        'ELIMINAR' => eliminarReporte(context, r),
        _ => cambiarEstadoReporte(context, r, accion),
      }),
      itemBuilder: (_) => [
        for (final estado in r.acciones)
          opcion(
            estado,
            textoAccionEstado(estado),
            iconoAccionEstado(estado),
            color: estado == 'DESCARTADO' ? RBColores.rojo : RBColores.tinta,
          ),
        if (r.acciones.isNotEmpty) const PopupMenuDivider(),
        opcion('COMENTARIOS', 'Ver comentarios (${r.comentarios})', Icons.forum_outlined),
        opcion('SUSPENDER_AUTOR', 'Suspender a quien reportó', Icons.block_rounded, color: RBColores.rojo),
        opcion('ELIMINAR', 'Eliminar reporte', Icons.delete_forever_rounded, color: RBColores.rojo),
      ],
    );
  }
}

IconData iconoAccionEstado(String estado) => switch (estado) {
  'VALIDADO' => Icons.verified_outlined,
  'RESUELTO' => Icons.task_alt_rounded,
  'DESCARTADO' => Icons.do_not_disturb_on_outlined,
  'PENDIENTE' => Icons.restore_rounded,
  _ => Icons.edit_outlined,
};

Future<bool> suspenderAutorReporte(BuildContext context, ReporteAdmin reporte) async {
  final confirmado = await confirmar(
    context,
    titulo: 'Suspender a quien reportó',
    mensaje:
        'La cuenta de «${reporte.autor}» no podrá volver a entrar ni crear '
        'reportes hasta que la reactives en la pestaña Usuarios. '
        'Se cerrarán todas sus sesiones.',
    accion: 'Suspender',
  );
  if (!confirmado || !context.mounted) return false;
  return ejecutarAccionAdmin(
    context,
    () => AdminServicio().suspenderAutor(reporte.id),
    'Cuenta de «${reporte.autor}» suspendida',
  );
}

/// Al volver siempre cuenta como cambio: se recargan los contadores de comentarios.
Future<bool> verComentariosReporte(BuildContext context, ReporteAdmin reporte) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: RBColores.fondo,
    builder: (_) => HojaComentarios(reporte: reporte),
  );
  return true;
}

/// Eliminar no se puede deshacer: se pide escribir ELIMINAR para confirmar.
Future<bool> eliminarReporte(BuildContext context, ReporteAdmin reporte) async {
  final confirmacion = TextEditingController();
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (dialogo) => StatefulBuilder(
      builder: (dialogo, actualizar) => AlertDialog(
        title: Text('Eliminar el reporte #${reporte.id}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se borrará para siempre, junto con sus votos, comentarios, fotos y avisos. '
              'No se puede deshacer.\n\n'
              'Si solo es falso o ya no aplica, es mejor «Marcar descartado»: deja de verse '
              'en el mapa pero queda el registro.',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: confirmacion,
              autofocus: true,
              onChanged: (_) => actualizar(() {}),
              decoration: const InputDecoration(labelText: 'Escribe ELIMINAR para confirmar'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogo, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: RBColores.rojo),
            onPressed: confirmacion.text.trim().toUpperCase() == 'ELIMINAR' ? () => Navigator.pop(dialogo, true) : null,
            child: const Text('Eliminar'),
          ),
        ],
      ),
    ),
  );
  if (confirmado != true || !context.mounted) return false;
  return ejecutarAccionAdmin(
    context,
    () => AdminServicio().eliminarReporte(reporte.id),
    'Reporte #${reporte.id} eliminado',
  );
}

/// Abre la ficha de un reporte encima del mapa ("Moderar" en su tarjeta).
/// Devuelve true si se moderó algo, para que el mapa recargue sus pines.
Future<bool> abrirModeracion(BuildContext context, int idReporte) async {
  var cambio = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
    builder: (_) => HojaModerarReporte(idReporte: idReporte, alCambiar: () => cambio = true),
  );
  return cambio;
}

/// Ficha de un reporte con todas sus acciones de moderación.
class HojaModerarReporte extends StatefulWidget {
  final int idReporte;
  final VoidCallback alCambiar;

  const HojaModerarReporte({super.key, required this.idReporte, required this.alCambiar});

  @override
  State<HojaModerarReporte> createState() => _HojaModerarReporteState();
}

class _HojaModerarReporteState extends State<HojaModerarReporte> {
  ReporteAdmin? _reporte;
  String? _error;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final reporte = await AdminServicio().reporte(widget.idReporte);
      if (!mounted) return;
      setState(() {
        _reporte = reporte;
        _cargando = false;
        if (reporte == null) _error = 'Este reporte ya no existe';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = mensajeDeError(e);
          _cargando = false;
        });
      }
    }
  }

  Future<void> _moderar(Future<bool> accion) async {
    if (!await accion || !mounted) return;
    widget.alCambiar();
    _cargar();
  }

  Future<void> _eliminar(ReporteAdmin r) async {
    if (!await eliminarReporte(context, r)) return;
    widget.alCambiar();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final r = _reporte;
    if (_cargando || r == null) {
      return SizedBox(
        height: 240,
        child: _cargando
            ? const Center(child: CircularProgressIndicator(color: RBColores.azul))
            : MensajeCentro(_error ?? '', reintentar: _cargar),
      );
    }
    final lugar = [r.direccion, r.zona].whereType<String>().where((p) => p.isNotEmpty).join(' · ');
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Row(
          children: [
            IconoCategoria(codigo: r.categoriaCodigo, colorHex: r.colorHex, tamano: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '#${r.id} ${r.categoria}',
                style: const TextStyle(
                  fontFamily: RBFuentes.titulos,
                  fontSize: 19,
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
        const SizedBox(height: 8),
        ChipsReporte(estado: r.estado, soloGrupo: r.soloGrupo),
        if (r.imagen != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              ApiConfig.urlArchivo(r.imagen!),
              height: 170,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(r.descripcion, style: const TextStyle(fontSize: 14.5, height: 1.4, color: RBColores.tinta)),
        const SizedBox(height: 8),
        Text(
          [
            if (lugar.isNotEmpty) lugar,
            '${r.autor} · ${fechaHora(r.fechaCreacion?.toLocal())}',
            '${r.confirmaciones} confirman · ${r.desmentidos} desmienten',
          ].join('\n'),
          style: const TextStyle(fontSize: 13, height: 1.45, color: RBColores.texto2),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => _moderar(verComentariosReporte(context, r)),
          icon: const Icon(Icons.forum_outlined, size: 19),
          label: Text(
            'Comentarios (${r.comentarios})'
            '${r.comentariosOcultos > 0 ? ' · ${r.comentariosOcultos} ocultos' : ''}',
          ),
        ),
        if (r.denunciasPendientes > 0) ...[
          const SizedBox(height: 10),
          Text(
            r.denunciasPendientes == 1
                ? '1 denuncia pendiente (ver pestaña Denuncias)'
                : '${r.denunciasPendientes} denuncias pendientes (ver pestaña Denuncias)',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: RBColores.rojo),
          ),
        ],
        const SizedBox(height: 14),
        const Text('Cambiar estado', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (r.acciones.isEmpty)
          Text(
            r.estado == 'RESUELTO'
                ? 'Un reporte resuelto ya no cambia de estado.'
                : 'Este reporte no admite cambios de estado.',
            style: const TextStyle(fontSize: 13, color: RBColores.texto2),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final estado in r.acciones)
                ChipFiltro(
                  etiqueta: textoAccionEstado(estado),
                  activo: false,
                  icono: Icon(iconoAccionEstado(estado), size: 18, color: RBColores.azul),
                  onTap: () => _moderar(cambiarEstadoReporte(context, r, estado)),
                ),
            ],
          ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: RBColores.rojo,
            side: const BorderSide(color: RBColores.rojo, width: 1.4),
          ),
          onPressed: () => _moderar(suspenderAutorReporte(context, r)),
          icon: const Icon(Icons.block_rounded, size: 18),
          label: const Text('Suspender a quien reportó'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: RBColores.rojo),
          onPressed: () => _eliminar(r),
          icon: const Icon(Icons.delete_forever_rounded, size: 19),
          label: const Text('Eliminar reporte'),
        ),
      ],
    );
  }
}

/// Estado del reporte (uno solo: el efectivo) y "Solo grupo" si es privado.
class ChipsReporte extends StatelessWidget {
  final String estado;
  final bool soloGrupo;

  const ChipsReporte({super.key, required this.estado, required this.soloGrupo});

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 6, runSpacing: 4, children: [chipReporte(estado), if (soloGrupo) const ChipSoloGrupo()]);
  }
}
