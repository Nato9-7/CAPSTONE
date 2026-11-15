import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/territorio.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/servicios/auth_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/fondo_acceso.dart';

/// Región y comuna del registro: dos listas encadenadas con las comunas que
/// tienen cobertura. Ambas son obligatorias y se validan con el formulario.
class SelectorComuna extends StatefulWidget {
  final ValueChanged<Comuna?> alCambiar;

  const SelectorComuna({super.key, required this.alCambiar});

  @override
  State<SelectorComuna> createState() => _SelectorComunaState();
}

class _SelectorComunaState extends State<SelectorComuna> {
  List<Region>? _regiones;
  String? _error;
  Region? _region;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final regiones = await AuthServicio().regionesRegistro();
      if (!mounted) return;
      setState(() {
        _regiones = regiones;
        // Con una sola región no hay nada que elegir.
        if (regiones.length == 1) _region = regiones.first;
      });
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  void _elegirRegion(Region? region) {
    setState(() => _region = region);
    widget.alCambiar(null);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return CampoRotulado(
        rotulo: 'Región y comuna',
        campo: Row(
          children: [
            Expanded(
              child: Text(_error!, style: const TextStyle(color: RBColores.rojo, fontSize: 14)),
            ),
            TextButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    final regiones = _regiones ?? const <Region>[];
    final cargando = _regiones == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CampoRotulado(
          rotulo: 'Región',
          campo: DropdownButtonFormField<Region>(
            initialValue: _region,
            isExpanded: true,
            hint: Text(cargando ? 'Cargando…' : 'Elige tu región'),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.map_outlined)),
            validator: (valor) => valor == null ? 'Elige tu región' : null,
            items: [
              for (final r in regiones)
                DropdownMenuItem(value: r, child: Text(r.etiqueta, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: cargando ? null : _elegirRegion,
          ),
        ),
        const SizedBox(height: 14),
        CampoRotulado(
          rotulo: 'Comuna',
          // La llave reinicia la comuna elegida al cambiar de región.
          campo: DropdownButtonFormField<Comuna>(
            key: ValueKey(_region?.id),
            isExpanded: true,
            hint: Text(_region == null ? 'Primero elige la región' : 'Elige tu comuna'),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.location_city_outlined)),
            validator: (valor) => valor == null ? 'Elige tu comuna' : null,
            items: [
              for (final c in _region?.comunas ?? const <Comuna>[])
                DropdownMenuItem(value: c, child: Text(c.nombre, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: _region == null ? null : widget.alCambiar,
          ),
        ),
      ],
    );
  }
}
