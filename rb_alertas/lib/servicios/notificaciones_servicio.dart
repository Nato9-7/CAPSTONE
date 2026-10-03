import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rb_alertas/config/api_config.dart';
import 'package:rb_alertas/servicios/reporte_servicio.dart' show ReporteCercano;
import 'package:rb_alertas/servicios/zonas_servicio.dart' show TipoZona;

class NotificacionesServicioException implements Exception {
  final String mensaje;
  NotificacionesServicioException(this.mensaje);
}

/// La zona que disparó la alerta. Puede faltar: si el usuario eliminó la zona,
/// la notificación sobrevive con `id_zona_segura` en null (ON DELETE SET NULL).
class ZonaDeAlerta {
  final int id;
  final String nombre;
  final TipoZona tipo;

  ZonaDeAlerta({required this.id, required this.nombre, required this.tipo});

  factory ZonaDeAlerta.desdeJson(Map<String, dynamic> json) {
    return ZonaDeAlerta(
      id: (json['id_zona_segura'] as num).toInt(),
      nombre: (json['nombre'] ?? '').toString(),
      tipo: TipoZona.desdeApi(json['tipo']?.toString()),
    );
  }
}

/// Un incidente que cayó dentro de alguna zona segura del usuario.
class AlertaDeZona {
  final int id;
  final ReporteCercano reporte;
  final ZonaDeAlerta? zona;
  final int? distanciaMetros;
  final DateTime? fechaEnvio;
  /// Cambia en memoria al abrir el detalle, sin recargar toda la lista.
  bool leida;

  AlertaDeZona({
    required this.id,
    required this.reporte,
    required this.zona,
    required this.distanciaMetros,
    required this.fechaEnvio,
    required this.leida,
  });

  /// "a 320 m de tu Casa", o solo la distancia si la zona ya no existe.
  String get referencia {
    final distancia = distanciaMetros == null
        ? null
        : (distanciaMetros! < 1000
            ? '${distanciaMetros!} m'
            : '${(distanciaMetros! / 1000).toStringAsFixed(1)} km');
    if (zona == null) {
      return distancia == null ? 'En una zona que eliminaste' : 'a $distancia de una zona eliminada';
    }
    return distancia == null
        ? 'En ${zona!.nombre}'
        : 'a $distancia de ${zona!.nombre}';
  }

  factory AlertaDeZona.desdeJson(Map<String, dynamic> json) {
    final zona = json['zona'];
    return AlertaDeZona(
      id: (json['id_notificacion'] as num).toInt(),
      reporte: ReporteCercano.desdeJson(
        json['reporte'] as Map<String, dynamic>,
      ),
      zona: zona == null
          ? null
          : ZonaDeAlerta.desdeJson(zona as Map<String, dynamic>),
      distanciaMetros: (json['distancia_metros'] as num?)?.toInt(),
      fechaEnvio: DateTime.tryParse((json['fecha_envio'] ?? '').toString()),
      leida: json['leida'] == true,
    );
  }
}

class AlertasDeZona {
  final int noLeidas;
  final List<AlertaDeZona> alertas;

  AlertasDeZona({required this.noLeidas, required this.alertas});

  factory AlertasDeZona.desdeJson(Map<String, dynamic> json) {
    return AlertasDeZona(
      noLeidas: (json['no_leidas'] as num?)?.toInt() ?? 0,
      alertas: [
        for (final n in (json['notificaciones'] as List? ?? []))
          AlertaDeZona.desdeJson(n as Map<String, dynamic>),
      ],
    );
  }
}

class NotificacionesServicio {
  static const String baseUrl = ApiConfig.baseUrl;
  static const String _ruta = '/api/usuarios/notificaciones';

  Future<AlertasDeZona> listar(String token, {int limite = 50}) async {
    final respuesta = await http.get(
      Uri.parse('$baseUrl$_ruta/').replace(
        queryParameters: {'limite': '$limite'},
      ),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (respuesta.statusCode == 200) {
      return AlertasDeZona.desdeJson(
        jsonDecode(utf8.decode(respuesta.bodyBytes)) as Map<String, dynamic>,
      );
    }
    throw NotificacionesServicioException(
      _mensaje(respuesta, 'No se pudieron cargar tus alertas'),
    );
  }

  /// Marca una alerta como leída. No lanza error: que falle el acuse no debe
  /// impedir que el usuario vea el detalle del incidente.
  Future<void> marcarLeida(String token, int idNotificacion) async {
    try {
      await http.post(
        Uri.parse('$baseUrl$_ruta/$idNotificacion/leida'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      // se reintenta solo en la próxima carga de la lista
    }
  }

  String _mensaje(http.Response respuesta, String porDefecto) {
    try {
      final cuerpo = jsonDecode(utf8.decode(respuesta.bodyBytes));
      final detalle = cuerpo is Map ? cuerpo['detail'] : null;
      if (detalle is String) return detalle;
    } catch (_) {
      // se usa el mensaje por defecto
    }
    return porDefecto;
  }
}
