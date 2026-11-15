import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/servicios/auth_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/validaciones.dart';
import 'package:rb_alertas/widgets/dialogos.dart';
import 'package:rb_alertas/widgets/fondo_acceso.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

class RegistroVista extends StatefulWidget {
  const RegistroVista({super.key});

  @override
  State<RegistroVista> createState() => _RegistroVistaState();
}

class _RegistroVistaState extends State<RegistroVista> {
  final _formKey = GlobalKey<FormState>();
  final _nombresController = TextEditingController();
  final _apellidosController = TextEditingController();
  final _rutController = TextEditingController();
  final _emailController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authServicio = AuthServicio();
  bool _obscurePassword = true;
  bool _cargando = false;

  @override
  void dispose() {
    _nombresController.dispose();
    _apellidosController.dispose();
    _rutController.dispose();
    _emailController.dispose();
    _telefonoController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// El prefijo +56 9 va fijo en el campo: se escriben los 8 dígitos restantes.
  static const _prefijoTelefono = '+569';

  Future<void> _registrar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _cargando = true);
    final email = _emailController.text.trim();

    try {
      await _authServicio.registrar(
        nombres: _nombresController.text.trim(),
        apellidos: _apellidosController.text.trim(),
        rut: rutSinPuntos(_rutController.text),
        email: email,
        telefono: '$_prefijoTelefono${_telefonoController.text.replaceAll(' ', '')}',
        password: _passwordController.text,
      );

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Revisa tu correo'),
          content: Text(
            'Te enviamos un enlace a $email para activar tu cuenta. '
            'Ábrelo y después inicia sesión.\n\n'
            'Si no lo ves en unos minutos, revisa la carpeta de spam.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.maybePop(context);
    } catch (e) {
      if (mounted) mostrarAviso(context, mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FondoAcceso(
      tamanoSuricata: 120,
      tarjeta: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MarcaRB(tamano: context.escala(40)),
            const SizedBox(height: 8),
            const Text(
              'Crea tu cuenta',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: RBColores.tinta,
              ),
            ),
            const SizedBox(height: 18),
            // Lado a lado si hay espacio; en celulares angostos, uno bajo el otro.
            LayoutBuilder(
              builder: (context, limites) {
                final nombres = CampoRotulado(
                  rotulo: 'Nombres',
                  campo: _campo(
                    controller: _nombresController,
                    hintText: 'Nombres',
                    icon: Icons.person_outline_rounded,
                    keyboardType: TextInputType.name,
                    validator: (valor) => validarRequerido(valor, 'nombres'),
                  ),
                );
                final apellidos = CampoRotulado(
                  rotulo: 'Apellidos',
                  campo: _campo(
                    controller: _apellidosController,
                    hintText: 'Apellidos',
                    icon: Icons.person_outline_rounded,
                    keyboardType: TextInputType.name,
                    validator: (valor) => validarRequerido(valor, 'apellidos'),
                  ),
                );
                if (limites.maxWidth < 320) {
                  return Column(children: [nombres, const SizedBox(height: 14), apellidos]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: nombres),
                    const SizedBox(width: 12),
                    Expanded(child: apellidos),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            CampoRotulado(
              rotulo: 'RUT',
              campo: _campo(
                controller: _rutController,
                hintText: '12.345.678-9',
                icon: Icons.badge_outlined,
                keyboardType: TextInputType.text,
                validator: validarRut,
              ),
            ),
            const SizedBox(height: 14),
            CampoRotulado(
              rotulo: 'Correo electrónico',
              campo: _campo(
                controller: _emailController,
                hintText: 'tu@correo.com',
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                validator: validarEmail,
              ),
            ),
            const SizedBox(height: 14),
            CampoRotulado(
              rotulo: 'Teléfono móvil',
              campo: TextFormField(
                controller: _telefonoController,
                keyboardType: TextInputType.phone,
                validator: validarMovil,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                  LengthLimitingTextInputFormatter(9),
                ],
                decoration: const InputDecoration(
                  hintText: '1234 5678',
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(left: 14, right: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.phone_android_rounded, color: RBColores.texto2),
                        SizedBox(width: 10),
                        Text(
                          '+56 9',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: RBColores.tinta,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            CampoRotulado(
              rotulo: 'Contraseña',
              campo: TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                validator: validarPasswordNueva,
                decoration: InputDecoration(
                  hintText: 'Mínimo 8 caracteres',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword ? 'Mostrar contraseña' : 'Ocultar contraseña',
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            BotonPrincipal(
              texto: 'Crear cuenta',
              onPressed: _registrar,
              cargando: _cargando,
            ),
          ],
        ),
      ),
      pie: EnlaceAcceso(
        texto: '¿Ya tienes cuenta?',
        enlace: 'Inicia sesión',
        onTap: () => Navigator.maybePop(context),
      ),
    );
  }

  Widget _campo({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required TextInputType keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: Icon(icon),
      ),
    );
  }
}
