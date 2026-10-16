import 'package:flutter/material.dart';

/// Colores del sistema visual RB Alertas (v1).
///
/// Azul marino para la estructura, verde para reportar y para lo que está a
/// salvo. El rojo se reserva para llamar a emergencias.
class RBColores {
  RBColores._();

  static const azul = Color(0xFF002366);
  static const verde = Color(0xFF007A33);
  static const blanco = Color(0xFFFFFFFF);
  static const negro = Color(0xFF000000);

  static const azul50 = Color(0xFFE9EEF8);
  static const verde50 = Color(0xFFE2F2E8);
  static const fondo = Color(0xFFF4F6FA);
  static const linea = Color(0xFFE3E8F0);
  static const texto2 = Color(0xFF5B6680);
  static const tinta = Color(0xFF0E1A33);

  /// Borde de los campos de texto, un poco más marcado que [linea].
  static const bordeCampo = Color(0xFFCBD3E1);
  static const placeholder = Color(0xFF8A93A6);

  static const rojo = Color(0xFFC62828);
  static const rojo50 = Color(0xFFFBE9E9);

  /// Círculo decorativo de las pantallas de acceso.
  static const petroleo = Color(0xFF0A4550);
}

/// Familias tipográficas empaquetadas en assets/fonts.
class RBFuentes {
  RBFuentes._();

  /// Títulos: carácter local y cercano.
  static const titulos = 'BricolageGrotesque';

  /// Interfaz: muy legible en pantallas chicas y al sol.
  static const interfaz = 'Figtree';
}

/// Estilos de texto de la escala tipográfica del diseño.
class RBTexto {
  RBTexto._();

  /// Display · 32/36.
  static const display = TextStyle(
    fontFamily: RBFuentes.titulos,
    fontSize: 32,
    height: 36 / 32,
    fontWeight: FontWeight.w800,
    color: RBColores.azul,
    letterSpacing: -0.5,
  );

  /// Título · 20/26.
  static const titulo = TextStyle(
    fontFamily: RBFuentes.interfaz,
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeight.w700,
    color: RBColores.tinta,
  );

  /// Cuerpo · 15/22.
  static const cuerpo = TextStyle(
    fontFamily: RBFuentes.interfaz,
    fontSize: 15,
    height: 22 / 15,
    color: RBColores.tinta,
  );

  /// Etiqueta · 12, en mayúsculas y espaciada ("UBICACIÓN DETECTADA").
  static const etiqueta = TextStyle(
    fontFamily: RBFuentes.interfaz,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
    color: RBColores.texto2,
  );

  /// Rótulo sobre un campo de formulario ("Correo electrónico").
  static const rotuloCampo = TextStyle(
    fontFamily: RBFuentes.interfaz,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: RBColores.tinta,
  );
}

/// Radios de borde usados en tarjetas, botones y campos.
class RBRadios {
  RBRadios._();

  static const campo = 16.0;
  static const boton = 16.0;
  static const tarjeta = 20.0;
  static const hoja = 28.0;
}

/// Tema de Material con la paleta y las fuentes de RB Alertas.
ThemeData temaRBAlertas() {
  final esquema = ColorScheme.fromSeed(
    seedColor: RBColores.azul,
    primary: RBColores.azul,
    onPrimary: Colors.white,
    secondary: RBColores.verde,
    onSecondary: Colors.white,
    error: RBColores.rojo,
    surface: Colors.white,
    onSurface: RBColores.tinta,
  );

  final bordeCampo = OutlineInputBorder(
    borderRadius: BorderRadius.circular(RBRadios.campo),
    borderSide: const BorderSide(color: RBColores.bordeCampo, width: 1.2),
  );

  final formaBoton = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(RBRadios.boton),
  );
  const textoBoton = TextStyle(
    fontFamily: RBFuentes.interfaz,
    fontSize: 16,
    fontWeight: FontWeight.w700,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    fontFamily: RBFuentes.interfaz,
    scaffoldBackgroundColor: RBColores.fondo,
    dividerColor: RBColores.linea,
    dividerTheme: const DividerThemeData(color: RBColores.linea, space: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: RBColores.fondo,
      surfaceTintColor: Colors.transparent,
      foregroundColor: RBColores.azul,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: RBFuentes.titulos,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: RBColores.azul,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      hintStyle: const TextStyle(color: RBColores.placeholder, fontSize: 16),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      prefixIconColor: RBColores.texto2,
      suffixIconColor: RBColores.texto2,
      border: bordeCampo,
      enabledBorder: bordeCampo,
      focusedBorder: bordeCampo.copyWith(
        borderSide: const BorderSide(color: RBColores.azul, width: 1.8),
      ),
      errorBorder: bordeCampo.copyWith(
        borderSide: const BorderSide(color: RBColores.rojo, width: 1.2),
      ),
      focusedErrorBorder: bordeCampo.copyWith(
        borderSide: const BorderSide(color: RBColores.rojo, width: 1.8),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: RBColores.azul,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(48, 52),
        shape: formaBoton,
        textStyle: textoBoton,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: RBColores.azul,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        shape: formaBoton,
        textStyle: textoBoton,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: RBColores.azul,
        backgroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: RBColores.bordeCampo, width: 1.2),
        shape: formaBoton,
        textStyle: textoBoton,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: RBColores.azul,
        textStyle: const TextStyle(
          fontFamily: RBFuentes.interfaz,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: RBColores.azul,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RBColores.tinta,
      contentTextStyle: const TextStyle(
        fontFamily: RBFuentes.interfaz,
        color: Colors.white,
        fontSize: 14,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RBRadios.tarjeta),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: RBFuentes.titulos,
        fontSize: 21,
        fontWeight: FontWeight.w800,
        color: RBColores.azul,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: RBFuentes.interfaz,
        fontSize: 15,
        height: 1.4,
        color: RBColores.tinta,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: RBColores.bordeCampo,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(RBRadios.hoja)),
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: RBColores.verde,
      inactiveTrackColor: RBColores.linea,
      thumbColor: RBColores.verde,
      overlayColor: Color(0x22007A33),
      activeTickMarkColor: Colors.white,
      inactiveTickMarkColor: RBColores.bordeCampo,
      trackHeight: 6,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: RBColores.azul,
      unselectedLabelColor: RBColores.texto2,
      indicatorColor: RBColores.azul,
      dividerColor: RBColores.linea,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: RBColores.azul,
      side: const BorderSide(color: RBColores.linea),
      labelStyle: const TextStyle(
        fontFamily: RBFuentes.interfaz,
        fontWeight: FontWeight.w600,
        color: RBColores.tinta,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// Ancho de referencia del diseño (un Android/iPhone de tamaño medio).
const _anchoDiseno = 390.0;

/// Ajustes globales según el tamaño de pantalla (se usa en MaterialApp.builder).
///
/// En celulares angostos el texto se reduce un poco (hasta un 14 %), y el
/// tamaño de letra que el usuario elige en su teléfono se respeta hasta 1,3x
/// para que los botones y tarjetas no se rompan.
Widget ajusteResponsivo(BuildContext context, Widget? hijo) {
  final datos = MediaQuery.of(context);
  final factorAncho = (datos.size.width / _anchoDiseno).clamp(0.86, 1.0);
  final escala = (datos.textScaler.scale(1) * factorAncho).clamp(0.8, 1.3);
  return MediaQuery(
    data: datos.copyWith(textScaler: TextScaler.linear(escala)),
    child: hijo ?? const SizedBox(),
  );
}

/// Medidas que se adaptan al tamaño del celular.
extension RBPantalla on BuildContext {
  Size get _tamanoPantalla => MediaQuery.sizeOf(this);

  /// Celulares angostos (iPhone SE, Android compactos): menos de 360 de ancho.
  bool get pantallaAngosta => _tamanoPantalla.width < 360;

  /// Pantallas bajas, donde el contenido fijo debe ocupar menos alto.
  bool get pantallaBaja => _tamanoPantalla.height < 700;

  /// Reduce una medida del diseño en proporción al ancho (nunca la agranda).
  double escala(double valor) =>
      valor * (_tamanoPantalla.width / _anchoDiseno).clamp(0.8, 1.0);

  /// Una fracción del alto de la pantalla, acotada entre [minimo] y [maximo].
  double altoRelativo(double fraccion, {required double minimo, required double maximo}) =>
      (_tamanoPantalla.height * fraccion).clamp(minimo, maximo);
}
