import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:rb_alertas/config/mapa_config.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';

// Piezas visuales compartidas del sistema RB Alertas.

// ---------------------------------------------------------------------------
// Textos derivados
// ---------------------------------------------------------------------------

/// "hace 12 min", "hace 3 h", "Ayer"... para fechas de reportes y alertas.
String tiempoRelativo(DateTime? fecha) {
  if (fecha == null) return '';
  final diferencia = DateTime.now().difference(fecha);
  if (diferencia.isNegative || diferencia.inMinutes < 1) return 'recién';
  if (diferencia.inMinutes < 60) return 'hace ${diferencia.inMinutes} min';
  if (diferencia.inHours < 24) return 'hace ${diferencia.inHours} h';
  if (diferencia.inDays == 1) return 'ayer';
  if (diferencia.inDays < 7) return 'hace ${diferencia.inDays} días';
  if (diferencia.inDays < 30) {
    final semanas = diferencia.inDays ~/ 7;
    return semanas == 1 ? 'hace 1 semana' : 'hace $semanas semanas';
  }
  return '${fecha.day.toString().padLeft(2, '0')}/'
      '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
}

/// Igual que [tiempoRelativo], pero con mayúscula inicial ("Hace 12 min").
String tiempoRelativoInicio(DateTime? fecha) => capitalizar(tiempoRelativo(fecha));

/// "12 min" sin el "hace", para etiquetas compactas ("Accidente · 12 min").
String tiempoCorto(DateTime? fecha) {
  final texto = tiempoRelativo(fecha);
  return texto.startsWith('hace ') ? texto.substring(5) : texto;
}

String capitalizar(String texto) =>
    texto.isEmpty ? texto : texto[0].toUpperCase() + texto.substring(1);

/// "350 m" o "1,2 km", con coma decimal.
String distanciaLegible(num metros) {
  if (metros < 1000) return '${metros.round()} m';
  final km = metros / 1000;
  final texto = km.toStringAsFixed(km >= 10 || km == km.roundToDouble() ? 0 : 1);
  return '${texto.replaceAll('.', ',')} km';
}

/// La BD no guarda un título: se arma con la categoría y la calle
/// ("Accidente en Av. Diego Portales").
String tituloReporte(String categoria, String? direccion) {
  final calle = direccion?.split(',').first.trim();
  return (calle == null || calle.isEmpty) ? categoria : '$categoria en $calle';
}

// ---------------------------------------------------------------------------
// Estados de un reporte
// ---------------------------------------------------------------------------

/// Estados que ve el usuario. En la BD son PENDIENTE, VALIDADO, RESUELTO,
/// EXPIRADO y DESCARTADO.
enum EstadoVisual {
  activa,
  validada,
  resuelta,
  vencida,
  descartada;

  static EstadoVisual desdeApi(String? estado) => switch (estado) {
        'VALIDADO' => EstadoVisual.validada,
        'RESUELTO' => EstadoVisual.resuelta,
        'EXPIRADO' => EstadoVisual.vencida,
        'DESCARTADO' => EstadoVisual.descartada,
        _ => EstadoVisual.activa,
      };
}

/// Píldora de estado: Activa, Validada, Resuelta, Vencida o Descartada.
class ChipEstado extends StatelessWidget {
  final EstadoVisual estado;

  /// Texto alternativo, por ejemplo "Validada por vecinos" en el detalle.
  final String? texto;
  final bool grande;

  const ChipEstado({super.key, required this.estado, this.texto, this.grande = false});

  @override
  Widget build(BuildContext context) {
    final (etiqueta, fondo, color, icono) = switch (estado) {
      EstadoVisual.activa => ('Activa', RBColores.azul50, RBColores.azul, null),
      EstadoVisual.validada => ('Validada', RBColores.verde, Colors.white, Icons.check_rounded),
      EstadoVisual.resuelta => ('Resuelta', RBColores.verde50, RBColores.verde, Icons.check_rounded),
      EstadoVisual.vencida => ('Vencida', RBColores.linea, RBColores.texto2, Icons.schedule_rounded),
      EstadoVisual.descartada => ('Descartada', Colors.transparent, RBColores.texto2, null),
    };
    final tamanoTexto = grande ? 14.0 : 12.5;

    final contenido = Padding(
      padding: EdgeInsets.symmetric(horizontal: grande ? 14 : 10, vertical: grande ? 7 : 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (estado == EstadoVisual.activa)
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 6),
              decoration: const BoxDecoration(color: RBColores.azul, shape: BoxShape.circle),
            )
          else if (icono != null) ...[
            Icon(icono, size: tamanoTexto + 2, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            texto ?? etiqueta,
            style: TextStyle(fontSize: tamanoTexto, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );

    if (estado == EstadoVisual.descartada) {
      return CustomPaint(
        painter: BordePunteado(color: RBColores.placeholder, radio: 20, trazo: 4, espacio: 3),
        child: contenido,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(20)),
      child: contenido,
    );
  }
}

/// Píldora con candado: el reporte es privado de un grupo vecinal.
class ChipSoloGrupo extends StatelessWidget {
  final bool grande;

  const ChipSoloGrupo({super.key, this.grande = false});

  @override
  Widget build(BuildContext context) {
    final tamanoTexto = grande ? 14.0 : 12.5;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: grande ? 14 : 10, vertical: grande ? 7 : 4),
      decoration: BoxDecoration(
        color: RBColores.fondo,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RBColores.linea),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: tamanoTexto + 2, color: RBColores.texto2),
          const SizedBox(width: 4),
          Text(
            'Solo el grupo',
            style: TextStyle(fontSize: tamanoTexto, fontWeight: FontWeight.w700, color: RBColores.texto2),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Marca y mascota
// ---------------------------------------------------------------------------

/// La suricata dentro de un círculo azul marino, con borde blanco opcional.
class AvatarSuricata extends StatelessWidget {
  final double tamano;
  final double borde;
  final bool sombra;

  const AvatarSuricata({super.key, this.tamano = 48, this.borde = 0, this.sombra = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: sombra
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      padding: EdgeInsets.all(borde),
      child: ClipOval(
        child: ColoredBox(
          color: RBColores.azul,
          child: Image.asset(
            'assets/images/logo.png',
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.2),
            errorBuilder: (context, error, pila) =>
                Icon(Icons.shield_outlined, color: Colors.white, size: tamano * 0.5),
          ),
        ),
      ),
    );
  }
}

/// Logotipo "RB Alertas": RB en azul marino y Alertas en verde.
class MarcaRB extends StatelessWidget {
  final double tamano;
  final Color colorRB;

  const MarcaRB({super.key, this.tamano = 40, this.colorRB = RBColores.azul});

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(
      fontFamily: RBFuentes.titulos,
      fontSize: tamano,
      fontWeight: FontWeight.w800,
      letterSpacing: -tamano * 0.03,
      height: 1.1,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'RB ', style: estilo.copyWith(color: colorRB)),
          TextSpan(text: 'Alertas', style: estilo.copyWith(color: RBColores.verde)),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

// ---------------------------------------------------------------------------
// Bloques de pantalla
// ---------------------------------------------------------------------------

/// Título grande de una sección principal ("Alertas", "Zonas seguras").
class TituloPantalla extends StatelessWidget {
  final String texto;
  final double tamano;

  const TituloPantalla(this.texto, {super.key, this.tamano = 40});

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: RBTexto.display.copyWith(fontSize: context.escala(tamano), height: 1.1),
    );
  }
}

/// Rótulo en mayúsculas sobre un grupo ("RECIENTES", "UBICACIÓN").
class EtiquetaSeccion extends StatelessWidget {
  final String texto;
  final Widget? accion;

  const EtiquetaSeccion(this.texto, {super.key, this.accion});

  @override
  Widget build(BuildContext context) {
    final etiqueta = Text(texto.toUpperCase(), style: RBTexto.etiqueta);
    if (accion == null) return etiqueta;
    return Row(children: [Expanded(child: etiqueta), accion!]);
  }
}

/// Tarjeta blanca de las listas: bordes de 20 y sombra muy suave.
class TarjetaRB extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? colorBorde;

  const TarjetaRB({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.colorBorde,
  });

  @override
  Widget build(BuildContext context) {
    final radio = BorderRadius.circular(RBRadios.tarjeta);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radio,
        border: colorBorde == null ? null : Border.all(color: colorBorde!, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: RBColores.azul.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radio,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Fila de una lista de incidentes: ícono de categoría, título, detalle y,
/// debajo, el estado con su contador.
class FilaIncidente extends StatelessWidget {
  final String codigoCategoria;
  final String? colorHex;
  final String titulo;
  final String detalle;
  final EstadoVisual? estado;
  final String? contador;
  final VoidCallback? onTap;

  /// Marca la fila como no leída (borde azul).
  final bool destacada;

  const FilaIncidente({
    super.key,
    required this.codigoCategoria,
    required this.colorHex,
    required this.titulo,
    required this.detalle,
    this.estado,
    this.contador,
    this.onTap,
    this.destacada = false,
  });

  @override
  Widget build(BuildContext context) {
    return TarjetaRB(
      onTap: onTap,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
      colorBorde: destacada ? RBColores.azul : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconoCategoria(codigo: codigoCategoria, colorHex: colorHex, tamano: context.escala(52)),
          SizedBox(width: context.pantallaAngosta ? 12 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16.5,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: RBColores.tinta,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detalle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, color: RBColores.texto2),
                ),
                if (estado != null || contador != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (estado != null) ChipEstado(estado: estado!),
                      if (estado != null && contador != null) const SizedBox(width: 10),
                      if (contador != null)
                        Flexible(
                          child: Text(
                            contador!,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, color: RBColores.texto2),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta verde con la suricata: resumen de "Cerca de ti" y "Mis reportes".
class TarjetaSuricata extends StatelessWidget {
  final Widget child;

  const TarjetaSuricata({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(context.pantallaAngosta ? 18 : 22, 20, 14, 20),
      decoration: BoxDecoration(
        color: RBColores.verde,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(child: child),
          const SizedBox(width: 10),
          AvatarSuricata(tamano: context.escala(72)),
        ],
      ),
    );
  }
}

/// Botón de filtro: relleno azul marino cuando está activo, blanco si no.
class ChipFiltro extends StatelessWidget {
  final String etiqueta;
  final bool activo;
  final VoidCallback onTap;
  final Widget? icono;
  final bool conCheck;

  const ChipFiltro({
    super.key,
    required this.etiqueta,
    required this.activo,
    required this.onTap,
    this.icono,
    this.conCheck = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: activo ? RBColores.azul : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: activo ? RBColores.azul : RBColores.bordeCampo),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (activo && conCheck) ...[
                const Icon(Icons.check_rounded, size: 18, color: Colors.white),
                const SizedBox(width: 6),
              ] else if (icono != null) ...[
                icono!,
                const SizedBox(width: 8),
              ],
              // Flexible: una etiqueta larga (el nombre de un grupo) se corta
              // con "…" en vez de desbordar el chip en pantallas angostas.
              Flexible(
                child: Text(
                  etiqueta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: activo ? Colors.white : RBColores.tinta,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selector de pestañas segmentado (Cerca de ti · Mis zonas · Mis reportes).
class SelectorSegmentado extends StatelessWidget {
  final TabController controlador;
  final List<String> opciones;

  const SelectorSegmentado({super.key, required this.controlador, required this.opciones});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: RBColores.linea,
        borderRadius: BorderRadius.circular(18),
      ),
      child: TabBar(
        controller: controlador,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        splashBorderRadius: BorderRadius.circular(14),
        labelColor: RBColores.azul,
        unselectedLabelColor: RBColores.texto2,
        labelStyle: const TextStyle(
          fontFamily: RBFuentes.interfaz,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: RBFuentes.interfaz,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        tabs: [
          for (final o in opciones)
            Tab(child: FittedBox(fit: BoxFit.scaleDown, child: Text(o, maxLines: 1))),
        ],
      ),
    );
  }
}

/// Mensaje centrado para listas vacías, errores o falta de sesión.
class EstadoVacio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String detalle;
  final String? accion;
  final VoidCallback? onAccion;

  const EstadoVacio({
    super.key,
    required this.icono,
    required this.titulo,
    required this.detalle,
    this.accion,
    this.onAccion,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: RBColores.azul50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icono, size: 30, color: RBColores.azul),
            ),
            const SizedBox(height: 14),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: RBColores.tinta,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detalle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.45, color: RBColores.texto2),
            ),
            if (accion != null && onAccion != null) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onAccion, child: Text(accion!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Aviso suave en ámbar (por ejemplo, sin permiso de ubicación).
class AvisoRB extends StatelessWidget {
  final String texto;

  const AvisoRB({super.key, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF2D49B)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF8A6A00)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(fontSize: 13.5, color: Color(0xFF5C4700)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Botón circular blanco flotante sobre el mapa (volver, compartir, GPS).
class BotonCircular extends StatelessWidget {
  final IconData icono;
  final VoidCallback? onTap;
  final Color fondo;
  final Color color;
  final double tamano;
  final String? tooltip;

  const BotonCircular({
    super.key,
    required this.icono,
    required this.onTap,
    this.fondo = Colors.white,
    this.color = RBColores.tinta,
    this.tamano = 52,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final boton = Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: (fondo == Colors.white ? Colors.black : fondo).withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: fondo,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(icono, color: color, size: tamano * 0.46),
        ),
      ),
    );
    return tooltip == null ? boton : Tooltip(message: tooltip!, child: boton);
  }
}

// ---------------------------------------------------------------------------
// Mapa
// ---------------------------------------------------------------------------

/// Capa base de teselas compartida por todos los mapas.
TileLayer capaMapaBase() => TileLayer(
      urlTemplate: MapaConfig.urlTeselas,
      userAgentPackageName: MapaConfig.paquete,
    );

/// Crédito de los datos del mapa, obligatorio por licencia.
class AtribucionMapa extends StatelessWidget {
  const AtribucionMapa({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      color: Colors.white.withValues(alpha: 0.7),
      child: const Text(
        MapaConfig.atribucion,
        style: TextStyle(fontSize: 9, color: RBColores.texto2),
      ),
    );
  }
}

/// Pin circular de un incidente: color de la categoría, borde blanco e ícono.
/// Seleccionado crece y suma un halo del mismo color.
class PinIncidente extends StatelessWidget {
  final String codigo;
  final String? colorHex;
  final bool seleccionado;

  const PinIncidente({
    super.key,
    required this.codigo,
    this.colorHex,
    this.seleccionado = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = colorCategoria(codigo, colorHex: colorHex);
    final tamano = seleccionado ? 60.0 : 44.0;
    final pin = Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: seleccionado ? 4 : 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(iconoCategoria(codigo), color: Colors.white, size: tamano * 0.42),
    );
    if (!seleccionado) return Center(child: pin);
    return Center(
      child: Container(
        width: tamano + 22,
        height: tamano + 22,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: pin,
      ),
    );
  }
}

/// Punto azul con halo que marca la ubicación del usuario.
class PuntoUsuario extends StatelessWidget {
  const PuntoUsuario({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: RBColores.azul.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: RBColores.azul,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Utilidades de dibujo
// ---------------------------------------------------------------------------

/// Borde punteado redondeado (cajas de foto, "Añadir ubicación", Descartada).
class BordePunteado extends CustomPainter {
  final Color color;
  final double radio;
  final double trazo;
  final double espacio;

  const BordePunteado({
    required this.color,
    this.radio = 16,
    this.trazo = 6,
    this.espacio = 5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final borde = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radio)));

    for (final tramo in borde.computeMetrics()) {
      var distancia = 0.0;
      while (distancia < tramo.length) {
        canvas.drawPath(tramo.extractPath(distancia, distancia + trazo), pincel);
        distancia += trazo + espacio;
      }
    }
  }

  @override
  bool shouldRepaint(BordePunteado anterior) =>
      anterior.color != color || anterior.radio != radio;
}
