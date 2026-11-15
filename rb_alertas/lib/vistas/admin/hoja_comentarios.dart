import 'package:flutter/material.dart';
import 'package:rb_alertas/config/api_config.dart';
import 'package:rb_alertas/modelos/modelos.dart';
import 'package:rb_alertas/servicios/admin_servicio.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/vistas/admin/comun_admin.dart';
import 'package:rb_alertas/widgets/dialogos.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Comentarios de un reporte para moderar: ocultar, volver a publicar,
/// eliminar o suspender a quien lo escribió.
class HojaComentarios extends StatefulWidget {
  final ReporteAdmin reporte;

  const HojaComentarios({super.key, required this.reporte});

  @override
  State<HojaComentarios> createState() => _HojaComentariosState();
}

class _HojaComentariosState extends State<HojaComentarios> {
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
      final comentarios = await _servicio.comentarios(widget.reporte.id);
      if (mounted) setState(() => _comentarios = comentarios);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  /// Ejecuta la acción y recarga la lista si se aplicó.
  Future<void> _aplicar(Future<void> Function() accion, String exito) async {
    if (await ejecutarAccionAdmin(context, accion, exito) && mounted) _cargar();
  }

  Future<void> _cambiarEstado(ComentarioAdmin c, String estado) => _aplicar(
    () => _servicio.cambiarEstadoComentario(c.id, estado),
    estado == 'OCULTO' ? 'Comentario oculto' : 'Comentario publicado de nuevo',
  );

  Future<void> _eliminar(ComentarioAdmin c) async {
    final confirmado = await confirmar(
      context,
      titulo: 'Eliminar comentario',
      mensaje: 'Desaparece de la app para todos y se borra su foto. No se puede deshacer '
          '(si solo quieres esconderlo por ahora, usa «Ocultar»).',
      accion: 'Eliminar',
    );
    if (confirmado) await _aplicar(() => _servicio.eliminarComentario(c.id), 'Comentario eliminado');
  }

  Future<void> _suspenderAutor(ComentarioAdmin c) async {
    final confirmado = await confirmar(
      context,
      titulo: 'Suspender a ${c.autor ?? 'quien lo escribió'}',
      mensaje: 'No podrá volver a entrar a la app y se cerrarán sus sesiones. Puedes '
          'reactivar la cuenta en la pestaña Usuarios.',
      accion: 'Suspender',
    );
    if (confirmado) await _aplicar(() => _servicio.suspenderAutorComentario(c.id), 'Cuenta suspendida');
  }

  @override
  Widget build(BuildContext context) {
    final comentarios = _comentarios;
    final Widget cuerpo;
    if (comentarios == null) {
      cuerpo = cargandoOError(_error, _cargar);
    } else if (comentarios.isEmpty) {
      cuerpo = const MensajeCentro('Este reporte no tiene comentarios.');
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
          EncabezadoHoja('Comentarios del reporte #${widget.reporte.id}'),
          Expanded(child: cuerpo),
        ],
      ),
    );
  }

  Widget _tarjeta(ComentarioAdmin c) {
    final (texto, fondo, color) = switch (c.estado) {
      'PUBLICADO' => ('Publicado', RBColores.verde50, RBColores.verde),
      'OCULTO' => ('Oculto', RBColores.rojo50, RBColores.rojo),
      _ => ('Eliminado', RBColores.linea, RBColores.texto2),
    };
    return TarjetaRB(
      // Las respuestas van con sangría bajo su comentario.
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
                      const Icon(Icons.subdirectory_arrow_right_rounded, size: 16, color: RBColores.texto2),
                    Text(
                      c.autor ?? 'Vecino',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: RBColores.tinta),
                    ),
                    PildoraAdmin(
                      texto: texto,
                      fondo: fondo,
                      color: color,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      tamano: 12,
                    ),
                  ],
                ),
                if (c.contenido.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(c.contenido, style: const TextStyle(fontSize: 14, height: 1.35, color: RBColores.tinta)),
                ],
                if (c.imagen != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      ApiConfig.urlArchivo(c.imagen!),
                      height: 110,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: RBColores.texto2),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  fechaHora(c.fechaCreacion?.toLocal()),
                  style: const TextStyle(fontSize: 12.5, color: RBColores.texto2),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Moderar',
            color: Colors.white,
            surfaceTintColor: Colors.transparent,
            icon: const Icon(Icons.more_vert, color: RBColores.texto2),
            onSelected: (accion) => switch (accion) {
              'OCULTAR' => _cambiarEstado(c, 'OCULTO'),
              'PUBLICAR' => _cambiarEstado(c, 'PUBLICADO'),
              'ELIMINAR' => _eliminar(c),
              _ => _suspenderAutor(c),
            },
            itemBuilder: (_) => [
              if (c.estado == 'PUBLICADO') const PopupMenuItem(value: 'OCULTAR', child: Text('Ocultar')),
              if (c.estado == 'OCULTO') const PopupMenuItem(value: 'PUBLICAR', child: Text('Publicar de nuevo')),
              if (c.estado != 'ELIMINADO')
                const PopupMenuItem(
                  value: 'ELIMINAR',
                  child: Text(
                    'Eliminar comentario',
                    style: TextStyle(fontWeight: FontWeight.w700, color: RBColores.rojo),
                  ),
                ),
              const PopupMenuItem(
                value: 'SUSPENDER',
                child: Text('Suspender a quien lo escribió', style: TextStyle(color: RBColores.rojo)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
