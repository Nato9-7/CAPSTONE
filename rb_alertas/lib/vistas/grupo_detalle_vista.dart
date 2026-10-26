import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rb_alertas/config/app_info.dart';
import 'package:rb_alertas/servicios/grupos_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/detalle_incidente_vista.dart';
import 'package:rb_alertas/vistas/grupo_formulario_vista.dart';
import 'package:rb_alertas/vistas/grupos_vista.dart' show ChipAdmin;
import 'package:rb_alertas/widgets/barra_navegacion_inferior.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';
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
  bool _trabajando = false;

  @override
  void initState() {
    super.initState();
    _grupo = widget.grupoInicial;
    _cargar();
  }

  Future<void> _cargar() async {
    final token = Sesion.token;
    if (token == null || token.isEmpty) {
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
        _servicio.detalle(token: token, idGrupo: widget.idGrupo),
        _servicio.reportes(token: token, idGrupo: widget.idGrupo),
      ]);
      if (!mounted) return;
      final reportes = resultados[1] as List<ReporteGrupo>;
      setState(() {
        _grupo = resultados[0] as Grupo;
        _reportes = reportes;
        _hayMas = reportes.length >= GruposServicio.reportesPorPagina;
        _cargando = false;
      });
    } on GruposServicioException catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e.mensaje;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo conectar con el servidor';
      });
    }
  }

  Future<void> _cargarMas() async {
    final token = Sesion.token;
    if (token == null || _reportes.isEmpty || _cargandoMas) return;
    setState(() => _cargandoMas = true);
    try {
      final siguientes = await _servicio.reportes(
        token: token,
        idGrupo: widget.idGrupo,
        antesDe: _reportes.last.id,
      );
      if (!mounted) return;
      setState(() {
        _reportes = [..._reportes, ...siguientes];
        _hayMas = siguientes.length >= GruposServicio.reportesPorPagina;
      });
    } on GruposServicioException catch (e) {
      _mostrarMensaje(e.mensaje);
    } catch (_) {
      _mostrarMensaje('No se pudo conectar con el servidor');
    } finally {
      if (mounted) setState(() => _cargandoMas = false);
    }
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _abrirReporte(ReporteGrupo reporte) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetalleIncidenteVista(idReporte: reporte.id)),
    );
    // Al volver pueden haber cambiado el estado o los comentarios.
    if (mounted) _cargar();
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
    _mostrarMensaje('Copiado: pégalo donde quieras compartirlo');
  }

  Future<void> _copiarCodigo(Grupo grupo) async {
    await Clipboard.setData(ClipboardData(text: grupo.codigo ?? ''));
    _mostrarMensaje('Código copiado');
  }

  Future<void> _regenerarCodigo(Grupo grupo) async {
    final token = Sesion.token;
    if (token == null) return;
    final confirmado = await _confirmar(
      titulo: 'Generar un código nuevo',
      mensaje: 'El código actual dejará de funcionar. Quienes ya están en el '
          'grupo siguen dentro.',
      accion: 'Generar',
    );
    if (confirmado != true) return;
    setState(() => _trabajando = true);
    try {
      final actualizado = await _servicio.regenerarCodigo(token: token, idGrupo: grupo.id);
      if (!mounted) return;
      setState(() => _grupo = actualizado);
      _mostrarMensaje('Nuevo código listo para compartir');
    } on GruposServicioException catch (e) {
      _mostrarMensaje(e.mensaje);
    } catch (_) {
      _mostrarMensaje('No se pudo conectar con el servidor');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Menú del grupo

  Future<bool?> _confirmar({
    required String titulo,
    required String mensaje,
    required String accion,
    bool peligrosa = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (contextoDialogo) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contextoDialogo, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(contextoDialogo, true),
            style: peligrosa ? TextButton.styleFrom(foregroundColor: RBColores.rojo) : null,
            child: Text(accion),
          ),
        ],
      ),
    );
  }

  Future<void> _elegirAccion(_AccionGrupo accion) async {
    final grupo = _grupo;
    final token = Sesion.token;
    if (grupo == null || token == null) return;
    switch (accion) {
      case _AccionGrupo.vecinos:
        final cambio = await _VecinosHoja.abrir(context, grupo: grupo);
        if (cambio == true && mounted) _cargar();
      case _AccionGrupo.editar:
        final actualizado = await GrupoFormularioVista.abrir(
          context,
          grupo: grupo,
          radiosPermitidos: const [500, 1000, 2000],
        );
        if (actualizado != null && mounted) setState(() => _grupo = actualizado);
      case _AccionGrupo.eliminar:
        final confirmado = await _confirmar(
          titulo: 'Eliminar grupo',
          mensaje: '¿Eliminar «${grupo.nombre}»? Los vecinos ya no podrán ver '
              'los reportes que se compartieron solo en el grupo.',
          accion: 'Eliminar',
          peligrosa: true,
        );
        if (confirmado == true) {
          await _salirOEliminar(() => _servicio.eliminar(token: token, idGrupo: grupo.id));
        }
      case _AccionGrupo.salir:
        final confirmado = await _confirmar(
          titulo: 'Salir del grupo',
          mensaje: '¿Salir de «${grupo.nombre}»? Para volver necesitarás un código nuevo.',
          accion: 'Salir',
          peligrosa: true,
        );
        if (confirmado == true) {
          await _salirOEliminar(() => _servicio.salir(token: token, idGrupo: grupo.id));
        }
    }
  }

  Future<void> _salirOEliminar(Future<void> Function() operacion) async {
    setState(() => _trabajando = true);
    try {
      await operacion();
      if (!mounted) return;
      Navigator.pop(context);
    } on GruposServicioException catch (e) {
      _mostrarMensaje(e.mensaje);
    } catch (_) {
      _mostrarMensaje('No se pudo conectar con el servidor');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Interfaz

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RBColores.fondo,
      body: SafeArea(bottom: false, child: _cuerpo()),
      bottomNavigationBar: const BarraNavegacionInferior(
        seccionActiva: SeccionApp.grupos,
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
          if (grupo != null)
            PopupMenuButton<_AccionGrupo>(
              tooltip: 'Opciones del grupo',
              enabled: !_trabajando,
              icon: const Icon(Icons.more_vert_rounded, size: 28, color: RBColores.tinta),
              onSelected: _elegirAccion,
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: _AccionGrupo.vecinos,
                  child: ListTile(
                    leading: Icon(Icons.people_outline_rounded),
                    title: Text('Ver vecinos'),
                  ),
                ),
                if (grupo.esAdmin) ...[
                  const PopupMenuItem(
                    value: _AccionGrupo.editar,
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Editar grupo'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _AccionGrupo.eliminar,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline_rounded, color: RBColores.rojo),
                      title: Text('Eliminar grupo', style: TextStyle(color: RBColores.rojo)),
                    ),
                  ),
                ] else
                  const PopupMenuItem(
                    value: _AccionGrupo.salir,
                    child: ListTile(
                      leading: Icon(Icons.logout_rounded, color: RBColores.rojo),
                      title: Text('Salir del grupo', style: TextStyle(color: RBColores.rojo)),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando && _grupo == null) {
      return Column(
        children: [
          _encabezado(),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }
    if (_error != null && _reportes.isEmpty) {
      return Column(
        children: [
          _encabezado(),
          Expanded(
            child: EstadoVacio(
              icono: Icons.cloud_off_rounded,
              titulo: 'No se pudo cargar el grupo',
              detalle: _error!,
              accion: 'Reintentar',
              onAccion: _cargar,
            ),
          ),
        ],
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
                  _tarjetaCodigo(grupo),
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
                  _TarjetaReporteGrupo(reporte: reporte, onTap: () => _abrirReporte(reporte)),
                if (_hayMas)
                  Center(
                    child: _cargandoMas
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(),
                          )
                        : TextButton(
                            onPressed: _cargarMas,
                            child: const Text('Ver reportes anteriores'),
                          ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaCodigo(Grupo grupo) {
    final expira = grupo.codigoExpira;
    final String vigencia;
    if (grupo.codigoVencido || expira == null) {
      vigencia = 'Venció: genera uno nuevo para invitar';
    } else {
      final dias = expira.difference(DateTime.now()).inDays;
      vigencia = dias < 1 ? 'Vence hoy' : (dias == 1 ? 'Vence mañana' : 'Vence en $dias días');
    }
    return TarjetaRB(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('CÓDIGO DE INVITACIÓN', style: RBTexto.etiqueta),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    grupo.codigo!,
                    style: TextStyle(
                      fontFamily: RBFuentes.titulos,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                      color: grupo.codigoVencido ? RBColores.texto2 : RBColores.azul,
                      decoration: grupo.codigoVencido ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              ),
              if (!grupo.codigoVencido)
                IconButton(
                  tooltip: 'Copiar código',
                  onPressed: () => _copiarCodigo(grupo),
                  icon: const Icon(Icons.copy_rounded, color: RBColores.azul),
                ),
            ],
          ),
          Text(
            vigencia,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: grupo.codigoVencido ? RBColores.rojo : RBColores.texto2,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: grupo.codigoVencido || _trabajando ? null : () => _compartirCodigo(grupo),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: RBColores.verde,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(RBRadios.boton),
                      ),
                    ),
                    icon: const Icon(Icons.share_rounded, size: 20),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Invitar vecinos', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _trabajando ? null : () => _regenerarCodigo(grupo),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: RBColores.azul,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(RBRadios.boton),
                      ),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Código nuevo', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Un reporte en el chat del grupo: quién lo compartió y cuándo, arriba, y la
/// tarjeta del incidente debajo, como un mensaje.
class _TarjetaReporteGrupo extends StatelessWidget {
  final ReporteGrupo reporte;
  final VoidCallback onTap;

  const _TarjetaReporteGrupo({required this.reporte, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final comentarios = reporte.totalComentarios == 1
        ? '1 comentario'
        : '${reporte.totalComentarios} comentarios';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Row(
              children: [
                const AvatarSuricata(tamano: 26),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    reporte.esMio ? 'Tú' : reporte.autor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: RBColores.tinta,
                    ),
                  ),
                ),
                Text(
                  ' · ${tiempoRelativo(reporte.fecha)}',
                  style: const TextStyle(fontSize: 14, color: RBColores.texto2),
                ),
              ],
            ),
          ),
          TarjetaRB(
            onTap: onTap,
            padding: const EdgeInsets.fromLTRB(16, 16, 14, 14),
            colorBorde: reporte.esMio ? RBColores.verde50 : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconoCategoria(
                  codigo: reporte.categoriaCodigo,
                  colorHex: reporte.colorHex,
                  tamano: context.escala(52),
                ),
                SizedBox(width: context.pantallaAngosta ? 12 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tituloReporte(reporte.categoria, reporte.direccion),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16.5,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                          color: RBColores.tinta,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        reporte.descripcion,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14.5, height: 1.35, color: RBColores.texto2),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ChipEstado(estado: EstadoVisual.desdeApi(reporte.estado)),
                          if (reporte.soloGrupo) const ChipSoloGrupo(),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.chat_bubble_outline_rounded, size: 16, color: RBColores.texto2),
                              const SizedBox(width: 4),
                              Text(
                                comentarios,
                                style: const TextStyle(fontSize: 14, color: RBColores.texto2),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: RBColores.placeholder, size: 26),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lista de vecinos del grupo, con su alias. El admin puede quitar a alguien.
/// Devuelve true si se quitó a alguien, para refrescar el contador.
class _VecinosHoja extends StatefulWidget {
  final Grupo grupo;

  const _VecinosHoja({required this.grupo});

  static Future<bool?> abrir(BuildContext context, {required Grupo grupo}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _VecinosHoja(grupo: grupo),
    );
  }

  @override
  State<_VecinosHoja> createState() => _VecinosHojaState();
}

class _VecinosHojaState extends State<_VecinosHoja> {
  final _servicio = GruposServicio();
  List<MiembroGrupo>? _miembros;
  String? _error;
  bool _huboCambios = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final token = Sesion.token;
    if (token == null) return;
    try {
      final miembros = await _servicio.miembros(token: token, idGrupo: widget.grupo.id);
      if (mounted) setState(() => _miembros = miembros);
    } on GruposServicioException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo conectar con el servidor');
    }
  }

  Future<void> _expulsar(MiembroGrupo miembro) async {
    final token = Sesion.token;
    if (token == null) return;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contextoDialogo) => AlertDialog(
        title: const Text('Quitar del grupo'),
        content: Text(
          '¿Quitar a ${miembro.alias}? Dejará de ver los reportes del grupo. '
          'Para que no vuelva a entrar, genera un código nuevo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contextoDialogo, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(contextoDialogo, true),
            style: TextButton.styleFrom(foregroundColor: RBColores.rojo),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    try {
      await _servicio.expulsar(token: token, idGrupo: widget.grupo.id, idMiembro: miembro.id);
      if (!mounted) return;
      setState(() {
        _miembros = _miembros?.where((m) => m.id != miembro.id).toList();
        _huboCambios = true;
      });
    } on GruposServicioException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo conectar con el servidor');
    }
  }

  @override
  Widget build(BuildContext context) {
    final miembros = _miembros;
    return PopScope(
      canPop: false,
      // Se cierra devolviendo si hubo cambios, también con el gesto de volver.
      onPopInvokedWithResult: (yaCerro, _) {
        if (!yaCerro) Navigator.pop(context, _huboCambios);
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Vecinos del grupo',
                style: TextStyle(
                  fontFamily: RBFuentes.titulos,
                  fontSize: context.escala(26),
                  fontWeight: FontWeight.w800,
                  color: RBColores.azul,
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: AvisoRB(texto: _error!),
              ),
            if (miembros == null && _error == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (miembros != null)
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
                  itemCount: miembros.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, color: RBColores.linea),
                  itemBuilder: (_, indice) => _filaMiembro(miembros[indice]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filaMiembro(MiembroGrupo miembro) {
    final puedeQuitar = widget.grupo.esAdmin && !miembro.esAdmin;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const AvatarSuricata(tamano: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  miembro.soyYo ? '${miembro.alias} (tú)' : miembro.alias,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: RBColores.tinta,
                  ),
                ),
                if (miembro.fechaUnion != null)
                  Text(
                    'Se unió ${tiempoRelativo(miembro.fechaUnion)}',
                    style: const TextStyle(fontSize: 14, color: RBColores.texto2),
                  ),
              ],
            ),
          ),
          if (miembro.esAdmin) const ChipAdmin(),
          if (puedeQuitar)
            IconButton(
              tooltip: 'Quitar del grupo',
              onPressed: () => _expulsar(miembro),
              icon: const Icon(Icons.person_remove_outlined, color: RBColores.rojo),
            ),
        ],
      ),
    );
  }
}
