import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rb_alertas/servicios/grupos_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/grupo_detalle_vista.dart';
import 'package:rb_alertas/vistas/grupo_formulario_vista.dart';
import 'package:rb_alertas/widgets/barra_navegacion_inferior.dart';
import 'package:rb_alertas/widgets/fondo_acceso.dart' show CampoRotulado;
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Pestaña Grupos: los grupos vecinales del usuario, crear uno o unirse con
/// el código que comparte el administrador.
class GruposVista extends StatefulWidget {
  const GruposVista({super.key});

  @override
  State<GruposVista> createState() => _GruposVistaState();
}

class _GruposVistaState extends State<GruposVista> {
  final _servicio = GruposServicio();
  MisGrupos? _datos;
  String? _error;
  bool _cargando = true;

  bool get _haySesion => (Sesion.token ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final token = Sesion.token;
    if (token == null || token.isEmpty) {
      setState(() => _cargando = false);
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final datos = await _servicio.listar(token);
      if (!mounted) return;
      setState(() {
        _datos = datos;
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

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _abrirGrupo(Grupo grupo) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GrupoDetalleVista(idGrupo: grupo.id, grupoInicial: grupo)),
    );
    // Al volver puede haber salido, eliminado o editado el grupo.
    if (mounted) _cargar();
  }

  Future<void> _crearGrupo() async {
    final datos = _datos;
    if (datos == null) return;
    // El botón nunca se oculta: si no puede crear, se explica el motivo.
    if (!datos.puedeCrear) {
      _mostrarMensaje(
        datos.administraUno
            ? 'Ya administras un grupo. Por ahora cada vecino puede crear uno.'
            : 'Ya estás en ${datos.maximo} grupos. Sal de uno para crear otro.',
      );
      return;
    }
    final grupo = await GrupoFormularioVista.abrir(
      context,
      radiosPermitidos: datos.radiosPermitidos,
    );
    if (grupo != null && mounted) _abrirGrupo(grupo);
  }

  Future<void> _unirse() async {
    final grupo = await _UnirseGrupoHoja.abrir(context);
    if (grupo != null && mounted) _abrirGrupo(grupo);
  }

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
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Align(alignment: Alignment.centerLeft, child: TituloPantalla('Grupos')),
    );
  }

  Widget _cuerpo() {
    if (!_haySesion) {
      return Column(
        children: [
          _encabezado(),
          const Expanded(
            child: EstadoVacio(
              icono: Icons.groups_outlined,
              titulo: 'Inicia sesión para usar los grupos',
              detalle: 'Con una cuenta puedes crear el grupo de tu junta de vecinos '
                  'o unirte con el código que te compartieron.',
            ),
          ),
        ],
      );
    }
    if (_cargando && _datos == null) {
      return Column(
        children: [
          _encabezado(),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }
    if (_error != null && _datos == null) {
      return Column(
        children: [
          _encabezado(),
          Expanded(
            child: EstadoVacio(
              icono: Icons.cloud_off_rounded,
              titulo: 'No se pudieron cargar tus grupos',
              detalle: _error!,
              accion: 'Reintentar',
              onAccion: _cargar,
            ),
          ),
        ],
      );
    }

    final datos = _datos!;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _encabezado(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Los reportes que tus vecinos compartan dentro del área del '
                  'grupo aparecen aquí, y te avisamos al instante.',
                  style: TextStyle(fontSize: 17, height: 1.45, color: RBColores.texto2),
                ),
                const SizedBox(height: 18),
                if (datos.grupos.isEmpty) ...[
                  _tarjetaBienvenida(),
                  const SizedBox(height: 22),
                ] else ...[
                  const EtiquetaSeccion('Mis grupos'),
                  const SizedBox(height: 12),
                  for (final grupo in datos.grupos) _filaGrupo(grupo),
                  const SizedBox(height: 10),
                ],
                _botonUnirse(),
                const SizedBox(height: 12),
                _botonCrear(datos.puedeCrear),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaBienvenida() {
    return const TarjetaSuricata(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Grupos vecinales',
            style: TextStyle(
              fontFamily: RBFuentes.titulos,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Únete con el código que te compartió tu junta de vecinos, o crea '
            'el grupo de tu pasaje, edificio o parcelación.',
            style: TextStyle(fontSize: 15, height: 1.4, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _filaGrupo(Grupo grupo) {
    final actividad = grupo.ultimoReporte == null
        ? 'Sin reportes todavía'
        : 'Último reporte ${tiempoRelativo(grupo.ultimoReporte)}';
    return TarjetaRB(
      onTap: () => _abrirGrupo(grupo),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
      child: Row(
        children: [
          Container(
            width: context.escala(56),
            height: context.escala(56),
            decoration: BoxDecoration(
              color: RBColores.azul50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.groups_rounded, color: RBColores.azul, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  grupo.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: RBColores.tinta,
                  ),
                ),
                Text(
                  '${grupo.miembrosTexto} · ${grupo.radioLegible}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15.5, color: RBColores.texto2),
                ),
                const SizedBox(height: 2),
                Text(
                  actividad,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: RBColores.texto2),
                ),
              ],
            ),
          ),
          if (grupo.esAdmin) ...[
            const SizedBox(width: 8),
            const ChipAdmin(),
          ],
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: RBColores.placeholder, size: 26),
        ],
      ),
    );
  }

  Widget _botonUnirse() {
    return SizedBox(
      height: 60,
      child: ElevatedButton.icon(
        onPressed: _unirse,
        style: ElevatedButton.styleFrom(
          backgroundColor: RBColores.verde,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RBRadios.tarjeta)),
        ),
        icon: const Icon(Icons.vpn_key_outlined),
        label: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('Unirme con un código', style: TextStyle(fontSize: 18)),
        ),
      ),
    );
  }

  Widget _botonCrear(bool puedeCrear) {
    final color = puedeCrear ? RBColores.azul : RBColores.texto2;
    return CustomPaint(
      painter: const BordePunteado(color: RBColores.placeholder, radio: RBRadios.tarjeta + 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(RBRadios.tarjeta + 4),
          onTap: _crearGrupo,
          child: SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, color: color, size: 28),
                const SizedBox(width: 10),
                Text(
                  'Crear grupo',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Píldora "Admin" junto al nombre del grupo o del vecino.
class ChipAdmin extends StatelessWidget {
  const ChipAdmin({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: RBColores.azul50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'Admin',
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: RBColores.azul),
      ),
    );
  }
}

/// Panel para escribir el código: primero muestra de qué grupo se trata y
/// después confirma el ingreso. Devuelve el grupo al que entró.
class _UnirseGrupoHoja extends StatefulWidget {
  const _UnirseGrupoHoja();

  static Future<Grupo?> abrir(BuildContext context) {
    return showModalBottomSheet<Grupo>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _UnirseGrupoHoja(),
    );
  }

  @override
  State<_UnirseGrupoHoja> createState() => _UnirseGrupoHojaState();
}

class _UnirseGrupoHojaState extends State<_UnirseGrupoHoja> {
  final _servicio = GruposServicio();
  final _codigoCtrl = TextEditingController();
  InvitacionGrupo? _invitacion;
  String? _error;
  bool _trabajando = false;

  @override
  void dispose() {
    _codigoCtrl.dispose();
    super.dispose();
  }

  Future<void> _revisar() async {
    final token = Sesion.token;
    final codigo = _codigoCtrl.text.trim();
    if (token == null || codigo.isEmpty) {
      setState(() => _error = 'Escribe el código que te compartieron');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _trabajando = true;
      _error = null;
    });
    try {
      final invitacion = await _servicio.verInvitacion(token: token, codigo: codigo);
      if (!mounted) return;
      setState(() => _invitacion = invitacion);
    } on GruposServicioException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo conectar con el servidor');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _unirse() async {
    final token = Sesion.token;
    if (token == null) return;
    setState(() {
      _trabajando = true;
      _error = null;
    });
    try {
      final grupo = await _servicio.unirse(token: token, codigo: _codigoCtrl.text);
      if (!mounted) return;
      Navigator.pop(context, grupo);
    } on GruposServicioException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo conectar con el servidor');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invitacion = _invitacion;
    return Padding(
      // Sube con el teclado para que el campo no quede tapado.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Unirme a un grupo',
              style: TextStyle(
                fontFamily: RBFuentes.titulos,
                fontSize: context.escala(26),
                fontWeight: FontWeight.w800,
                color: RBColores.azul,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Pídele el código al administrador del grupo. Vence a los 7 días.',
              style: TextStyle(fontSize: 15, height: 1.4, color: RBColores.texto2),
            ),
            const SizedBox(height: 18),
            CampoRotulado(
              rotulo: 'Código de invitación',
              campo: TextField(
                controller: _codigoCtrl,
                enabled: !_trabajando,
                maxLength: 20,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [UpperCaseTextFormatter()],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _revisar(),
                // Si cambia el código, la vista previa anterior ya no corresponde.
                onChanged: (_) {
                  if (_invitacion != null || _error != null) {
                    setState(() {
                      _invitacion = null;
                      _error = null;
                    });
                  }
                },
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  color: RBColores.tinta,
                ),
                decoration: const InputDecoration(
                  hintText: 'K7Q2MXAB',
                  counterText: '',
                  prefixIcon: Icon(Icons.vpn_key_outlined, color: RBColores.azul),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              AvisoRB(texto: _error!),
            ],
            if (invitacion != null) ...[
              const SizedBox(height: 16),
              _vistaPrevia(invitacion),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 58,
              child: ElevatedButton(
                onPressed: _trabajando
                    ? null
                    : (invitacion == null
                        ? _revisar
                        : (invitacion.yaEsMiembro ? null : _unirse)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: RBColores.verde,
                  disabledBackgroundColor: RBColores.verde.withValues(alpha: 0.6),
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(RBRadios.tarjeta),
                  ),
                ),
                child: _trabajando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    : Text(
                        invitacion == null
                            ? 'Buscar grupo'
                            : (invitacion.yaEsMiembro ? 'Ya eres parte de este grupo' : 'Unirme al grupo'),
                        style: const TextStyle(fontSize: 18),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vistaPrevia(InvitacionGrupo invitacion) {
    final descripcion = invitacion.descripcion?.trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RBColores.azul50,
        borderRadius: BorderRadius.circular(RBRadios.tarjeta),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: RBColores.azul,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.groups_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invitacion.nombre,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: RBColores.tinta,
                  ),
                ),
                if (descripcion != null && descripcion.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    descripcion,
                    style: const TextStyle(fontSize: 14.5, height: 1.35, color: RBColores.texto2),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  '${invitacion.totalMiembros == 1 ? '1 vecino' : '${invitacion.totalMiembros} vecinos'}'
                  ' · área de ${radioTexto(invitacion.radioMetros)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: RBColores.azul,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Deja el código en mayúsculas mientras se escribe, como se ve al compartirlo.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
