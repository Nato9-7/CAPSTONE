import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:rb_alertas/modelos/zona_segura.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/servicios/zonas_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/dialogos.dart';
import 'package:rb_alertas/widgets/editor_area.dart';
import 'package:rb_alertas/widgets/fondo_acceso.dart' show CampoRotulado;
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Crea o edita una zona segura. Se muestra como panel inferior sobre la
/// lista de zonas; devuelve `true` si se guardó o se eliminó algo.
class ZonaDetalleVista extends StatefulWidget {
  final ZonaSegura? zona;
  final List<int> radiosPermitidos;

  const ZonaDetalleVista({super.key, this.zona, required this.radiosPermitidos});

  static Future<bool?> abrir(
    BuildContext context, {
    ZonaSegura? zona,
    required List<int> radiosPermitidos,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      builder: (_) => ZonaDetalleVista(zona: zona, radiosPermitidos: radiosPermitidos),
    );
  }

  @override
  State<ZonaDetalleVista> createState() => _ZonaDetalleVistaState();
}

class _ZonaDetalleVistaState extends State<ZonaDetalleVista> with EditorArea {
  final _servicio = ZonasServicio();
  final _nombreCtrl = TextEditingController();
  late TipoZona _tipo;
  bool _guardando = false;

  bool get _esNueva => widget.zona == null;

  @override
  void initState() {
    super.initState();
    final zona = widget.zona;
    _tipo = zona?.tipo ?? TipoZona.casa;
    _nombreCtrl.text = zona != null && zona.tipo == TipoZona.otro ? zona.nombre : '';
    iniciarArea(
      radiosPermitidos: widget.radiosPermitidos,
      centroInicial: zona == null ? null : LatLng(zona.latitud, zona.longitud),
      radioInicial: zona?.radioMetros,
      direccion: zona?.direccion,
    );
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    liberarArea();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!Sesion.activa) {
      mostrarAviso(context, 'Inicia sesión para guardar tus zonas');
      return;
    }
    if (_tipo.nombreLibre && _nombreCtrl.text.trim().isEmpty) {
      mostrarAviso(context, 'Escribe un nombre para la zona');
      return;
    }

    setState(() => _guardando = true);
    try {
      if (_esNueva) {
        await _servicio.crear(
          tipo: _tipo,
          nombre: _nombreCtrl.text,
          latitud: centro.latitude,
          longitud: centro.longitude,
          radioMetros: radio,
          direccion: direccionCtrl.text,
        );
      } else {
        await _servicio.actualizar(
          idZona: widget.zona!.id,
          tipo: _tipo,
          nombre: _nombreCtrl.text,
          latitud: centro.latitude,
          longitud: centro.longitude,
          radioMetros: radio,
          direccion: direccionCtrl.text,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      mostrarAviso(context, mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _eliminar() async {
    final zona = widget.zona;
    if (zona == null || !Sesion.activa) return;

    final confirmado = await confirmar(
      context,
      titulo: 'Eliminar zona',
      mensaje: '¿Eliminar «${zona.nombre}»? Dejarás de recibir alertas de lo que '
          'ocurra en ese sector.',
      accion: 'Eliminar',
    );
    if (!confirmado || !mounted) return;

    setState(() => _guardando = true);
    try {
      await _servicio.eliminar(zona.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      mostrarAviso(context, mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PanelEditorArea(
      titulo: _esNueva ? 'Nueva ubicación' : 'Editar ubicación',
      textoGuardar: _esNueva ? 'Guardar zona' : 'Guardar cambios',
      guardando: _guardando,
      onCerrar: () => Navigator.pop(context, false),
      onGuardar: _guardar,
      children: [
        _tipoDeLugar(),
        const SizedBox(height: 18),
        _campoNombre(),
        const SizedBox(height: 18),
        campoDireccion(),
        const SizedBox(height: 22),
        selectorRadio(
          titulo: 'Radio de cobertura',
          alcance: (minutos) => 'Recibirás alertas de incidentes a menos de $minutos '
              'minutos caminando desde esta ubicación.',
        ),
        const SizedBox(height: 22),
        const Text('Vista previa', style: RBTexto.rotuloCampo),
        const SizedBox(height: 4),
        const Text(
          'Mueve el mapa hasta dejar el punto sobre el lugar exacto.',
          style: TextStyle(fontSize: 14, color: RBColores.texto2),
        ),
        const SizedBox(height: 10),
        vistaPrevia(color: RBColores.verde, opacidad: 0.15, icono: _tipo.icono),
        if (!_esNueva) ...[
          const SizedBox(height: 14),
          Center(
            child: TextButton.icon(
              onPressed: _guardando ? null : _eliminar,
              style: TextButton.styleFrom(foregroundColor: RBColores.rojo),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Eliminar ubicación'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _tipoDeLugar() {
    return CampoRotulado(
      rotulo: 'Tipo de lugar',
      campo: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tipo in TipoZona.values)
            ChipFiltro(
              etiqueta: tipo.etiqueta,
              activo: _tipo == tipo,
              icono: Icon(tipo.icono, size: 19, color: RBColores.verde),
              onTap: () => setState(() => _tipo = tipo),
            ),
        ],
      ),
    );
  }

  /// Solo "Otro lugar" lleva nombre propio: en los demás lo fija el servidor,
  /// y así el nombre guardado siempre corresponde al ícono.
  Widget _campoNombre() {
    if (!_tipo.nombreLibre) {
      return CampoRotulado(
        rotulo: 'Nombre de la ubicación',
        campo: InputDecorator(
          decoration: const InputDecoration(
            enabled: false,
            helperText: 'El nombre lo define el tipo de lugar',
            fillColor: RBColores.fondo,
          ),
          child: Text(_tipo.etiqueta, style: const TextStyle(fontSize: 16, color: RBColores.tinta)),
        ),
      );
    }
    return CampoRotulado(
      rotulo: 'Nombre de la ubicación',
      campo: TextField(
        controller: _nombreCtrl,
        maxLength: 60,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Colegio, casa de mis padres…', counterText: ''),
      ),
    );
  }
}
