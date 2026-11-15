import 'package:rb_alertas/modelos/lectura_json.dart';
import 'package:rb_alertas/modelos/reporte.dart';

/// Lo que devuelve el login: el token de sesión y los datos básicos del usuario.
class LoginResultado {
  final String token;
  final Map<String, dynamic> usuario;

  LoginResultado({required this.token, required this.usuario});
}

class PerfilUsuario {
  final String nombres;
  final String apellidos;
  final String email;
  final String? urlFoto;
  final bool emailVerificado;
  final String? comuna;
  final String? region;
  final int totalReportes;
  final int totalResueltos;
  final List<EntidadEmergencia> emergencias;

  PerfilUsuario({
    required this.nombres,
    required this.apellidos,
    required this.email,
    required this.urlFoto,
    required this.emailVerificado,
    required this.comuna,
    required this.region,
    required this.totalReportes,
    required this.totalResueltos,
    required this.emergencias,
  });

  String get nombreCompleto => '$nombres $apellidos'.trim();

  String get lugar {
    final partes = [comuna, region].whereType<String>().where((p) => p.isNotEmpty);
    return partes.isEmpty ? 'Chile' : partes.join(', ');
  }

  factory PerfilUsuario.desdeJson(Map<String, dynamic> json) => PerfilUsuario(
    nombres: json.texto('nombres'),
    apellidos: json.texto('apellidos'),
    email: json.texto('email'),
    urlFoto: json.textoOpcional('url_foto_perfil'),
    emailVerificado: json.booleano('email_verificado'),
    comuna: json.textoOpcional('comuna'),
    region: json.textoOpcional('region'),
    totalReportes: json.entero('total_reportes'),
    totalResueltos: json.entero('total_resueltos'),
    emergencias: json.lista('emergencias', EntidadEmergencia.desdeJson),
  );
}
