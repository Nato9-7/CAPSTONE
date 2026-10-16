import 'package:flutter/material.dart';
import 'package:rb_alertas/servicios/perfil_servicio.dart';
import 'package:rb_alertas/servicios/reporte_servicio.dart' show EntidadEmergencia;
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:url_launcher/url_launcher.dart';

/// Pregunta antes de llamar a una entidad de emergencia y abre el marcador.
Future<void> llamarEmergencia(BuildContext context, EntidadEmergencia entidad) async {
  final llamar = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(entidad.nombre),
      content: Text('¿Llamar al ${entidad.telefono}?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: RBColores.rojo),
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.call_rounded, size: 18),
          label: const Text('Llamar'),
        ),
      ],
    ),
  );
  if (llamar != true) return;
  final abierta = await launchUrl(Uri(scheme: 'tel', path: entidad.telefono))
      .catchError((_) => false);
  if (!abierta && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Marca al ${entidad.telefono}')));
  }
}

/// Panel inferior con los teléfonos de emergencia de la comuna del usuario
/// (los mismos accesos directos que antes estaban en el perfil).
Future<void> mostrarPanelEmergencias(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _PanelEmergencias(),
  );
}

class _PanelEmergencias extends StatefulWidget {
  const _PanelEmergencias();

  @override
  State<_PanelEmergencias> createState() => _PanelEmergenciasState();
}

class _PanelEmergenciasState extends State<_PanelEmergencias> {
  List<EntidadEmergencia>? _entidades;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final token = Sesion.token;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Inicia sesión para ver los teléfonos de emergencia de tu comuna.');
      return;
    }
    setState(() => _error = null);
    try {
      final perfil = await PerfilServicio().obtenerPerfil(token);
      if (!mounted) return;
      setState(() => _entidades = perfil.emergencias);
    } on PerfilServicioException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo conectar con el servidor');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: RBColores.rojo50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.notification_important_outlined, color: RBColores.rojo),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Emergencias',
                    style: TextStyle(
                      fontFamily: RBFuentes.titulos,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: RBColores.azul,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Llama directo a los servicios de emergencia de tu comuna.',
              style: TextStyle(fontSize: 15, color: RBColores.texto2),
            ),
            const SizedBox(height: 18),
            _contenido(),
          ],
        ),
      ),
    );
  }

  Widget _contenido() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: RBColores.texto2),
        ),
      );
    }
    final entidades = _entidades;
    if (entidades == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (entidades.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Todavía no hay teléfonos de emergencia cargados para tu comuna.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: RBColores.texto2),
        ),
      );
    }
    return Column(
      children: [
        for (final entidad in entidades)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _filaEntidad(entidad),
          ),
      ],
    );
  }

  Widget _filaEntidad(EntidadEmergencia entidad) {
    final (icono, color) = estiloEntidadEmergencia(entidad.tipo);
    return Material(
      color: RBColores.fondo,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => llamarEmergencia(context, entidad),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icono, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombreCortoEmergencia(entidad),
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        color: RBColores.tinta,
                      ),
                    ),
                    Text(
                      entidad.telefono,
                      style: const TextStyle(fontSize: 14.5, color: RBColores.texto2),
                    ),
                  ],
                ),
              ),
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: RBColores.rojo, shape: BoxShape.circle),
                child: const Icon(Icons.call_rounded, color: Colors.white, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String nombreCortoEmergencia(EntidadEmergencia entidad) {
  switch (entidad.tipo) {
    case 'CARABINEROS':
      return 'Carabineros';
    case 'BOMBEROS':
      return 'Bomberos';
    case 'SAMU':
      return 'SAMU';
    case 'SEGURIDAD_CIUDADANA':
      return 'Seguridad municipal';
    default:
      return entidad.nombre;
  }
}

(IconData, Color) estiloEntidadEmergencia(String tipo) {
  switch (tipo) {
    case 'CARABINEROS':
      return (Icons.shield_outlined, RBColores.verde);
    case 'BOMBEROS':
      return (Icons.local_fire_department_outlined, const Color(0xFFD2490B));
    case 'SAMU':
      return (Icons.local_hospital_outlined, const Color(0xFFBE185D));
    case 'SEGURIDAD_CIUDADANA':
      return (Icons.local_police_outlined, RBColores.azul);
    default:
      return (Icons.call_outlined, RBColores.texto2);
  }
}
