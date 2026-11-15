import 'package:rb_alertas/modelos/lectura_json.dart';
import 'package:rb_alertas/modelos/reporte.dart';
import 'package:rb_alertas/modelos/zona_segura.dart';
import 'package:rb_alertas/utilidades/formato.dart';

/// La zona que disparó la alerta. Puede faltar: si el usuario eliminó la zona,
/// la notificación sobrevive con `id_zona_segura` en null (ON DELETE SET NULL).
class ZonaDeAlerta {
  final int id;
  final String nombre;
  final TipoZona tipo;

  ZonaDeAlerta({required this.id, required this.nombre, required this.tipo});

  factory ZonaDeAlerta.desdeJson(Map<String, dynamic> json) => ZonaDeAlerta(
    id: json.entero('id_zona_segura'),
    nombre: json.texto('nombre'),
    tipo: TipoZona.desdeApi(json.textoOpcional('tipo')),
  );
}

/// Un incidente que cayó dentro de alguna zona segura del usuario, o que un
/// vecino compartió en uno de sus grupos.
class AlertaDeZona {
  final int id;
  final ReporteCercano reporte;
  final ZonaDeAlerta? zona;

  /// Nombre del grupo, solo en los avisos de grupo (motivo GRUPO).
  final String? grupo;
  final int? distanciaMetros;
  final DateTime? fechaEnvio;

  /// Cambia en memoria al abrir el detalle, sin recargar toda la lista.
  bool leida;

  AlertaDeZona({
    required this.id,
    required this.reporte,
    required this.zona,
    this.grupo,
    required this.distanciaMetros,
    required this.fechaEnvio,
    required this.leida,
  });

  /// "a 320 m de tu Casa", "En el grupo Villa Los Notros", o solo la
  /// distancia si la zona ya no existe.
  String get referencia {
    if (grupo != null) return 'En el grupo $grupo';
    final distancia = distanciaMetros == null ? null : distanciaLegible(distanciaMetros!);
    if (zona == null) {
      return distancia == null ? 'En una zona que eliminaste' : 'a $distancia de una zona eliminada';
    }
    return distancia == null ? 'En ${zona!.nombre}' : 'a $distancia de ${zona!.nombre}';
  }

  factory AlertaDeZona.desdeJson(Map<String, dynamic> json) {
    final zona = json['zona'];
    final grupo = json['grupo'];
    return AlertaDeZona(
      id: json.entero('id_notificacion'),
      reporte: ReporteCercano.desdeJson(json['reporte'] as Map<String, dynamic>),
      zona: zona is Map<String, dynamic> ? ZonaDeAlerta.desdeJson(zona) : null,
      grupo: grupo is Map ? grupo['nombre']?.toString() : null,
      distanciaMetros: json.enteroOpcional('distancia_metros'),
      fechaEnvio: json.fecha('fecha_envio'),
      leida: json.booleano('leida'),
    );
  }
}

/// Alertas de zona del usuario y cuántas quedan sin leer.
class AlertasDeZona {
  final int noLeidas;
  final List<AlertaDeZona> alertas;

  AlertasDeZona({required this.noLeidas, required this.alertas});

  factory AlertasDeZona.desdeJson(Map<String, dynamic> json) => AlertasDeZona(
    noLeidas: json.entero('no_leidas'),
    alertas: json.lista('notificaciones', AlertaDeZona.desdeJson),
  );
}
