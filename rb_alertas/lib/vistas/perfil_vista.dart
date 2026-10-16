import 'package:flutter/material.dart';
import 'package:rb_alertas/config/app_info.dart';
import 'package:rb_alertas/servicios/estado_alertas_servicio.dart';
import 'package:rb_alertas/servicios/perfil_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/servicios/zonas_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/inicio_sesion_vista.dart';
import 'package:rb_alertas/vistas/mapa_vista.dart';
import 'package:rb_alertas/vistas/zonas_seguras_vista.dart';
import 'package:rb_alertas/widgets/barra_navegacion_inferior.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Perfil del usuario. Las estadísticas se ven en Alertas › Mis reportes y los
/// teléfonos de emergencia en el botón "Emergencias" del mapa.
class PerfilVista extends StatefulWidget {
  const PerfilVista({super.key});

  @override
  State<PerfilVista> createState() => _PerfilVistaState();
}

class _PerfilVistaState extends State<PerfilVista> {
  // En pantallas bajas la franja azul y el avatar se achican.
  double get _altoEncabezado => context.pantallaBaja ? 128 : 180;
  double get _tamanoAvatar => context.escala(context.pantallaBaja ? 118 : 150);

  final _perfilServicio = PerfilServicio();
  PerfilUsuario? _perfil;
  int? _cantidadZonas;
  String? _error;
  bool _sinSesion = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final token = Sesion.token;
    if (token == null || token.isEmpty) {
      setState(() {
        _sinSesion = true;
        _error = 'Inicia sesión para ver tu perfil';
      });
      return;
    }
    setState(() {
      _error = null;
      _sinSesion = false;
    });
    _cargarZonas(token);
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

  Future<void> _cargarZonas(String token) async {
    try {
      final datos = await ZonasServicio().listar(token);
      if (mounted) setState(() => _cantidadZonas = datos.zonas.length);
    } catch (_) {
      // Sin el dato, la fila de zonas se muestra sin contador.
    }
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _cerrarSesion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Quieres salir de tu cuenta en este dispositivo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: RBColores.rojo),
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
    await Sesion.cerrar();
    EstadoAlertas.limpiar();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const MapaVista()),
      (ruta) => false,
    );
  }

  Future<void> _abrirZonas() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ZonasSegurasVista()),
    );
    final token = Sesion.token;
    if (mounted && token != null) _cargarZonas(token);
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RBColores.fondo,
      body: _cuerpo(),
      bottomNavigationBar: const BarraNavegacionInferior(
        seccionActiva: SeccionApp.perfil,
      ),
    );
  }

  Widget _cuerpo() {
    final perfil = _perfil;
    if (perfil == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _encabezado(perfil),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: perfil == null ? _sinPerfil() : _contenido(perfil),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Franja azul marino con el título, "Cerrar sesión" y el avatar montado
  /// sobre el borde inferior.
  Widget _encabezado(PerfilUsuario? perfil) {
    final arriba = MediaQuery.of(context).padding.top;
    return SizedBox(
      height: _altoEncabezado + arriba + _tamanoAvatar / 2 + 6,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Container(
            height: _altoEncabezado + arriba,
            decoration: const BoxDecoration(
              color: RBColores.azul,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
            ),
            padding: EdgeInsets.fromLTRB(24, arriba + 20, 16, 0),
            alignment: Alignment.topCenter,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Perfil',
                    style: TextStyle(
                      fontFamily: RBFuentes.titulos,
                      fontSize: context.escala(34),
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (perfil != null)
                  OutlinedButton.icon(
                    onPressed: _cerrarSesion,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      minimumSize: const Size(0, 52),
                      textStyle: const TextStyle(
                        fontFamily: RBFuentes.interfaz,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 20),
                    label: const Text('Cerrar sesión'),
                  ),
              ],
            ),
          ),
          Positioned(
            bottom: 0,
            child: _avatar(perfil),
          ),
        ],
      ),
    );
  }

  Widget _avatar(PerfilUsuario? perfil) {
    final foto = perfil?.urlFoto;
    final tieneFoto = foto != null && foto.isNotEmpty;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (tieneFoto)
          Container(
            width: _tamanoAvatar,
            height: _tamanoAvatar,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: CircleAvatar(
              backgroundColor: RBColores.azul,
              backgroundImage: NetworkImage(foto),
            ),
          )
        else
          AvatarSuricata(tamano: _tamanoAvatar, borde: 6, sombra: true),
        if (perfil != null)
          Positioned(
            right: 2,
            bottom: 6,
            child: Material(
              color: RBColores.verde,
              shape: const CircleBorder(side: BorderSide(color: Colors.white, width: 3)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _mostrarMensaje('Cambiar la foto de perfil estará disponible pronto'),
                child: const Padding(
                  padding: EdgeInsets.all(11),
                  child: Icon(Icons.photo_camera_outlined, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _sinPerfil() {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: EstadoVacio(
        icono: _sinSesion ? Icons.person_outline_rounded : Icons.cloud_off_rounded,
        titulo: _sinSesion ? 'Aún no inicias sesión' : 'No se pudo cargar tu perfil',
        detalle: _error ?? '',
        accion: _sinSesion ? 'Crear cuenta / Iniciar sesión' : 'Reintentar',
        onAccion: _sinSesion
            ? () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const InicioSesionVista()),
                );
                if (mounted) _cargar();
              }
            : _cargar,
      ),
    );
  }

  Widget _contenido(PerfilUsuario p) {
    final zonas = _cantidadZonas;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                p.nombreCompleto.isEmpty ? p.email : p.nombreCompleto,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: RBFuentes.titulos,
                  fontSize: context.escala(32),
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  color: RBColores.azul,
                ),
              ),
            ),
            // El visto verde indica que la cuenta tiene el correo verificado.
            if (p.emailVerificado) ...[
              const SizedBox(width: 8),
              const Tooltip(
                message: 'Correo verificado',
                child: Icon(Icons.verified_rounded, color: RBColores.verde, size: 24),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.place_outlined, size: 20, color: RBColores.texto2),
            const SizedBox(width: 6),
            Text(p.lugar, style: const TextStyle(fontSize: 17, color: RBColores.texto2)),
          ],
        ),
        const SizedBox(height: 36),
        const Padding(
          padding: EdgeInsets.only(left: 8),
          child: EtiquetaSeccion('Cuenta'),
        ),
        const SizedBox(height: 12),
        TarjetaRB(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _opcion(
                Icons.person_outline_rounded,
                'Editar perfil',
                () => _mostrarMensaje('Editar perfil estará disponible pronto'),
              ),
              const Divider(height: 1),
              _opcion(
                Icons.lock_outline_rounded,
                'Privacidad y seguridad',
                () => _mostrarMensaje('Privacidad y seguridad estará disponible pronto'),
              ),
              const Divider(height: 1),
              _opcion(
                Icons.description_outlined,
                'Política de privacidad',
                () => _mostrarMensaje('La política de privacidad estará disponible pronto'),
              ),
              const Divider(height: 1),
              _opcion(
                Icons.verified_user_outlined,
                'Zonas seguras',
                _abrirZonas,
                verde: true,
                detalle: zonas == null
                    ? null
                    : '$zonas ${zonas == 1 ? 'ubicación' : 'ubicaciones'}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'RB Alertas · ${AppInfo.version}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: RBColores.texto2),
        ),
      ],
    );
  }

  Widget _opcion(
    IconData icono,
    String texto,
    VoidCallback alTocar, {
    bool verde = false,
    String? detalle,
  }) {
    return InkWell(
      onTap: alTocar,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: verde ? RBColores.verde50 : RBColores.azul50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icono, color: verde ? RBColores.verde : RBColores.azul, size: 24),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                texto,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: RBColores.tinta,
                ),
              ),
            ),
            if (detalle != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  detalle,
                  style: const TextStyle(fontSize: 15.5, color: RBColores.texto2),
                ),
              ),
            const Icon(Icons.chevron_right_rounded, color: RBColores.placeholder, size: 26),
          ],
        ),
      ),
    );
  }
}
