import 'package:flutter/material.dart';
import '../servicios/auth_servicio.dart';
import '../widgets/app_logo.dart';

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

  String? _validarRequerido(String? valor, String campo) {
    if (valor == null || valor.trim().isEmpty) {
      return 'Ingresa tu $campo';
    }
    return null;
  }

  String? _validarEmail(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'Ingresa tu correo electrónico';
    }
    final regexEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!regexEmail.hasMatch(valor.trim())) {
      return 'Ingresa un correo válido';
    }
    return null;
  }

  String? _validarRut(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'Ingresa tu RUT';
    }
    final regexRut = RegExp(r'^\d{7,8}-[\dkK]$');
    if (!regexRut.hasMatch(valor.trim())) {
      return 'Formato inválido (ej: 12345678-9)';
    }
    return null;
  }

  String? _validarTelefono(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'Ingresa tu teléfono móvil';
    }
    final regexTelefono = RegExp(r'^\+?\d{8,15}$');
    if (!regexTelefono.hasMatch(valor.trim())) {
      return 'Ingresa un teléfono válido';
    }
    return null;
  }

  String? _validarPassword(String? valor) {
    if (valor == null || valor.isEmpty) {
      return 'Ingresa una contraseña';
    }
    if (valor.length < 8) {
      return 'Debe tener al menos 8 caracteres';
    }
    return null;
  }

  Future<void> _registrar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _cargando = true);

    try {
      await _authServicio.registrar(
        nombres: _nombresController.text.trim(),
        apellidos: _apellidosController.text.trim(),
        rut: _rutController.text.trim(),
        email: _emailController.text.trim(),
        telefono: _telefonoController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cuenta creada correctamente')),
      );
      Navigator.maybePop(context);
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
    const colorAzul = Color(0xFF0056D2);
    const colorBordeCampo = Color(0xFFE2E8F0);
    const colorTextoGris = Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 32.0),
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
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Encabezado con flecha atrás y título de la app
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: const Icon(
                                Icons.arrow_back,
                                color: Color(0xFF4B5563),
                                size: 22,
                              ),
                              onPressed: () => Navigator.maybePop(context),
                            ),
                          ),
                          const Center(
                            child: Text(
                              'RB Alertas',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: colorAzul,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // Logo consistente con las otras pantallas
                      const AppLogo(size: 88),
                      const SizedBox(height: 22),

                      // Título Crear Cuenta
                      const Text(
                        'Crear Cuenta',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 26),

                      // Campo: Nombres
                      _buildTextField(
                        controller: _nombresController,
                        hintText: 'Nombres',
                        icon: Icons.person_outline_rounded,
                        keyboardType: TextInputType.name,
                        bordeColor: colorBordeCampo,
                        azulColor: colorAzul,
                        validator: (valor) => _validarRequerido(valor, 'nombres'),
                      ),
                      const SizedBox(height: 14),

                      // Campo: Apellidos
                      _buildTextField(
                        controller: _apellidosController,
                        hintText: 'Apellidos',
                        icon: Icons.person_outline_rounded,
                        keyboardType: TextInputType.name,
                        bordeColor: colorBordeCampo,
                        azulColor: colorAzul,
                        validator: (valor) => _validarRequerido(valor, 'apellidos'),
                      ),
                      const SizedBox(height: 14),

                      // Campo: RUT
                      _buildTextField(
                        controller: _rutController,
                        hintText: 'RUT (ej: 12345678-9)',
                        icon: Icons.badge_outlined,
                        keyboardType: TextInputType.text,
                        bordeColor: colorBordeCampo,
                        azulColor: colorAzul,
                        validator: _validarRut,
                      ),
                      const SizedBox(height: 14),

                      // Campo: Correo electrónico
                      _buildTextField(
                        controller: _emailController,
                        hintText: 'Correo electrónico',
                        icon: Icons.mail_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                        bordeColor: colorBordeCampo,
                        azulColor: colorAzul,
                        validator: _validarEmail,
                      ),
                      const SizedBox(height: 14),

                      // Campo: Teléfono móvil
                      _buildTextField(
                        controller: _telefonoController,
                        hintText: 'Teléfono móvil',
                        icon: Icons.phone_android_rounded,
                        keyboardType: TextInputType.phone,
                        bordeColor: colorBordeCampo,
                        azulColor: colorAzul,
                        validator: _validarTelefono,
                      ),
                      const SizedBox(height: 14),

                      // Campo: Contraseña
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        validator: _validarPassword,
                        decoration: InputDecoration(
                          hintText: 'Contraseña',
                          hintStyle: const TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 14,
                          ),
                          prefixIcon: const Icon(
                            Icons.lock_outline_rounded,
                            color: Color(0xFF6B7280),
                            size: 20,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: const Color(0xFF9CA3AF),
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: colorBordeCampo,
                              width: 1.2,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: colorAzul,
                              width: 1.8,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Botón Registrarse
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _cargando ? null : _registrar,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorAzul,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _cargando
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Registrarse',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Footer: ¿Ya tienes una cuenta? Inicia sesión
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            '¿Ya tienes una cuenta? ',
                            style: TextStyle(
                              fontSize: 13,
                              color: colorTextoGris,
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              Navigator.maybePop(context);
                            },
                            child: const Text(
                              'Inicia sesión',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorAzul,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required TextInputType keyboardType,
    required Color bordeColor,
    required Color azulColor,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: Color(0xFF9CA3AF),
          fontSize: 14,
        ),
        prefixIcon: Icon(
          icon,
          color: const Color(0xFF6B7280),
          size: 20,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: bordeColor,
            width: 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: azulColor,
            width: 1.8,
          ),
        ),
      ),
    );
  }
}
