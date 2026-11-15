import 'package:rb_alertas/modelos/usuario.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/servicios/estado_alertas_servicio.dart';
import 'package:rb_alertas/servicios/push_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';

/// Perfil del usuario con sesión y cierre de sesión.
class PerfilServicio {
  Future<PerfilUsuario> obtenerPerfil() async {
    final cuerpo = await ApiCliente.get('/api/usuarios/perfil', error: 'No se pudo cargar tu perfil');
    return PerfilUsuario.desdeJson(cuerpo as Map<String, dynamic>);
  }

  /// Cierra la sesión en el servidor y en el teléfono. No falla si el token
  /// ya venció o no hay conexión: la sesión local se borra igual.
  Future<void> cerrarSesion() async {
    if (Sesion.activa) {
      // Primero el teléfono deja de recibir avisos: después el token ya no sirve.
      await PushServicio.darDeBaja();
      try {
        await ApiCliente.post('/api/usuarios/logout', error: '');
      } catch (_) {
        // la sesión se borra igual en la app
      }
    }
    await Sesion.cerrar();
    EstadoAlertas.limpiar();
  }
}
