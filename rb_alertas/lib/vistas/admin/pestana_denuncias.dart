import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/modelos.dart';
import 'package:rb_alertas/servicios/admin_servicio.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/vistas/admin/comun_admin.dart';
import 'package:rb_alertas/vistas/admin/moderacion_reporte.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';
import 'package:rb_alertas/widgets/dialogos.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Lo que los vecinos denunciaron, junto por reporte o comentario.
class PestanaDenuncias extends StatefulWidget {
  const PestanaDenuncias({super.key});

  @override
  State<PestanaDenuncias> createState() => _PestanaDenunciasState();
}

class _PestanaDenunciasState extends State<PestanaDenuncias> with AutomaticKeepAliveClientMixin {
  static const _filtros = [
    ('PENDIENTE', 'Pendientes'),
    ('ATENDIDA', 'Atendidas'),
    ('DESESTIMADA', 'Desestimadas'),
  ];

  final _servicio = AdminServicio();
  List<DenunciaAdmin>? _denuncias;
  String? _error;
  String _estado = 'PENDIENTE';

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
      final denuncias = await _servicio.denuncias(estado: _estado);
      if (mounted) setState(() => _denuncias = denuncias);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  void _filtrar(String estado) {
    setState(() {
      _estado = estado;
      _denuncias = null;
    });
    _cargar();
  }

  /// Confirma, ejecuta y recarga la lista.
  Future<void> _hacer(
    String titulo,
    String mensaje,
    String boton,
    Future<void> Function() accion,
    String exito, {
    bool peligro = true,
  }) async {
    final confirmado = await confirmar(context, titulo: titulo, mensaje: mensaje, accion: boton, peligro: peligro);
    if (!confirmado || !mounted) return;
    if (await ejecutarAccionAdmin(context, accion, exito) && mounted) _cargar();
  }

  Future<void> _moderarReporte(DenunciaAdmin d) async {
    // Descartar o eliminar el reporte desde la ficha atiende sus denuncias.
    if (await abrirModeracion(context, d.idReporte) && mounted) _cargar();
  }

  List<Widget> _acciones(DenunciaAdmin d) {
    final oculto = d.estadoComentario == 'OCULTO';
    final desestimar = TextButton(
      onPressed: () => _hacer(
        'Desestimar denuncias',
        d.esComentario && oculto
            ? 'El comentario no infringe las normas: vuelve a publicarse y las denuncias se cierran.'
            : 'No hay nada que corregir: las denuncias se cierran y todo queda como está.',
        'Desestimar',
        () => _servicio.revisarDenuncias(d, 'DESESTIMADA'),
        'Denuncias desestimadas',
        peligro: false,
      ),
      child: const Text('Desestimar'),
    );
    if (!d.esComentario) {
      return [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: RBColores.rojo),
          onPressed: () => _moderarReporte(d),
          icon: const Icon(Icons.shield_outlined, size: 18),
          label: const Text('Moderar reporte'),
        ),
        TextButton(
          onPressed: () => _hacer(
            'Marcar como atendidas',
            'Úsalo si ya lo resolviste de otra forma (por ejemplo, suspendiendo a quien lo creó).',
            'Marcar atendidas',
            () => _servicio.revisarDenuncias(d, 'ATENDIDA'),
            'Denuncias atendidas',
            peligro: false,
          ),
          child: const Text('Marcar atendidas'),
        ),
        desestimar,
      ];
    }
    final id = d.idComentario!;
    return [
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: RBColores.rojo),
        onPressed: () => _hacer(
          'Eliminar comentario',
          'Desaparece de la app para todos y se borra su foto. No se puede deshacer.',
          'Eliminar',
          () => _servicio.eliminarComentario(id),
          'Comentario eliminado',
        ),
        icon: const Icon(Icons.delete_forever_rounded, size: 18),
        label: const Text('Eliminar'),
      ),
      if (oculto)
        OutlinedButton(
          onPressed: () => _hacer(
            'Dejar oculto',
            'El comentario sigue oculto y las denuncias quedan atendidas.',
            'Dejar oculto',
            () => _servicio.revisarDenuncias(d, 'ATENDIDA'),
            'Comentario oculto; denuncias atendidas',
            peligro: false,
          ),
          child: const Text('Dejar oculto'),
        )
      else
        OutlinedButton(
          onPressed: () => _hacer(
            'Ocultar comentario',
            'Deja de verse en la app (puedes volver a publicarlo después).',
            'Ocultar',
            () => _servicio.cambiarEstadoComentario(id, 'OCULTO'),
            'Comentario oculto',
          ),
          child: const Text('Ocultar'),
        ),
      OutlinedButton(
        style: OutlinedButton.styleFrom(foregroundColor: RBColores.rojo),
        onPressed: () => _hacer(
          'Suspender a quien lo escribió',
          'Su cuenta no podrá entrar ni publicar hasta que la reactives en Usuarios.',
          'Suspender',
          () => _servicio.suspenderAutorComentario(id),
          'Cuenta suspendida',
        ),
        child: const Text('Suspender autor'),
      ),
      desestimar,
    ];
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        FiltrosAdmin<String>(opciones: _filtros, seleccionado: _estado, alElegir: _filtrar),
        Expanded(
          child: ListaAdmin<DenunciaAdmin>(
            elementos: _denuncias,
            error: _error,
            recargar: _cargar,
            textoVacio: _estado == 'PENDIENTE'
                ? 'No hay denuncias por revisar.'
                : 'No hay denuncias con este filtro.',
            tarjeta: _tarjeta,
          ),
        ),
      ],
    );
  }

  Widget _tarjeta(DenunciaAdmin d) {
    final texto = d.esComentario ? (d.contenido ?? '') : d.descripcion;
    return TarjetaRB(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconoCategoria(codigo: d.categoriaCodigo, colorHex: d.colorHex, tamano: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.esComentario
                          ? 'Comentario en el reporte #${d.idReporte}'
                          : 'Reporte #${d.idReporte} · ${d.categoria}',
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: RBColores.tinta),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        chipCuenta('SUSPENDIDO', texto: d.total == 1 ? '1 denuncia' : '${d.total} denuncias'),
                        if (d.esComentario && d.estadoComentario == 'OCULTO')
                          chipCuenta('OTRO', texto: 'Oculto')
                        else if (d.esComentario && d.estadoComentario == 'ELIMINADO')
                          chipCuenta('OTRO', texto: 'Eliminado')
                        else if (!d.esComentario)
                          chipReporte(d.estadoReporte),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: RBColores.fondo,
              borderRadius: BorderRadius.circular(RBRadios.campo),
            ),
            child: Text(
              texto.isEmpty ? '(sin texto)' : texto,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14.5, height: 1.4, color: RBColores.tinta),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Motivos: ${d.motivos.map(MotivoDenuncia.textoDe).join(' · ')}',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: RBColores.tinta),
          ),
          for (final detalle in d.detalles.take(3))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '«$detalle»',
                style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: RBColores.texto2),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Última denuncia: ${fechaHora(d.ultima?.toLocal())}',
            style: const TextStyle(fontSize: 12.5, color: RBColores.texto2),
          ),
          if (_estado == 'PENDIENTE') ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: _acciones(d)),
          ],
        ],
      ),
    );
  }
}
