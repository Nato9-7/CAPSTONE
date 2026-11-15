import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rb_alertas/config/app_info.dart';
import 'package:rb_alertas/modelos/grupo.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/servicios/grupos_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/detalle/detalle_incidente_vista.dart';
import 'package:rb_alertas/vistas/grupos/grupo_formulario_vista.dart';
import 'package:rb_alertas/vistas/grupos/widgets/tarjeta_codigo.dart';
import 'package:rb_alertas/vistas/grupos/widgets/tarjeta_reporte_grupo.dart';
import 'package:rb_alertas/vistas/grupos/widgets/vecinos_hoja.dart';
import 'package:rb_alertas/widgets/barra_navegacion_inferior.dart';
import 'package:rb_alertas/widgets/dialogos.dart';
import 'package:rb_alertas/widgets/editor_area.dart' show radiosPorDefecto;
import 'package:rb_alertas/widgets/rb_componentes.dart';
import 'package:share_plus/share_plus.dart';

enum _AccionGrupo { vecinos, editar, eliminar, salir }

/// El "chat" de un grupo: los reportes que los vecinos compartieron en él.
/// Al tocar uno se abre el reporte, donde se comenta como en cualquier otro.
class GrupoDetalleVista extends StatefulWidget {
  final int idGrupo;

  /// Lo que ya se sabe del grupo (desde la lista), para dibujar el
  /// encabezado mientras carga el resto.
  final Grupo? grupoInicial;

  const GrupoDetalleVista({super.key, required this.idGrupo, this.grupoInicial});

  @override
  State<GrupoDetalleVista> createState() => _GrupoDetalleVistaState();
}

class _GrupoDetalleVistaState extends State<GrupoDetalleVista> {
  final _servicio = GruposServicio();
  Grupo? _grupo;
  List<ReporteGrupo> _reportes = [];
  String? _error;
  bool _cargando = true;
  bool _cargandoMas = false;
  bool _hayMas = false;

  /// Hay una operación sobre el grupo en curso (código, salir, eliminar).
  bool _trabajando = false;

  @override
  void initState() {
    super.initState();
    _grupo = widget.grupoInicial;
    _cargar();
  }

  Future<void> _cargar() async {
    if (!Sesion.activa) {
      setState(() {
        _cargando = false;
        _error = 'Inicia sesión para ver tus grupos';
      });
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resultados = await Future.wait([
        _servicio.detalle(widget.idGrupo),
        _servicio.reportes(idGrupo: widget.idGrupo),
      ]);
      if (!mounted) return;
      final reportes = resultados[1] as List<ReporteGrupo>;
      setState(() {
        _grupo = resultados[0] as Grupo;
        _reportes = reportes;
        _hayMas = reportes.length >= GruposServicio.reportesPorPagina;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = mensajeDeError(e);
      });
    }
  }

  /// Trae la página siguiente de reportes (los más antiguos).
  Future<void> _cargarMas() async {
    if (!Sesion.activa || _reportes.isEmpty || _cargandoMas) return;
    setState(() => _cargandoMas = true);
    try {
      final siguientes = await _servicio.reportes(idGrupo: widget.idGrupo, antesDe: _reportes.last.id);
      if (!mounted) return;
      setState(() {
        _reportes = [..._reportes, ...siguientes];
        _hayMas = siguientes.length >= GruposServicio.reportesPorPagina;
      });
    } catch (e) {
      if (mounted) mostrarAviso(context, mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargandoMas = false);
    }
  }

  Future<void> _abrirReporte(ReporteGrupo reporte) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetalleIncidenteVista(idReporte: reporte.id)),
    );
    // Al volver pueden haber cambiado el estado o los comentarios.
    if (mounted) _cargar();
  }

  /// Ejecuta [operacion] con los botones del grupo deshabilitados y avisa si falla.
  Future<void> _trabajar(Future<void> Function() operacion) async {
    setState(() => _trabajando = true);
    try {
      await operacion();
    } catch (e) {
      if (mounted) mostrarAviso(context, mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Código de invitación

  String _textoInvitacion(Grupo grupo) {
    final descarga = AppInfo.urlDescarga.isEmpty
        ? ''
        : '\nSi no tienes la app, descárgala aquí: ${AppInfo.urlDescarga}';
    return 'Únete al grupo «${grupo.nombre}» en RB Alertas con el código '
        '${grupo.codigo}.\nEn la app: Grupos → Unirme con un código.$descarga';
  }

  Future<void> _compartirCodigo(Grupo grupo) async {
    final texto = _textoInvitacion(grupo);
    // Igual que al compartir un reporte: en web, o si falla, se copia el texto.
    if (!kIsWeb) {
      try {
        await SharePlus.instance.share(ShareParams(text: texto, subject: grupo.nombre));
        return;
      } catch (_) {
        // si falla, se copia al portapapeles
      }
    }
    await Clipboard.setData(ClipboardData(text: texto));
    if (mounted) mostrarAviso(context, 'Copiado: pégalo donde quieras compartirlo');
  }

  Future<void> _copiarCodigo(Grupo grupo) async {
    await Clipboard.setData(ClipboardData(text: grupo.codigo ?? ''));
    if (mounted) mostrarAviso(context, 'Código copiado');
  }

  Future<void> _regenerarCodigo(Grupo grupo) async {
    if (!Sesion.activa) return;
    final confirmado = await confirmar(
      context,
      titulo: 'Generar un código nuevo',
      mensaje: 'El código actual dejará de funcionar. Quienes ya están en el '
          'grupo siguen dentro.',
      accion: 'Generar',
      peligro: false,
    );
    if (!confirmado || !mounted) return;
    await _trabajar(() async {
      final actualizado = await _servicio.regenerarCodigo(grupo.id);
      if (!mounted) return;
      setState(() => _grupo = actualizado);
      mostrarAviso(context, 'Nuevo código listo para compartir');
    });
  }

  // ---------------------------------------------------------------------------
  // Menú del grupo

  Future<void> _elegirAccion(_AccionGrupo accion) async {
    final grupo = _grupo;
    if (grupo == null || !Sesion.activa) return;
    switch (accion) {
      case _AccionGrupo.vecinos:
        final cambio = await VecinosHoja.abrir(context, grupo: grupo);
        if (cambio == true && mounted) _cargar();
      case _AccionGrupo.editar:
        final actualizado = await GrupoFormularioVista.abrir(
          context,
          grupo: grupo,
          radiosPermitidos: radiosPorDefecto,
        );
        if (actualizado != null && mounted) setState(() => _grupo = actualizado);
      case _AccionGrupo.eliminar:
        final confirmado = await confirmar(
          context,
          titulo: 'Eliminar grupo',
          mensaje: '¿Eliminar «${grupo.nombre}»? Los vecinos ya no podrán ver '
              'los reportes que se compartieron solo en el grupo.',
          accion: 'Eliminar',
        );
        if (confirmado) await _salirDelGrupo(() => _servicio.eliminar(grupo.id));
      case _AccionGrupo.salir:
        final confirmado = await confirmar(
          context,
          titulo: 'Salir del grupo',
          mensaje: '¿Salir de «${grupo.nombre}»? Para volver necesitarás un código nuevo.',
          accion: 'Salir',
        );
        if (confirmado) await _salirDelGrupo(() => _servicio.salir(grupo.id));
    }
  }

  /// Sale o elimina el grupo y vuelve a la lista.
  Future<void> _salirDelGrupo(Future<void> Function() operacion) async {
    if (!mounted) return;
    await _trabajar(() async {
      await operacion();
      if (mounted) Navigator.pop(context);
    });
  }

  // ---------------------------------------------------------------------------
  // Interfaz

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RBColores.fondo,
      body: SafeArea(bottom: false, child: _cuerpo()),
      bottomNavigationBar: const BarraNavegacionInferior(seccionActiva: SeccionApp.grupos),
    );
  }

  /// Encabezado arriba y [contenido] ocupando el resto (carga o error).
  Widget _conEncabezado(Widget contenido) =>
      Column(children: [_encabezado(), Expanded(child: contenido)]);

  Widget _cuerpo() {
    if (_cargando && _grupo == null) {
      return _conEncabezado(const Center(child: CircularProgressIndicator()));
    }
    if (_error != null && _reportes.isEmpty) {
      return _conEncabezado(
        EstadoVacio(
          icono: Icons.cloud_off_rounded,
          titulo: 'No se pudo cargar el grupo',
          detalle: _error!,
          accion: 'Reintentar',
          onAccion: _cargar,
        ),
      );
    }

    final grupo = _grupo!;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _encabezado(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (grupo.esAdmin && grupo.codigo != null) ...[
                  TarjetaCodigo(
                    grupo: grupo,
                    trabajando: _trabajando,
                    onCopiar: () => _copiarCodigo(grupo),
                    onCompartir: () => _compartirCodigo(grupo),
                    onRegenerar: () => _regenerarCodigo(grupo),
                  ),
                  const SizedBox(height: 24),
                ],
                const EtiquetaSeccion('Reportes del grupo'),
                const SizedBox(height: 12),
                if (_reportes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: EstadoVacio(
                      icono: Icons.forum_outlined,
                      titulo: 'Aún no hay reportes',
                      detalle: 'Cuando un vecino reporte algo dentro del área y '
                          'lo comparta con el grupo, aparecerá aquí.',
                    ),
                  ),
                for (final reporte in _reportes)
                  TarjetaReporteGrupo(reporte: reporte, onTap: () => _abrirReporte(reporte)),
                if (_hayMas)
                  Center(
                    child: _cargandoMas
                        ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())
                        : TextButton(onPressed: _cargarMas, child: const Text('Ver reportes anteriores')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _encabezado() {
    final grupo = _grupo;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Volver',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded, size: 30, color: RBColores.tinta),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Los nombres de junta de vecinos suelen ser largos: dos líneas
                // a tamaño legible en vez de achicar el texto hasta que quepa.
                Text(
                  grupo?.nombre ?? 'Grupo',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: RBFuentes.titulos,
                    fontSize: context.escala(26),
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: RBColores.azul,
                  ),
                ),
                if (grupo != null)
                  Text(
                    '${grupo.miembrosTexto} · área de ${grupo.radioLegible}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, color: RBColores.texto2),
                  ),
              ],
            ),
          ),
          if (grupo != null) _menu(grupo),
        ],
      ),
    );
  }

  /// Ver vecinos para todos; editar y eliminar para el admin; salir para el resto.
  Widget _menu(Grupo grupo) {
    PopupMenuItem<_AccionGrupo> opcion(_AccionGrupo valor, IconData icono, String texto, {bool peligro = false}) {
      final color = peligro ? RBColores.rojo : null;
      return PopupMenuItem(
        value: valor,
        child: ListTile(
          leading: Icon(icono, color: color),
          title: Text(texto, style: peligro ? const TextStyle(color: RBColores.rojo) : null),
        ),
      );
    }

    return PopupMenuButton<_AccionGrupo>(
      tooltip: 'Opciones del grupo',
      enabled: !_trabajando,
      icon: const Icon(Icons.more_vert_rounded, size: 28, color: RBColores.tinta),
      onSelected: _elegirAccion,
      itemBuilder: (_) => [
        opcion(_AccionGrupo.vecinos, Icons.people_outline_rounded, 'Ver vecinos'),
        if (grupo.esAdmin) ...[
          opcion(_AccionGrupo.editar, Icons.edit_outlined, 'Editar grupo'),
          opcion(_AccionGrupo.eliminar, Icons.delete_outline_rounded, 'Eliminar grupo', peligro: true),
        ] else
          opcion(_AccionGrupo.salir, Icons.logout_rounded, 'Salir del grupo', peligro: true),
      ],
    );
  }
}
