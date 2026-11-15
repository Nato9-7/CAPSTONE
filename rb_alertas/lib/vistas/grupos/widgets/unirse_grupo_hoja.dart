import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rb_alertas/modelos/grupo.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/servicios/grupos_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/widgets/fondo_acceso.dart' show CampoRotulado;
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Panel para escribir el código: primero muestra de qué grupo se trata y
/// después confirma el ingreso. Devuelve el grupo al que entró.
class UnirseGrupoHoja extends StatefulWidget {
  const UnirseGrupoHoja({super.key});

  static Future<Grupo?> abrir(BuildContext context) {
    return showModalBottomSheet<Grupo>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const UnirseGrupoHoja(),
    );
  }

  @override
  State<UnirseGrupoHoja> createState() => _UnirseGrupoHojaState();
}

class _UnirseGrupoHojaState extends State<UnirseGrupoHoja> {
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

  /// Ejecuta [accion] con el indicador de carga, mostrando su error en el panel.
  Future<void> _ejecutar(Future<void> Function() accion) async {
    setState(() {
      _trabajando = true;
      _error = null;
    });
    try {
      await accion();
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _revisar() async {
    final codigo = _codigoCtrl.text.trim();
    if (!Sesion.activa || codigo.isEmpty) {
      setState(() => _error = 'Escribe el código que te compartieron');
      return;
    }
    FocusScope.of(context).unfocus();
    await _ejecutar(() async {
      final invitacion = await _servicio.verInvitacion(codigo);
      if (mounted) setState(() => _invitacion = invitacion);
    });
  }

  Future<void> _unirse() async {
    if (!Sesion.activa) return;
    await _ejecutar(() async {
      final grupo = await _servicio.unirse(_codigoCtrl.text);
      if (mounted) Navigator.pop(context, grupo);
    });
  }

  /// Si cambia el código, la vista previa anterior ya no corresponde.
  void _alEditarCodigo(String _) {
    if (_invitacion == null && _error == null) return;
    setState(() {
      _invitacion = null;
      _error = null;
    });
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
                inputFormatters: [_FormatoMayusculas()],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _revisar(),
                onChanged: _alEditarCodigo,
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
              _VistaPreviaInvitacion(invitacion: invitacion),
            ],
            const SizedBox(height: 18),
            _botonPrincipal(invitacion),
          ],
        ),
      ),
    );
  }

  /// "Buscar grupo" hasta ver la invitación; después, "Unirme al grupo".
  Widget _botonPrincipal(InvitacionGrupo? invitacion) {
    final VoidCallback? accion;
    final String texto;
    if (invitacion == null) {
      accion = _revisar;
      texto = 'Buscar grupo';
    } else if (invitacion.yaEsMiembro) {
      accion = null;
      texto = 'Ya eres parte de este grupo';
    } else {
      accion = _unirse;
      texto = 'Unirme al grupo';
    }
    return SizedBox(
      height: 58,
      child: ElevatedButton(
        onPressed: _trabajando ? null : accion,
        style: ElevatedButton.styleFrom(
          backgroundColor: RBColores.verde,
          disabledBackgroundColor: RBColores.verde.withValues(alpha: 0.6),
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RBRadios.tarjeta)),
        ),
        child: _trabajando
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              )
            : Text(texto, style: const TextStyle(fontSize: 18)),
      ),
    );
  }
}

/// Datos del grupo antes de unirse: nombre, descripción, vecinos y área.
class _VistaPreviaInvitacion extends StatelessWidget {
  final InvitacionGrupo invitacion;

  const _VistaPreviaInvitacion({required this.invitacion});

  @override
  Widget build(BuildContext context) {
    final descripcion = invitacion.descripcion?.trim();
    final vecinos = invitacion.totalMiembros == 1 ? '1 vecino' : '${invitacion.totalMiembros} vecinos';
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
            decoration: BoxDecoration(color: RBColores.azul, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.groups_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invitacion.nombre,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: RBColores.tinta),
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
                  '$vecinos · área de ${textoRadio(invitacion.radioMetros)}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: RBColores.azul),
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
class _FormatoMayusculas extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
