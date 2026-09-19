import 'package:flutter/material.dart';
import 'package:rb_alertas/servicios/perfil_servicio.dart';
import 'package:rb_alertas/servicios/reporte_servicio.dart' show EntidadEmergencia;
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/vistas/inicio_sesion_vista.dart';
import 'package:rb_alertas/widgets/barra_navegacion_inferior.dart';
import 'package:url_launcher/url_launcher.dart';

class PerfilVista extends StatefulWidget {
  const PerfilVista({super.key});

  @override
  State<PerfilVista> createState() => _PerfilVistaState();
}

class _PerfilVistaState extends State<PerfilVista> {
  static const _colorAzul = Color(0xFF0056D2);
  static const _colorFondo = Color(0xFFF7F8FC);
  static const _colorTitulo = Color(0xFF111827);
  static const _colorTextoGris = Color(0xFF6B7280);
  static const _colorBorde = Color(0xFFE5E7EB);
  static const _colorVerde = Color(0xFF16A34A);
  static const _colorRojo = Color(0xFFDC2626);

  final _perfilServicio = PerfilServicio();
  PerfilUsuario? _perfil;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final token = Sesion.token;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Inicia sesión para ver tu perfil');
      return;
    }
    setState(() => _error = null);
    try {
      final perfil = await _perfilServicio.obtenerPerfil(token);
      if (!mounted) return;
      setState(() => _perfil = perfil);
    } on PerfilServicioException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo conectar con el servidor');
    }
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _llamar(EntidadEmergencia entidad) async {
    final llamar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entidad.nombre),
        content: Text('¿Llamar al ${entidad.telefono}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _colorRojo),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.phone, size: 18),
            label: const Text('Llamar'),
          ),
        ],
      ),
    );
    if (llamar != true) return;
    final abierta = await launchUrl(Uri(scheme: 'tel', path: entidad.telefono))
        .catchError((_) => false);
    if (!abierta && mounted) _mostrarMensaje('Marca al ${entidad.telefono}');
  }

  Future<void> _cerrarSesion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Quieres salir de tu cuenta en este dispositivo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _colorRojo),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    final token = Sesion.token;
    if (token != null && token.isNotEmpty) {
      await _perfilServicio.cerrarSesion(token);
    }
    Sesion.cerrar();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const InicioSesionVista()),
      (ruta) => false,
    );
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        backgroundColor: _colorFondo,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: _colorAzul),
          onPressed: () {},
        ),
        title: const Text(
          'RB Alertas',
          style: TextStyle(color: _colorAzul, fontWeight: FontWeight.w800, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Color(0xFF374151)),
            onPressed: () {},
          ),
        ],
      ),
      body: _cuerpo(),
      bottomNavigationBar: const BarraNavegacionInferior(seccionActiva: SeccionApp.perfil),
    );
  }

  Widget _cuerpo() {
    final perfil = _perfil;
    if (perfil == null) {
      if (_error == null) {
        return const Center(child: CircularProgressIndicator(color: _colorAzul));
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _colorTextoGris)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _tarjetaUsuario(perfil),
                  const SizedBox(height: 20),
                  const Text(
                    'Accesos Directos Emergencias',
                    style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: _colorTitulo),
                  ),
                  const SizedBox(height: 12),
                  _emergencias(perfil),
                  const SizedBox(height: 20),
                  _opciones(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration get _estiloTarjeta => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _colorBorde),
      );

  Widget _tarjetaUsuario(PerfilUsuario p) {
    final iniciales = [p.nombres, p.apellidos]
        .where((x) => x.isNotEmpty)
        .map((x) => x[0].toUpperCase())
        .join();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: _estiloTarjeta,
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 42,
                backgroundColor: const Color(0xFFE5EDFF),
                backgroundImage: (p.urlFoto != null && p.urlFoto!.isNotEmpty)
                    ? NetworkImage(p.urlFoto!)
                    : null,
                child: (p.urlFoto == null || p.urlFoto!.isEmpty)
                    ? Text(
                        iniciales.isEmpty ? '?' : iniciales,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: _colorAzul),
                      )
                    : null,
              ),
              // El visto verde indica que la cuenta tiene el correo verificado.
              if (p.emailVerificado)
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _colorVerde,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(Icons.check, size: 12, color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            p.nombreCompleto.isEmpty ? p.email : p.nombreCompleto,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _colorTitulo),
          ),
          const SizedBox(height: 4),
          Text(p.lugar, style: const TextStyle(fontSize: 13, color: _colorTextoGris)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _contador('${p.totalReportes}', 'Reportes\nRealizados', _colorAzul)),
              const SizedBox(width: 12),
              Expanded(child: _contador('${p.totalResueltos}', 'Alertas\nResueltas', _colorVerde)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contador(String valor, String etiqueta, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(valor, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(
            etiqueta,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5, color: _colorTextoGris, height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _emergencias(PerfilUsuario p) {
    if (p.emergencias.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _estiloTarjeta,
        child: const Text(
          'Todavía no hay teléfonos de emergencia cargados para tu comuna.',
          style: TextStyle(fontSize: 13, color: _colorTextoGris),
        ),
      );
    }
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.25,
      children: [for (final e in p.emergencias) _tarjetaEmergencia(e)],
    );
  }

  Widget _tarjetaEmergencia(EntidadEmergencia entidad) {
    final (icono, color) = _estiloEntidad(entidad.tipo);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _llamar(entidad),
        child: Container(
          decoration: _estiloTarjeta,
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(icono, color: color, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                _nombreCorto(entidad),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _colorTitulo),
              ),
              const SizedBox(height: 2),
              Text(entidad.telefono, style: const TextStyle(fontSize: 12.5, color: _colorTextoGris)),
            ],
          ),
        ),
      ),
    );
  }

  String _nombreCorto(EntidadEmergencia entidad) {
    switch (entidad.tipo) {
      case 'CARABINEROS':
        return 'Carabineros';
      case 'BOMBEROS':
        return 'Bomberos';
      case 'SAMU':
        return 'SAMU';
      case 'SEGURIDAD_CIUDADANA':
        return 'Seguridad Mun.';
      default:
        return entidad.nombre;
    }
  }

  (IconData, Color) _estiloEntidad(String tipo) {
    switch (tipo) {
      case 'CARABINEROS':
        return (Icons.shield_outlined, _colorVerde);
      case 'BOMBEROS':
        return (Icons.local_fire_department_outlined, _colorRojo);
      case 'SAMU':
        return (Icons.medical_services_outlined, _colorAzul);
      case 'SEGURIDAD_CIUDADANA':
        return (Icons.local_police_outlined, const Color(0xFFF59E0B));
      default:
        return (Icons.phone_outlined, _colorTextoGris);
    }
  }

  Widget _opciones() {
    return Container(
      decoration: _estiloTarjeta,
      child: Column(
        children: [
          _opcion(
            Icons.person_outline,
            'Editar Perfil',
            () => _mostrarMensaje('Editar perfil estará disponible pronto'),
          ),
          const Divider(height: 1, color: _colorBorde),
          _opcion(
            Icons.lock_outline,
            'Privacidad y Seguridad',
            () => _mostrarMensaje('Privacidad y seguridad estará disponible pronto'),
          ),
          const Divider(height: 1, color: _colorBorde),
          _opcion(Icons.logout, 'Cerrar Sesión', _cerrarSesion, color: _colorRojo, flecha: false),
        ],
      ),
    );
  }

  Widget _opcion(
    IconData icono,
    String texto,
    VoidCallback alTocar, {
    Color color = _colorTitulo,
    bool flecha = true,
  }) {
    return ListTile(
      onTap: alTocar,
      leading: Icon(icono, color: color == _colorTitulo ? _colorTextoGris : color, size: 22),
      title: Text(
        texto,
        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: color),
      ),
      trailing: flecha ? const Icon(Icons.chevron_right, color: _colorTextoGris, size: 20) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }
}
