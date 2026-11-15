import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:rb_alertas/modelos/grupo.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/servicios/grupos_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/dialogos.dart';
import 'package:rb_alertas/widgets/editor_area.dart';
import 'package:rb_alertas/widgets/fondo_acceso.dart' show CampoRotulado;

/// Crea o edita un grupo vecinal. Se muestra como panel inferior, igual que
/// el editor de zonas seguras; devuelve el grupo guardado o null si se cerró.
class GrupoFormularioVista extends StatefulWidget {
  final Grupo? grupo;
  final List<int> radiosPermitidos;

  const GrupoFormularioVista({super.key, this.grupo, required this.radiosPermitidos});

  static Future<Grupo?> abrir(
    BuildContext context, {
    Grupo? grupo,
    required List<int> radiosPermitidos,
  }) {
    return showModalBottomSheet<Grupo>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      builder: (_) => GrupoFormularioVista(grupo: grupo, radiosPermitidos: radiosPermitidos),
    );
  }

  @override
  State<GrupoFormularioVista> createState() => _GrupoFormularioVistaState();
}

class _GrupoFormularioVistaState extends State<GrupoFormularioVista> with EditorArea {
  final _servicio = GruposServicio();
  final _nombreCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();
  bool _guardando = false;

  bool get _esNuevo => widget.grupo == null;

  @override
  void initState() {
    super.initState();
    final grupo = widget.grupo;
    _nombreCtrl.text = grupo?.nombre ?? '';
    _descripcionCtrl.text = grupo?.descripcion ?? '';
    iniciarArea(
      radiosPermitidos: widget.radiosPermitidos,
      centroInicial: grupo == null ? null : LatLng(grupo.latitud, grupo.longitud),
      radioInicial: grupo?.radioMetros,
      direccion: grupo?.direccion,
    );
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descripcionCtrl.dispose();
    liberarArea();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!Sesion.activa) {
      mostrarAviso(context, 'Inicia sesión para crear un grupo');
      return;
    }
    if (_nombreCtrl.text.trim().isEmpty) {
      mostrarAviso(context, 'Escribe un nombre para el grupo');
      return;
    }

    setState(() => _guardando = true);
    try {
      final grupo = _esNuevo
          ? await _servicio.crear(
              nombre: _nombreCtrl.text,
              descripcion: _descripcionCtrl.text,
              latitud: centro.latitude,
              longitud: centro.longitude,
              radioMetros: radio,
              direccion: direccionCtrl.text,
            )
          : await _servicio.actualizar(
              idGrupo: widget.grupo!.id,
              nombre: _nombreCtrl.text,
              descripcion: _descripcionCtrl.text,
              latitud: centro.latitude,
              longitud: centro.longitude,
              radioMetros: radio,
              direccion: direccionCtrl.text,
            );
      if (!mounted) return;
      Navigator.pop(context, grupo);
    } catch (e) {
      mostrarAviso(context, mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PanelEditorArea(
      titulo: _esNuevo ? 'Nuevo grupo' : 'Editar grupo',
      textoGuardar: _esNuevo ? 'Crear grupo' : 'Guardar cambios',
      guardando: _guardando,
      onCerrar: () => Navigator.pop(context),
      onGuardar: _guardar,
      children: [
        CampoRotulado(
          rotulo: 'Nombre del grupo',
          campo: TextField(
            controller: _nombreCtrl,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Junta de vecinos Villa Los Notros',
              counterText: '',
              prefixIcon: Icon(Icons.groups_outlined, color: RBColores.azul),
            ),
          ),
        ),
        const SizedBox(height: 18),
        CampoRotulado(
          rotulo: 'Descripción (opcional)',
          campo: TextField(
            controller: _descripcionCtrl,
            maxLength: 255,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Para avisarnos entre vecinos del pasaje',
              counterText: '',
            ),
          ),
        ),
        const SizedBox(height: 18),
        campoDireccion(),
        const SizedBox(height: 22),
        selectorRadio(
          titulo: 'Radio del grupo',
          alcance: (minutos) => 'Los vecinos podrán compartir en el grupo los incidentes a menos de '
              '$minutos minutos caminando desde el centro.',
        ),
        const SizedBox(height: 22),
        const Text('Área del grupo', style: RBTexto.rotuloCampo),
        const SizedBox(height: 4),
        const Text(
          'Mueve el mapa hasta dejar el punto en el centro del sector.',
          style: TextStyle(fontSize: 14, color: RBColores.texto2),
        ),
        const SizedBox(height: 10),
        vistaPrevia(color: RBColores.azul, opacidad: 0.12, icono: Icons.groups_rounded),
      ],
    );
  }
}
