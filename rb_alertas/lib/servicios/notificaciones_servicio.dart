import 'package:rb_alertas/modelos/notificacion.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';

/// Alertas de zona segura y de grupo del usuario con sesión.
class NotificacionesServicio {
  static const String _ruta = '/api/usuarios/notificaciones';

  Future<AlertasDeZona> listar({int limite = 50}) async {
    final cuerpo = await ApiCliente.get(
      '$_ruta/',
      consulta: {'limite': '$limite'},
      error: 'No se pudieron cargar tus alertas',
    );
    return AlertasDeZona.desdeJson(cuerpo as Map<String, dynamic>);
  }

  /// Marca una alerta como leída. No lanza error: que falle el acuse no debe
  /// impedir que el usuario vea el detalle del incidente.
  Future<void> marcarLeida(int idNotificacion) async {
    try {
      await ApiCliente.post('$_ruta/$idNotificacion/leida', error: '');
    } catch (_) {
      // se reintenta solo en la próxima carga de la lista
    }
  }
}
