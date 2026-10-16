import 'package:flutter/material.dart';
import 'package:rb_alertas/servicios/auth_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/vistas/admin_vista.dart';
import 'package:rb_alertas/vistas/mapa_vista.dart';
import 'package:rb_alertas/vistas/recuperar_contrasena_vista.dart';
import 'package:rb_alertas/vistas/registro_vista.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/fondo_acceso.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

class InicioSesionVista extends StatefulWidget {
  const InicioSesionVista({super.key});

  @override
  State<InicioSesionVista> createState() => _InicioSesionVistaState();
}

class _InicioSesionVistaState extends State<InicioSesionVista> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authServicio = AuthServicio();
  bool _obscurePassword = true;
  bool _cargando = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _iniciarSesion() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _cargando = true);

    try {
      final resultado = await _authServicio.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      await Sesion.iniciar(resultado);

      if (!mounted) return;
      if (Sesion.esAdmin) {
        // La cuenta admin entra directo al panel, sin el mapa ni el resto de la app.
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const AdminVista()),
          (ruta) => false,
        );
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MapaVista()),
      );
    } on AuthServicioException catch (e) {
      if (!mounted) return;
      if (e.codigo == AuthServicio.codigoEmailNoVerificado) {
        _avisarCorreoSinVerificar(e.mensaje, _emailController.text.trim());
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.mensaje)),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo conectar con el servidor')),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _avisarCorreoSinVerificar(String mensaje, String email) {
    showDialog<void>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('Verifica tu correo'),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogo);
              String resultado;
              try {
                resultado = await _authServicio.reenviarVerificacion(email);
              } on AuthServicioException catch (e) {
                resultado = e.mensaje;
              } catch (_) {
                resultado = 'No se pudo conectar con el servidor';
              }
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(resultado)),
              );
            },
            child: const Text('Reenviar correo'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogo),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bajo = context.pantallaBaja;
    return FondoAcceso(
      tarjeta: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MarcaRB(tamano: context.escala(46)),
            SizedBox(height: bajo ? 4 : 10),
            const Text(
              'Alertas vecinales de Puerto Montt',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, color: RBColores.texto2),
            ),
            SizedBox(height: bajo ? 16 : 26),
            const Text(
              'Iniciar sesión',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: RBColores.tinta,
              ),
            ),
            SizedBox(height: bajo ? 12 : 18),
            CampoRotulado(
              rotulo: 'Correo electrónico',
              campo: TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                validator: (valor) {
                  if (valor == null || valor.trim().isEmpty) {
                    return 'Ingresa tu correo electrónico';
                  }
                  return null;
                },
                decoration: const InputDecoration(
                  hintText: 'tu@correo.com',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
              ),
            ),
            SizedBox(height: bajo ? 12 : 16),
            CampoRotulado(
              rotulo: 'Contraseña',
              campo: TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _cargando ? null : _iniciarSesion(),
                validator: (valor) {
                  if (valor == null || valor.isEmpty) {
                    return 'Ingresa tu contraseña';
                  }
                  return null;
                },
                decoration: InputDecoration(
                  hintText: '••••••••',
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
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RecuperarContrasenaVista(
                        emailInicial: _emailController.text.trim(),
                      ),
                    ),
                  );
                },
                child: const Text(
                  '¿Olvidaste tu contraseña?',
                  style: TextStyle(
                    fontSize: 16,
                    color: RBColores.azul,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            SizedBox(height: bajo ? 16 : 22),
            BotonPrincipal(
              texto: 'Iniciar sesión',
              onPressed: _iniciarSesion,
              cargando: _cargando,
            ),
          ],
        ),
      ),
      pie: EnlaceAcceso(
        texto: '¿No tienes cuenta?',
        enlace: 'Regístrate',
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const RegistroVista()),
          );
        },
      ),
    );
  }
}
