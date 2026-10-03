import 'package:flutter/material.dart';
import 'package:rb_alertas/servicios/auth_servicio.dart';
import 'package:rb_alertas/widgets/app_logo.dart';

/// Pide el correo y la API envía un enlace para crear una contraseña nueva.
/// La contraseña se cambia en la página que abre ese enlace, no en la app.
class RecuperarContrasenaVista extends StatefulWidget {
  /// Correo ya escrito en el inicio de sesión, para no tener que repetirlo.
  final String emailInicial;

  const RecuperarContrasenaVista({super.key, this.emailInicial = ''});

  @override
  State<RecuperarContrasenaVista> createState() =>
      _RecuperarContrasenaVistaState();
}

class _RecuperarContrasenaVistaState extends State<RecuperarContrasenaVista> {
  static const _colorAzul = Color(0xFF0056D2);
  static const _colorFondoCampo = Color(0xFFF0F4FF);
  static const _colorBordeCampo = Color(0xFFD4E2FB);
  static const _colorTextoGris = Color(0xFF6B7280);

  final _formKey = GlobalKey<FormState>();
  late final _emailController = TextEditingController(text: widget.emailInicial);
  final _authServicio = AuthServicio();
  bool _cargando = false;
  // Mensaje de la API tras enviar el correo; mientras sea null se muestra el formulario.
  String? _mensajeEnviado;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String? _validarEmail(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'Ingresa tu correo electrónico';
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(valor.trim())) {
      return 'Ingresa un correo válido';
    }
    return null;
  }

  Future<void> _enviar() async {
    // Al reenviar desde la confirmación el formulario ya no está en pantalla.
    final reenvio = _mensajeEnviado != null;
    if (!reenvio && !_formKey.currentState!.validate()) return;

    setState(() => _cargando = true);
    try {
      final mensaje =
          await _authServicio.recuperarPassword(_emailController.text.trim());
      if (!mounted) return;
      setState(() => _mensajeEnviado = mensaje);
      if (reenvio) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Listo. Si pasó más de un minuto, te llegará un enlace nuevo.'),
          ),
        );
      }
    } on AuthServicioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.mensaje)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo conectar con el servidor')),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 36.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24.0),
                  border: Border.all(color: const Color(0xFFDCE4F2), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: _mensajeEnviado == null
                    ? _formulario()
                    : _confirmacion(_mensajeEnviado!),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _botonPrincipal({
    required String texto,
    required VoidCallback? onPressed,
    bool cargando = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _colorAzul,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: cargando
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(
                texto,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
      ),
    );
  }

  Widget _formulario() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppLogo(size: 88),
          const SizedBox(height: 22),
          const Text(
            'Recupera tu contraseña',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _colorAzul,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Escribe el correo de tu cuenta y te enviaremos un enlace para crear una contraseña nueva.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: _colorTextoGris, height: 1.4),
          ),
          const SizedBox(height: 28),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Correo Electrónico',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            validator: _validarEmail,
            onFieldSubmitted: (_) => _cargando ? null : _enviar(),
            decoration: InputDecoration(
              hintText: 'tu@correo.com',
              hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
              prefixIcon: const Icon(
                Icons.mail_outline_rounded,
                color: Color(0xFF6B7280),
                size: 20,
              ),
              filled: true,
              fillColor: _colorFondoCampo,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _colorBordeCampo, width: 1.2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _colorAzul, width: 1.8),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFB91C1C), width: 1.2),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFB91C1C), width: 1.8),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _botonPrincipal(
            texto: 'Enviar enlace',
            onPressed: _cargando ? null : _enviar,
            cargando: _cargando,
          ),
          const SizedBox(height: 18),
          TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text(
              'Volver a iniciar sesión',
              style: TextStyle(color: _colorAzul, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _confirmacion(String mensaje) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppLogo(size: 88),
        const SizedBox(height: 22),
        const Text(
          'Revisa tu correo',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: _colorAzul,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          mensaje,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Color(0xFF374151), height: 1.4),
        ),
        const SizedBox(height: 10),
        const Text(
          'El enlace dura 1 hora y sirve una sola vez. Si no lo ves en unos minutos, revisa la carpeta de spam.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: _colorTextoGris, height: 1.4),
        ),
        const SizedBox(height: 28),
        _botonPrincipal(
          texto: 'Volver a iniciar sesión',
          onPressed: () => Navigator.maybePop(context),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _cargando ? null : _enviar,
          child: const Text(
            'Reenviar correo',
            style: TextStyle(color: _colorAzul, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
