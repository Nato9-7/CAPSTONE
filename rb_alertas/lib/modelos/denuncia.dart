/// Motivos para denunciar un reporte o un comentario (los mismos que acepta la API).
enum MotivoDenuncia {
  falso('FALSO', 'Es falso o engañoso'),
  ofensivo('OFENSIVO', 'Ofensivo o con insultos'),
  spam('SPAM', 'Spam o publicidad'),
  datosPersonales('DATOS_PERSONALES', 'Expone datos personales'),
  otro('OTRO', 'Otro motivo');

  final String api;
  final String texto;
  const MotivoDenuncia(this.api, this.texto);

  static String textoDe(String api) =>
      values.where((m) => m.api == api).firstOrNull?.texto ?? api;
}
