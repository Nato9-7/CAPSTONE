import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/grupo.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/servicios/grupos_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/vistas/grupos/widgets/chip_admin.dart';
import 'package:rb_alertas/widgets/dialogos.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Lista de vecinos del grupo, con su alias. El admin puede quitar a alguien.
/// Devuelve true si se quitó a alguien, para refrescar el contador.
class VecinosHoja extends StatefulWidget {
  final Grupo grupo;

  const VecinosHoja({super.key, required this.grupo});

  static Future<bool?> abrir(BuildContext context, {required Grupo grupo}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => VecinosHoja(grupo: grupo),
    );
  }

  @override
  State<VecinosHoja> createState() => _VecinosHojaState();
}

class _VecinosHojaState extends State<VecinosHoja> {
  final _servicio = GruposServicio();
  List<MiembroGrupo>? _miembros;
  String? _error;
  bool _huboCambios = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (!Sesion.activa) return;
    try {
      final miembros = await _servicio.miembros(widget.grupo.id);
      if (mounted) setState(() => _miembros = miembros);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  Future<void> _expulsar(MiembroGrupo miembro) async {
    if (!Sesion.activa) return;
    final confirmado = await confirmar(
      context,
      titulo: 'Quitar del grupo',
      mensaje: '¿Quitar a ${miembro.alias}? Dejará de ver los reportes del grupo. '
          'Para que no vuelva a entrar, genera un código nuevo.',
      accion: 'Quitar',
    );
    if (!confirmado) return;
    try {
      await _servicio.expulsar(idGrupo: widget.grupo.id, idMiembro: miembro.id);
      if (!mounted) return;
      setState(() {
        _miembros = _miembros?.where((m) => m.id != miembro.id).toList();
        _huboCambios = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final miembros = _miembros;
    return PopScope(
      canPop: false,
      // Se cierra devolviendo si hubo cambios, también con el gesto de volver.
      onPopInvokedWithResult: (yaCerro, _) {
        if (!yaCerro) Navigator.pop(context, _huboCambios);
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Vecinos del grupo',
                style: TextStyle(
                  fontFamily: RBFuentes.titulos,
                  fontSize: context.escala(26),
                  fontWeight: FontWeight.w800,
                  color: RBColores.azul,
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: AvisoRB(texto: _error!),
              ),
            if (miembros == null && _error == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (miembros != null)
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
                  itemCount: miembros.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, color: RBColores.linea),
                  itemBuilder: (_, indice) => _filaMiembro(miembros[indice]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filaMiembro(MiembroGrupo miembro) {
    final puedeQuitar = widget.grupo.esAdmin && !miembro.esAdmin;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const AvatarSuricata(tamano: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  miembro.soyYo ? '${miembro.alias} (tú)' : miembro.alias,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: RBColores.tinta),
                ),
                if (miembro.fechaUnion != null)
                  Text(
                    'Se unió ${tiempoRelativo(miembro.fechaUnion)}',
                    style: const TextStyle(fontSize: 14, color: RBColores.texto2),
                  ),
              ],
            ),
          ),
          if (miembro.esAdmin) const ChipAdmin(),
          if (puedeQuitar)
            IconButton(
              tooltip: 'Quitar del grupo',
              onPressed: () => _expulsar(miembro),
              icon: const Icon(Icons.person_remove_outlined, color: RBColores.rojo),
            ),
        ],
      ),
    );
  }
}
