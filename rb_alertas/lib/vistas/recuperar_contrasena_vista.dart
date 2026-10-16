import 'package:flutter/material.dart';
import 'package:rb_alertas/servicios/auth_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/fondo_acceso.dart';

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
    return FondoAcceso(
      tamanoSuricata: 130,
      tarjeta: _mensajeEnviado == null
          ? _formulario()
          : _confirmacion(_mensajeEnviado!),
      pie: EnlaceAcceso(
        texto: '¿Recordaste tu contraseña?',
        enlace: 'Inicia sesión',
        onTap: () => Navigator.maybePop(context),
      ),
    );
  }

  Widget _titulo(String texto) {
    return Text(
      texto,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: RBFuentes.titulos,
        fontSize: context.escala(28),
        fontWeight: FontWeight.w800,
        color: RBColores.azul,
        height: 1.15,
      ),
    );
  }

  Widget _formulario() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titulo('Recupera tu contraseña'),
          const SizedBox(height: 10),
          const Text(
            'Escribe el correo de tu cuenta y te enviaremos un enlace para crear una contraseña nueva.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15.5, color: RBColores.texto2, height: 1.45),
          ),
          const SizedBox(height: 24),
          CampoRotulado(
            rotulo: 'Correo electrónico',
            campo: TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              validator: _validarEmail,
              onFieldSubmitted: (_) => _cargando ? null : _enviar(),
              decoration: const InputDecoration(
                hintText: 'tu@correo.com',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
            ),
          ),
          const SizedBox(height: 22),
          BotonPrincipal(
            texto: 'Enviar enlace',
            onPressed: _enviar,
            cargando: _cargando,
          ),
        ],
      ),
    );
  }

  Widget _confirmacion(String mensaje) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: RBColores.verde50,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.mark_email_read_outlined, color: RBColores.verde, size: 28),
          ),
        ),
        const SizedBox(height: 14),
        _titulo('Revisa tu correo'),
        const SizedBox(height: 12),
        Text(
          mensaje,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15.5, color: RBColores.tinta, height: 1.45),
        ),
        const SizedBox(height: 10),
        const Text(
          'El enlace dura 1 hora y sirve una sola vez. Si no lo ves en unos minutos, revisa la carpeta de spam.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: RBColores.texto2, height: 1.45),
        ),
        const SizedBox(height: 24),
        BotonPrincipal(
          texto: 'Volver a iniciar sesión',
          onPressed: () => Navigator.maybePop(context),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _cargando ? null : _enviar,
          child: const Text('Reenviar correo', style: TextStyle(fontSize: 15.5)),
        ),
      ],
    );
  }
}
