import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:rb_alertas/servicios/admin_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';

/// Ámbar para "dudoso" (entre rojo y verde), el mismo del resto del panel.
const colorAmbarRed = Color(0xFFB7791F);

/// Colores para distinguir comunidades (se repiten si hay más).
const coloresComunidad = [
  Color(0xFF002366),
  Color(0xFF007A33),
  Color(0xFF8E44AD),
  Color(0xFFD35400),
  Color(0xFF0A4550),
  Color(0xFFC2185B),
  Color(0xFF1E88E5),
  Color(0xFF7CB342),
];

/// Ícono y color de cada elemento de la red. Los vecinos van por riesgo:
/// verde confiable, ámbar dudoso, rojo poco confiable o suspendido.
(IconData, Color) estiloNodoRed(NodoGrafo n, {bool porComunidad = false}) {
  if (porComunidad && n.comunidad != null) {
    final (icono, _) = estiloNodoRed(n);
    return (icono, coloresComunidad[n.comunidad! % coloresComunidad.length]);
  }
  switch (n.tipo) {
    case 'Usuario':
      final puntaje = (n.datos['reputacion'] as num?)?.round();
      final color = n.estado == 'SUSPENDIDO' || (puntaje != null && puntaje < 35)
          ? RBColores.rojo
          : (puntaje != null && puntaje < 65 ? colorAmbarRed : RBColores.verde);
      return (Icons.person_rounded, color);
    case 'Reporte':
    case 'Incidente':
      final codigo = (n.datos['categoria_codigo'] ?? '').toString();
      return (
        n.tipo == 'Incidente' ? Icons.layers_rounded : iconoCategoria(codigo),
        colorCategoria(codigo, colorHex: n.datos['color']?.toString()),
      );
    case 'Categoria':
      final codigo = (n.datos['codigo'] ?? '').toString();
      return (iconoCategoria(codigo), colorCategoria(codigo, colorHex: n.datos['color']?.toString()));
    case 'Comuna':
      return (Icons.location_city_rounded, RBColores.petroleo);
    case 'Localidad':
      return (Icons.place_rounded, RBColores.texto2);
    case 'ZonaSegura':
      return (Icons.shield_rounded, RBColores.verde);
    case 'Coordinacion':
      return (Icons.gpp_maybe_rounded, RBColores.rojo);
    case 'Grupo':
      return (Icons.groups_rounded, RBColores.petroleo);
    default:
      return (Icons.circle, RBColores.placeholder);
  }
}

/// Color de una relación según lo que significa.
Color colorRelacionRed(AristaGrafo a) {
  switch (a.tipo) {
    case 'VOTO':
      return a.datos['tipo'] == 'DESMIENTE' ? RBColores.rojo : RBColores.verde;
    case 'CONFIRMA_A':
      return RBColores.verde;
    case 'DESMIENTE_A':
      return RBColores.rojo;
    case 'CREO':
      return RBColores.azul;
    case 'MIEMBRO_DE':
      return RBColores.rojo;
    case 'AGRUPA':
      return RBColores.tinta;
    case 'ALERTO_A':
    case 'INTEGRA':
    case 'COMPARTIDO_EN':
      return RBColores.petroleo;
    default:
      return RBColores.bordeCampo;
  }
}

/// Permite pedirle al lienzo que encuadre toda la red (botón "encuadrar").
class ControladorLienzo {
  VoidCallback? _encuadrar;

  void encuadrar() => _encuadrar?.call();
}

/// Red dibujada con una simulación de fuerzas: los elementos se repelen y las
/// relaciones los atraen como resortes, así lo conectado queda junto.
///
/// - Tamaño del nodo: su actividad (cuántas relaciones tiene).
/// - Grosor de la línea: su peso (p. ej. cuántas veces confirmó).
/// - Zoom con la rueda del mouse o con dos dedos; arrastrar para moverse.
/// - Tocar un nodo lo selecciona; doble toque pide ampliar sus conexiones.
///
/// Las posiciones se conservan entre cambios: lo nuevo aparece junto a lo que
/// ya estaba conectado, así el dibujo no salta al ampliar.
class LienzoGrafo extends StatefulWidget {
  final List<NodoGrafo> nodos;
  final List<AristaGrafo> aristas;
  final String? seleccion;

  /// Si no es null, solo estos nodos (y sus relaciones) se ven a todo color.
  final Set<String>? resaltados;
  final bool colorPorComunidad;

  /// false para la miniatura del resumen: sin gestos y siempre encuadrada.
  final bool interactivo;
  final ValueChanged<NodoGrafo>? alSeleccionar;
  final ValueChanged<NodoGrafo>? alAmpliar;
  final VoidCallback? alTocarFondo;
  final ControladorLienzo? controlador;

  const LienzoGrafo({
    super.key,
    required this.nodos,
    required this.aristas,
    this.seleccion,
    this.resaltados,
    this.colorPorComunidad = false,
    this.interactivo = true,
    this.alSeleccionar,
    this.alAmpliar,
    this.alTocarFondo,
    this.controlador,
  });

  @override
  State<LienzoGrafo> createState() => _LienzoGrafoState();
}

class _LienzoGrafoState extends State<LienzoGrafo> with SingleTickerProviderStateMixin {
  static const _mundo = Size(3000, 3000);
  static const _pasosSimulacion = 240;

  final _transformacion = TransformationController();
  late final Ticker _ticker = createTicker((_) => _paso());
  final Map<String, Offset> _pos = {};
  final Map<String, Offset> _vel = {};
  Map<String, int> _grado = {};
  int _pasosRestantes = 0;
  Size _vista = Size.zero;
  bool _encuadreInicial = true;

  /// Al cambiar lo resaltado (un camino, un grupo), se encuadra al terminar de acomodarse.
  bool _encuadrarAlTerminar = false;
  final _aleatorio = math.Random(11);

  Offset get _centroMundo => Offset(_mundo.width / 2, _mundo.height / 2);

  @override
  void initState() {
    super.initState();
    widget.controlador?._encuadrar = _encuadrar;
    _transformacion.addListener(() => setState(() {}));
    _sincronizarNodos();
  }

  @override
  void didUpdateWidget(LienzoGrafo anterior) {
    super.didUpdateWidget(anterior);
    widget.controlador?._encuadrar = _encuadrar;
    if (!identical(anterior.nodos, widget.nodos) || !identical(anterior.aristas, widget.aristas)) {
      _sincronizarNodos();
    }
    if (widget.resaltados != null && !identical(anterior.resaltados, widget.resaltados)) {
      _encuadrarAlTerminar = true;
      if (!_ticker.isActive) WidgetsBinding.instance.addPostFrameCallback((_) => _encuadrar());
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _transformacion.dispose();
    super.dispose();
  }

  /// Agrega los nodos nuevos junto a un vecino ya ubicado, quita los que ya no
  /// están y vuelve a correr la simulación.
  void _sincronizarNodos() {
    final claves = {for (final n in widget.nodos) n.clave};
    _pos.removeWhere((c, _) => !claves.contains(c));
    _vel.removeWhere((c, _) => !claves.contains(c));
    _grado = {};
    for (final a in widget.aristas) {
      _grado[a.origen] = (_grado[a.origen] ?? 0) + 1;
      _grado[a.destino] = (_grado[a.destino] ?? 0) + 1;
    }
    final nuevos = [for (final n in widget.nodos) if (!_pos.containsKey(n.clave)) n];
    final habiaNodos = _pos.isNotEmpty;
    for (final (i, n) in nuevos.indexed) {
      Offset? ancla;
      for (final a in widget.aristas) {
        final otro = a.origen == n.clave ? a.destino : (a.destino == n.clave ? a.origen : null);
        if (otro != null && _pos.containsKey(otro)) {
          ancla = _pos[otro];
          break;
        }
      }
      final angulo = i * 2.39996;
      final radio = habiaNodos ? 40.0 : 30.0 + 22 * math.sqrt(i + 1);
      _pos[n.clave] = (ancla ?? _centroMundo) +
          Offset(math.cos(angulo), math.sin(angulo)) * radio +
          Offset(_aleatorio.nextDouble(), _aleatorio.nextDouble());
      _vel[n.clave] = Offset.zero;
    }
    // Red nueva (o casi toda nueva, p. ej. al cambiar de vista): se vuelve a encuadrar.
    if (!habiaNodos || nuevos.length > widget.nodos.length / 2) _encuadreInicial = true;
    _pasosRestantes = nuevos.isEmpty ? 60 : _pasosSimulacion;
    if (!_ticker.isActive) _ticker.start();
  }

  double radio(String clave, String tipo) {
    final base = switch (tipo) {
      'Usuario' => 15.0,
      'Coordinacion' || 'Incidente' || 'Grupo' => 17.0,
      'Comuna' || 'Localidad' || 'Categoria' => 13.0,
      _ => 11.0,
    };
    return base + math.min(16, math.sqrt((_grado[clave] ?? 0).toDouble()) * 3.2);
  }

  void _paso() {
    if (_pasosRestantes <= 0 || widget.nodos.isEmpty) {
      _ticker.stop();
      if (_encuadreInicial || _encuadrarAlTerminar || !widget.interactivo) {
        _encuadreInicial = false;
        _encuadrarAlTerminar = false;
        _encuadrar();
      }
      return;
    }
    final nodos = widget.nodos;
    final n = nodos.length;
    final k = 70.0 + 120 / math.sqrt(n + 1);
    final enfriamiento = _pasosRestantes / _pasosSimulacion;
    final fuerza = {for (final x in nodos) x.clave: Offset.zero};

    for (var i = 0; i < n; i++) {
      final a = nodos[i].clave;
      for (var j = i + 1; j < n; j++) {
        final b = nodos[j].clave;
        final d = _pos[a]! - _pos[b]!;
        final dist = math.max(d.distance, 1.0);
        final empuje = d / dist * (k * k / dist);
        fuerza[a] = fuerza[a]! + empuje;
        fuerza[b] = fuerza[b]! - empuje;
      }
    }
    for (final a in widget.aristas) {
      final pa = _pos[a.origen], pb = _pos[a.destino];
      if (pa == null || pb == null) continue;
      final d = pb - pa;
      final dist = math.max(d.distance, 1.0);
      final tiron = d / dist * (dist * dist / k) * 0.45;
      fuerza[a.origen] = fuerza[a.origen]! + tiron;
      fuerza[a.destino] = fuerza[a.destino]! - tiron;
    }
    final fijo = widget.seleccion;
    for (final x in nodos) {
      final c = x.clave;
      if (c == fijo && !_encuadreInicial) continue; // el seleccionado no se mueve
      final total = fuerza[c]! + (_centroMundo - _pos[c]!) * 0.03;
      var v = (_vel[c]! + total * 0.05) * 0.6;
      final tope = 28 * enfriamiento + 0.8;
      if (v.distance > tope) v = v / v.distance * tope;
      _vel[c] = v;
      _pos[c] = _pos[c]! + v;
    }
    _pasosRestantes--;
    if (!widget.interactivo && _pasosRestantes % 15 == 0) _encuadrar();
    setState(() {});
  }

  /// Zoom y posición para que se vea toda la red (con sus nombres). Si hay algo
  /// resaltado, se encuadra solo eso.
  void _encuadrar() {
    if (!mounted || _pos.isEmpty || _vista.isEmpty) return;
    final resaltados = widget.resaltados;
    final puntos = [
      for (final e in _pos.entries)
        if (resaltados == null || resaltados.isEmpty || resaltados.contains(e.key)) e.value,
    ];
    if (puntos.isEmpty) return;
    var caja = Rect.fromCircle(center: puntos.first, radius: 1);
    for (final p in puntos) {
      caja = caja.expandToInclude(Rect.fromCircle(center: p, radius: 1));
    }
    caja = caja.inflate(widget.interactivo ? 110 : 40);
    final escala = math
        .min(_vista.width / caja.width, _vista.height / caja.height)
        .clamp(0.15, widget.interactivo ? 1.8 : 1.2);
    _transformacion.value = Matrix4.identity()
      ..translateByDouble(
        _vista.width / 2 - caja.center.dx * escala,
        _vista.height / 2 - caja.center.dy * escala,
        0,
        1,
      )
      ..scaleByDouble(escala, escala, 1, 1);
  }

  NodoGrafo? _nodoEn(Offset puntoVista) {
    final p = _transformacion.toScene(puntoVista);
    NodoGrafo? elegido;
    var menor = double.infinity;
    for (final n in widget.nodos) {
      final pos = _pos[n.clave];
      if (pos == null) continue;
      final d = (pos - p).distance;
      if (d < radio(n.clave, n.tipo) + 8 && d < menor) {
        elegido = n;
        menor = d;
      }
    }
    return elegido;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, restricciones) {
        final nueva = restricciones.biggest;
        if (nueva != _vista) {
          _vista = nueva;
          WidgetsBinding.instance.addPostFrameCallback((_) => _encuadrar());
        }
        final pintor = CustomPaint(
          size: _mundo,
          painter: _PintorRed(
            nodos: widget.nodos,
            aristas: widget.aristas,
            pos: _pos,
            radio: radio,
            seleccion: widget.seleccion,
            resaltados: widget.resaltados,
            porComunidad: widget.colorPorComunidad,
            escala: _transformacion.value.getMaxScaleOnAxis(),
            conNombres: widget.interactivo,
          ),
        );
        if (!widget.interactivo) {
          return ClipRect(
            child: Transform(transform: _transformacion.value, child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              minHeight: 0,
              maxWidth: _mundo.width,
              maxHeight: _mundo.height,
              child: pintor,
            )),
          );
        }
        return ClipRect(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              final n = _nodoEn(d.localPosition);
              if (n == null) {
                widget.alTocarFondo?.call();
              } else {
                widget.alSeleccionar?.call(n);
              }
            },
            onDoubleTapDown: (d) {
              final n = _nodoEn(d.localPosition);
              if (n != null) widget.alAmpliar?.call(n);
            },
            onDoubleTap: () {},
            child: InteractiveViewer(
              transformationController: _transformacion,
              constrained: false,
              minScale: 0.1,
              maxScale: 4,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              child: pintor,
            ),
          ),
        );
      },
    );
  }
}

class _PintorRed extends CustomPainter {
  final List<NodoGrafo> nodos;
  final List<AristaGrafo> aristas;
  final Map<String, Offset> pos;
  final double Function(String clave, String tipo) radio;
  final String? seleccion;
  final Set<String>? resaltados;
  final bool porComunidad;
  final double escala;
  final bool conNombres;

  _PintorRed({
    required this.nodos,
    required this.aristas,
    required this.pos,
    required this.radio,
    required this.seleccion,
    required this.resaltados,
    required this.porComunidad,
    required this.escala,
    required this.conNombres,
  });

  bool _visible(String clave) => resaltados == null || resaltados!.contains(clave);

  @override
  void paint(Canvas canvas, Size size) {
    final tipos = {for (final n in nodos) n.clave: n.tipo};

    // Relaciones: primero las atenuadas, encima las resaltadas.
    for (final atenuadas in [true, false]) {
      for (final a in aristas) {
        final pa = pos[a.origen], pb = pos[a.destino];
        if (pa == null || pb == null) continue;
        final activa = _visible(a.origen) && _visible(a.destino);
        if (activa == atenuadas) continue;
        final peso = ((a.datos['peso'] as num?) ?? 1).toDouble();
        final color = colorRelacionRed(a);
        final grosor = (1.3 + math.sqrt(peso) * 1.6).clamp(1.3, 7.0) / math.max(escala, 0.6);
        final pincel = Paint()
          ..color = color.withValues(alpha: activa ? 0.75 : 0.08)
          ..strokeWidth = grosor
          ..strokeCap = StrokeCap.round;
        final d = pb - pa;
        if (d.distance < 1) continue;
        final u = d / d.distance;
        final fin = pb - u * (radio(a.destino, tipos[a.destino] ?? '') + 2);
        canvas.drawLine(pa, fin, pincel);
        // Punta de flecha: quién hizo qué (votó, creó, confirmó a…).
        if (activa) {
          final normal = Offset(-u.dy, u.dx);
          final largo = 8 + grosor;
          canvas.drawPath(
            Path()
              ..moveTo(fin.dx, fin.dy)
              ..lineTo((fin - u * largo + normal * largo * 0.45).dx, (fin - u * largo + normal * largo * 0.45).dy)
              ..lineTo((fin - u * largo - normal * largo * 0.45).dx, (fin - u * largo - normal * largo * 0.45).dy)
              ..close(),
            Paint()..color = color.withValues(alpha: 0.85),
          );
        }
      }
    }

    // Nodos: los atenuados primero, el seleccionado al final.
    final ordenados = [...nodos]
      ..sort((a, b) {
        int peso(NodoGrafo n) => n.clave == seleccion ? 2 : (_visible(n.clave) ? 1 : 0);
        return peso(a).compareTo(peso(b));
      });
    for (final n in ordenados) {
      final p = pos[n.clave];
      if (p == null) continue;
      final r = radio(n.clave, n.tipo);
      final (icono, color) = estiloNodoRed(n, porComunidad: porComunidad);
      final activo = _visible(n.clave);
      final seleccionado = n.clave == seleccion;
      final alfa = activo ? 1.0 : 0.18;

      if (seleccionado) {
        canvas.drawCircle(p, r + 9, Paint()..color = color.withValues(alpha: 0.22));
      }
      canvas.drawCircle(
        p + const Offset(0, 2),
        r,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.12 * alfa)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(p, r, Paint()..color = (seleccionado ? color : Colors.white).withValues(alpha: alfa));
      canvas.drawCircle(
        p,
        r,
        Paint()
          ..color = color.withValues(alpha: alfa)
          ..style = PaintingStyle.stroke
          ..strokeWidth = n.estado == 'SUSPENDIDO' ? 4 : 2.6,
      );
      final glifo = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icono.codePoint),
          style: TextStyle(
            fontFamily: icono.fontFamily,
            package: icono.fontPackage,
            fontSize: r * 1.05,
            color: (seleccionado ? Colors.white : color).withValues(alpha: alfa),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      glifo.paint(canvas, p - Offset(glifo.width / 2, glifo.height / 2));

      // Nombres: siempre en lo seleccionado o resaltado; el resto, al acercarse.
      final mostrarNombre = conNombres &&
          activo &&
          (seleccionado || resaltados != null || escala >= 0.85 || n.tipo == 'Usuario' && escala >= 0.55);
      if (mostrarNombre) {
        final texto = TextPainter(
          text: TextSpan(
            text: n.etiqueta,
            style: TextStyle(
              fontSize: (seleccionado ? 13.5 : 11.5) / math.min(math.max(escala, 0.55), 1.4),
              fontWeight: seleccionado || n.tipo == 'Usuario' ? FontWeight.w700 : FontWeight.w500,
              color: RBColores.tinta,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 170 / math.min(math.max(escala, 0.55), 1.4));
        final caja = Rect.fromLTWH(
          p.dx - texto.width / 2 - 5,
          p.dy + r + 4,
          texto.width + 10,
          texto.height + 3,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(caja, const Radius.circular(6)),
          Paint()..color = Colors.white.withValues(alpha: 0.88),
        );
        texto.paint(canvas, caja.topLeft + const Offset(5, 1.5));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PintorRed viejo) => true;
}
