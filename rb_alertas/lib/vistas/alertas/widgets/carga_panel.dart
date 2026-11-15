import 'package:flutter/material.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/vistas/cuenta/inicio_sesion_vista.dart';
import 'package:rb_alertas/vistas/detalle/detalle_incidente_vista.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Ciclo de carga común de los paneles de Alertas: indicador mientras carga,
/// aviso con "Reintentar" si falla e invitación a iniciar sesión si hace falta.
mixin CargaPanel<T extends StatefulWidget> on State<T> {
  bool cargando = true;
  String? error;
  bool sinSesion = false;

  /// Ejecuta [tarea] (que guarda sus datos con setState). Con [requiereSesion]
  /// y sin sesión abierta, no llama a la API y muestra la invitación.
  Future<void> ejecutarCarga(Future<void> Function() tarea, {bool requiereSesion = true}) async {
    if (requiereSesion && !Sesion.activa) {
      setState(() {
        cargando = false;
        sinSesion = true;
      });
      return;
    }
    setState(() {
      cargando = true;
      error = null;
      sinSesion = false;
    });
    try {
      await tarea();
      if (mounted) setState(() => cargando = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = mensajeDeError(e);
          cargando = false;
        });
      }
    }
  }

  /// Muestra el estado de carga, error o sin sesión; si no, [contenido].
  /// [recargar] es el reintento y lo que se ejecuta al volver del login.
  Widget construirPanel({
    required String tituloError,
    required Future<void> Function() recargar,
    required Widget Function() contenido,
    String detalleSinSesion = '',
  }) {
    if (sinSesion) {
      return EstadoVacio(
        icono: Icons.lock_outline_rounded,
        titulo: 'Inicia sesión',
        detalle: detalleSinSesion,
        accion: 'Iniciar sesión',
        onAccion: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const InicioSesionVista()));
          if (mounted) recargar();
        },
      );
    }
    if (cargando) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return EstadoVacio(
        icono: Icons.cloud_off_rounded,
        titulo: tituloError,
        detalle: error!,
        accion: 'Reintentar',
        onAccion: recargar,
      );
    }
    return contenido();
  }

  /// Abre el detalle de un reporte y recarga el panel si el reporte cambió
  /// (por ejemplo, se marcó como resuelto y dejó de estar vigente).
  Future<void> abrirDetalle(int idReporte, Future<void> Function() recargar) async {
    final cambio = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => DetalleIncidenteVista(idReporte: idReporte)),
    );
    if (cambio == true && mounted) recargar();
  }
}
