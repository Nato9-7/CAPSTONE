import 'package:flutter/foundation.dart';

import 'package:rb_alertas/servicios/notificaciones_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';

class EstadoAlertas {
  static int? _ultimoIdVisto;
  static bool _hayCercanasNuevas = false;
  static int _zonasSinLeer = 0;

  /// true cuando hay algo sin revisar, por cualquiera de los dos motivos.
  static final ValueNotifier<bool> hayNuevas = ValueNotifier(false);

  /// Alertas de zona sin leer
  static int get zonasSinLeer => _zonasSinLeer;

  static void _recalcular() {
    hayNuevas.value = _hayCercanasNuevas || _zonasSinLeer > 0;
  }

  static void marcarVistos(Iterable<int> ids) {
    if (ids.isEmpty) return;
    final maxId = ids.reduce((a, b) => a > b ? a : b);
    if (_ultimoIdVisto == null || maxId > _ultimoIdVisto!) {
      _ultimoIdVisto = maxId;
    }
    _hayCercanasNuevas = false;
    _recalcular();
  }

  /// Se llama al cargar reportes en otras pantallas (por ejemplo el mapa)
  static void revisar(Iterable<int> ids) {
    if (ids.isEmpty) return;
    if (_ultimoIdVisto == null) {
      _ultimoIdVisto = ids.reduce((a, b) => a > b ? a : b);
      return;
    }
    if (ids.any((id) => id > _ultimoIdVisto!)) {
      _hayCercanasNuevas = true;
      _recalcular();
    }
  }

  /// Cantidad de alertas de zona sin leer.
  static void registrarZonasSinLeer(int cantidad) {
    _zonasSinLeer = cantidad < 0 ? 0 : cantidad;
    _recalcular();
  }

  /// Consulta al servidor cuántas alertas de zona quedan sin leer.
  static Future<void> refrescarZonasSinLeer() async {
    final token = Sesion.token;
    if (token == null || token.isEmpty) {
      registrarZonasSinLeer(0);
      return;
    }
    try {
      final datos = await NotificacionesServicio().listar(token, limite: 1);
      registrarZonasSinLeer(datos.noLeidas);
    } catch (_) {
      // se reintenta en la próxima carga del mapa
    }
  }

  /// Al cerrar sesión no debe quedar la insignia de otra cuenta.
  static void limpiar() {
    _ultimoIdVisto = null;
    _hayCercanasNuevas = false;
    _zonasSinLeer = 0;
    _recalcular();
  }
}
