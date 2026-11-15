// Términos de uso y Política de privacidad que el usuario acepta al registrarse.
//
// Al cambiar el contenido hay que subir [DocumentosLegales.version]: la API
// guarda en usuario_consentimiento la versión que aceptó cada persona.

/// Un apartado de un documento: título y sus párrafos.
typedef SeccionLegal = ({String titulo, List<String> parrafos});

enum DocumentoLegal {
  terminos('Términos de uso', _terminos),
  privacidad('Política de privacidad', _privacidad);

  final String titulo;
  final List<SeccionLegal> secciones;
  const DocumentoLegal(this.titulo, this.secciones);
}

class DocumentosLegales {
  static const String version = '1.0';
  static const String vigenteDesde = '15 de noviembre de 2026';
}

const List<SeccionLegal> _terminos = [
  (
    titulo: '1. Aceptación',
    parrafos: [
      'Estos Términos de uso regulan el acceso y uso de la aplicación RB Alertas (en adelante, «la App»). '
          'Al crear una cuenta declaras haberlos leído y aceptarlos, junto con la Política de privacidad. '
          'Si no estás de acuerdo, no debes registrarte ni usar la App.',
      'Para crear una cuenta debes ser mayor de 18 años y entregar datos verdaderos, completos y actualizados.',
    ],
  ),
  (
    titulo: '2. Qué es RB Alertas',
    parrafos: [
      'La App es una plataforma comunitaria donde los vecinos reportan incidentes de seguridad, tránsito y '
          'otros hechos de su entorno, los confirman o desmienten, los comentan y reciben alertas de lo que '
          'ocurre cerca de su ubicación, de sus zonas seguras y de sus grupos vecinales.',
      'RB Alertas no es un servicio de emergencia ni reemplaza a Carabineros (133), Bomberos (132), SAMU (131) '
          'u otros organismos públicos. Ante una emergencia, comunícate primero con ellos. La App no garantiza '
          'que un reporte llegue a una autoridad ni que alguien acuda al lugar.',
    ],
  ),
  (
    titulo: '3. Tu cuenta',
    parrafos: [
      'Eres responsable de mantener la confidencialidad de tu contraseña y de toda actividad realizada desde tu '
          'cuenta. Si sospechas un uso no autorizado, cambia tu contraseña y avísanos.',
      'La cuenta es personal e intransferible. Solo puedes tener una cuenta asociada a tu RUT.',
    ],
  ),
  (
    titulo: '4. Uso permitido',
    parrafos: [
      'Te comprometes a usar la App de buena fe y conforme a la ley. En particular, no está permitido:',
      '• Publicar reportes falsos, exagerados o que puedan causar alarma injustificada.',
      '• Publicar datos personales de terceros (nombres, RUT, patentes, rostros reconocibles, domicilios) o '
          'acusar a personas determinadas.',
      '• Publicar contenido ofensivo, discriminatorio, violento, sexual o que incite a cometer delitos o a '
          'hacer justicia por mano propia.',
      '• Usar la App con fines comerciales, publicitarios o de spam.',
      '• Coordinarse con otras cuentas para confirmar o desmentir reportes de forma artificial, o intentar '
          'vulnerar la seguridad de la App.',
    ],
  ),
  (
    titulo: '5. Contenido que publicas',
    parrafos: [
      'Eres responsable de los reportes, fotografías, videos y comentarios que publicas. Conservas la '
          'titularidad de ese contenido, pero autorizas a RB Alertas, de forma gratuita y mientras esté '
          'publicado, a mostrarlo a otros usuarios, almacenarlo y adaptarlo técnicamente para el '
          'funcionamiento de la App.',
      'En la App tu nombre no se muestra junto a tus reportes ni comentarios: los demás vecinos te ven con '
          'un alias. Los reportes vencen de forma automática después de un tiempo y dejan de mostrarse en el mapa.',
    ],
  ),
  (
    titulo: '6. Moderación',
    parrafos: [
      'La comunidad puede denunciar contenido. RB Alertas puede ocultar, descartar o eliminar reportes y '
          'comentarios que infrinjan estos Términos, y suspender o cerrar las cuentas responsables, sin '
          'perjuicio de las acciones legales que correspondan.',
      'La reputación de cada cuenta se calcula con los votos que reciben sus reportes y puede usarse para '
          'detectar abusos.',
    ],
  ),
  (
    titulo: '7. Limitación de responsabilidad',
    parrafos: [
      'La información de la App proviene de los propios usuarios. RB Alertas no verifica previamente cada '
          'reporte y no garantiza su exactitud, vigencia ni integridad. Las decisiones que tomes a partir de '
          'ella son de tu exclusiva responsabilidad.',
      'La App se entrega «tal cual» y puede tener interrupciones por mantención, fallas de conexión o causas '
          'ajenas a nuestro control.',
    ],
  ),
  (
    titulo: '8. Cambios y término',
    parrafos: [
      'Podemos modificar estos Términos. Si el cambio es relevante, te lo informaremos en la App y te '
          'pediremos aceptarlo nuevamente antes de seguir usándola.',
      'Puedes dejar de usar la App y solicitar la eliminación de tu cuenta en cualquier momento.',
    ],
  ),
  (
    titulo: '9. Ley aplicable',
    parrafos: [
      'Estos Términos se rigen por las leyes de la República de Chile. Cualquier controversia se someterá a '
          'los tribunales ordinarios de justicia competentes, sin perjuicio de los derechos que te otorga la '
          'Ley N° 19.496 sobre protección de los derechos de los consumidores.',
    ],
  ),
];

const List<SeccionLegal> _privacidad = [
  (
    titulo: '1. Responsable',
    parrafos: [
      'RB Alertas es responsable del tratamiento de los datos personales que entregas al usar la App. Esta '
          'Política explica qué datos recolectamos, para qué los usamos y cuáles son tus derechos, conforme a '
          'la Ley N° 19.628 sobre protección de la vida privada y la Ley N° 21.719 que la modifica.',
    ],
  ),
  (
    titulo: '2. Datos que recolectamos',
    parrafos: [
      '• Datos de tu cuenta: nombres, apellidos, RUT, correo electrónico, teléfono móvil, comuna y región, y '
          'tu contraseña, que se guarda cifrada y nadie puede leer.',
      '• Ubicación: la posición del dispositivo cuando reportas, cuando usas el mapa o las alertas cercanas y, '
          'si lo activas, en segundo plano para avisarte al pasar por zonas de riesgo.',
      '• Contenido: reportes, fotografías, videos, comentarios, votos, denuncias, zonas seguras y grupos '
          'vecinales que crees o a los que te unas.',
      '• Datos técnicos: identificador de notificaciones del dispositivo, modelo, versión del sistema y de la '
          'App, dirección IP y fecha de tus accesos y de la aceptación de estos documentos.',
    ],
  ),
  (
    titulo: '3. Para qué los usamos',
    parrafos: [
      '• Crear y administrar tu cuenta, verificar tu correo y permitir la recuperación de tu contraseña.',
      '• Mostrar los incidentes en el mapa, calcular su distancia y enviarte alertas de lo que ocurre cerca '
          'de ti, de tus zonas seguras y de tus grupos.',
      '• Mostrarte los teléfonos de emergencia de tu comuna.',
      '• Moderar el contenido, calcular la reputación de las cuentas y prevenir abusos o reportes falsos.',
      '• Elaborar estadísticas y mapas de riesgo agregados, que no permiten identificar a ninguna persona.',
      'La base para tratar tus datos es el consentimiento que otorgas al registrarte y la ejecución del '
          'servicio que solicitas. No vendemos tus datos ni los usamos con fines publicitarios.',
    ],
  ),
  (
    titulo: '4. Uso de tu ubicación',
    parrafos: [
      'La ubicación es indispensable para el funcionamiento de la App. Solo se registra la posición asociada '
          'a tus reportes y zonas seguras; las consultas del mapa y de alertas cercanas usan tu posición en el '
          'momento, sin guardar un historial de tus desplazamientos.',
      'El aviso de zonas de riesgo con la App cerrada requiere el permiso «Permitir todo el tiempo». Puedes '
          'desactivarlo cuando quieras desde la App o desde los ajustes del teléfono.',
    ],
  ),
  (
    titulo: '5. Quién puede ver tus datos',
    parrafos: [
      '• Otros usuarios: ven tus reportes y comentarios con un alias, sin tu nombre, RUT, correo ni teléfono. '
          'En los grupos vecinales, los miembros ven tu alias.',
      '• Administradores de RB Alertas: acceden a los datos necesarios para moderar el contenido y atender '
          'solicitudes.',
      '• Proveedores tecnológicos que prestan servicios para el funcionamiento de la App, como el alojamiento '
          'de servidores, el envío de correos, las notificaciones push (Firebase Cloud Messaging, de Google) y '
          'los mapas y direcciones (OpenStreetMap). Solo reciben los datos necesarios para su función.',
      '• Autoridades: cuando una ley o una resolución judicial lo exija.',
    ],
  ),
  (
    titulo: '6. Conservación y seguridad',
    parrafos: [
      'Conservamos tus datos mientras tu cuenta esté activa. Si la eliminas, borraremos o anonimizaremos tus '
          'datos personales, salvo los que debamos conservar por obligación legal o para resolver reclamos.',
      'Las comunicaciones con la App viajan cifradas (HTTPS), tu contraseña se almacena con un algoritmo de '
          'cifrado irreversible y tu sesión se guarda cifrada en el teléfono.',
    ],
  ),
  (
    titulo: '7. Tus derechos',
    parrafos: [
      'Puedes solicitar en cualquier momento el acceso a tus datos, su rectificación, su supresión, oponerte '
          'a su tratamiento, pedir su portabilidad y revocar tu consentimiento. La revocación no afecta el '
          'tratamiento realizado antes de ella, pero puede impedir que sigas usando la App.',
      'Para ejercer estos derechos, escríbenos desde el correo asociado a tu cuenta a la dirección desde la '
          'que recibiste el correo de verificación. Responderemos dentro de los plazos que establece la ley.',
    ],
  ),
  (
    titulo: '8. Cambios a esta Política',
    parrafos: [
      'Si modificamos esta Política de forma relevante, te lo informaremos en la App y te pediremos aceptarla '
          'nuevamente.',
    ],
  ),
];
