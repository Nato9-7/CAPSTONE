import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/modelos.dart';
import 'package:rb_alertas/servicios/admin_servicio.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/vistas/admin/comun_admin.dart';
import 'package:rb_alertas/widgets/dialogos.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Cuentas de la app: búsqueda, suspensión y reactivación.
class PestanaUsuarios extends StatefulWidget {
  const PestanaUsuarios({super.key});

  @override
  State<PestanaUsuarios> createState() => _PestanaUsuariosState();
}

class _PestanaUsuariosState extends State<PestanaUsuarios> with AutomaticKeepAliveClientMixin {
  final _servicio = AdminServicio();
  final _buscador = TextEditingController();
  List<UsuarioAdmin>? _usuarios;
  String? _error;
  bool _soloSuspendidas = false;

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
      final usuarios = await _servicio.usuarios(buscar: _buscador.text, estado: _soloSuspendidas ? 'SUSPENDIDO' : null);
      if (mounted) {
        setState(() {
          _usuarios = usuarios;
          _revelados.clear(); // la lista recargada vuelve a traer los datos ocultos
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  Future<void> _cambiarEstado(UsuarioAdmin u) async {
    final suspender = u.estado != 'SUSPENDIDO';
    final confirmado = await confirmar(
      context,
      color: suspender ? RBColores.rojo : RBColores.verde,
      titulo: suspender ? 'Suspender cuenta' : 'Reactivar cuenta',
      mensaje: suspender
          ? '${u.nombreCompleto} (${u.email}) no podrá entrar a la app. '
                'Se cerrarán todas sus sesiones.'
          : '${u.nombreCompleto} (${u.email}) podrá volver a entrar a la app.',
      accion: suspender ? 'Suspender' : 'Reactivar',
    );
    if (!confirmado || !mounted) return;
    final aplicado = await ejecutarAccionAdmin(
      context,
      () => _servicio.cambiarEstadoUsuario(u.id, suspender ? 'SUSPENDIDO' : 'ACTIVO'),
      suspender ? 'Cuenta suspendida' : 'Cuenta reactivada',
    );
    if (aplicado && mounted) _cargar();
  }

  /// Cuentas cuyos datos completos ya se pidieron en esta sesión del panel.
  final Set<int> _revelados = {};

  Future<void> _revelar(UsuarioAdmin u) async {
    final confirmado = await confirmar(
      context,
      titulo: 'Ver datos de contacto',
      mensaje:
          'Se mostrarán el correo, RUT y teléfono completos de ${u.nombreCompleto}. '
          'Úsalos solo para moderar; la consulta queda registrada.',
      accion: 'Ver datos',
    );
    if (!confirmado || !mounted) return;
    try {
      final contacto = await _servicio.contactoUsuario(u.id);
      if (!mounted) return;
      setState(() {
        _revelados.add(u.id);
        final i = _usuarios?.indexWhere((x) => x.id == u.id) ?? -1;
        if (i >= 0) _usuarios![i] = u.conContacto(contacto);
      });
    } catch (e) {
      if (mounted) mostrarAviso(context, mensajeDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        BuscadorAdmin(
          controlador: _buscador,
          pista: 'Buscar por nombre, correo o RUT',
          alBuscar: _cargar,
          etiquetaInterruptor: 'Solo cuentas suspendidas',
          valorInterruptor: _soloSuspendidas,
          alCambiarInterruptor: (valor) {
            setState(() => _soloSuspendidas = valor);
            _cargar();
          },
        ),
        Expanded(
          child: ListaAdmin<UsuarioAdmin>(
            elementos: _usuarios,
            error: _error,
            recargar: _cargar,
            textoVacio: 'No se encontraron cuentas.',
            tarjeta: _tarjeta,
          ),
        ),
      ],
    );
  }

  Widget _tarjeta(UsuarioAdmin u) {
    final iniciales = [u.nombres, u.apellidos].where((x) => x.isNotEmpty).map((x) => x[0].toUpperCase()).join();
    // La cuenta admin y las eliminadas no se pueden suspender ni reactivar.
    final moderable = !u.esAdmin && u.estado != 'ELIMINADO';
    final suspendida = u.estado == 'SUSPENDIDO';

    return TarjetaRB(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: RBColores.azul50,
            child: Text(
              iniciales.isEmpty ? '?' : iniciales,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: RBColores.azul),
            ),
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
                      u.nombreCompleto.isEmpty ? u.email : u.nombreCompleto,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: RBColores.tinta),
                    ),
                    if (u.esAdmin)
                      const PildoraAdmin(texto: 'Admin', fondo: RBColores.azul, color: Colors.white)
                    else
                      chipCuenta(u.estado),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    u.email + (u.emailVerificado ? '' : ' (sin verificar)'),
                    [if (u.rut != null) 'RUT ${u.rut}', if (u.telefono != null) u.telefono!].join(' · '),
                    '${u.totalReportes} ${u.totalReportes == 1 ? 'reporte' : 'reportes'} · desde '
                        '${fechaHora(u.fechaCreacion?.toLocal()).split(' ').first}',
                  ].where((l) => l.isNotEmpty).join('\n'),
                  style: const TextStyle(fontSize: 13, color: RBColores.texto2, height: 1.4),
                ),
                // Los datos llegan parcialmente ocultos; verlos completos queda registrado.
                if (!_revelados.contains(u.id))
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      foregroundColor: RBColores.azul,
                    ),
                    onPressed: () => _revelar(u),
                    icon: const Icon(Icons.visibility_outlined, size: 17),
                    label: const Text('Ver datos de contacto'),
                  ),
              ],
            ),
          ),
          if (moderable)
            TextButton(
              onPressed: () => _cambiarEstado(u),
              style: TextButton.styleFrom(foregroundColor: suspendida ? RBColores.verde : RBColores.rojo),
              child: Text(suspendida ? 'Reactivar' : 'Suspender'),
            ),
        ],
      ),
    );
  }
}
