// Gráficos del análisis dibujados a mano (sin librerías): barras por día,
// mini serie por sector e insignia de tendencia.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/analisis.dart';
import 'package:rb_alertas/tema/rb_tema.dart';

/// Ámbar del panel para "a la baja"/"dudoso": entre el rojo y el verde.
const colorAmbar = Color(0xFFB7791F);

const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/// "22 nov"
String diaCorto(DateTime d) => '${d.day} ${_meses[d.month - 1]}';

/// Texto, color e ícono de una tendencia. Para hechos, subir es malo: rojo.
(String, Color, IconData) estiloTendencia(Tendencia t, double? variacion) => switch (t) {
  Tendencia.nueva => ('Nueva', RBColores.rojo, Icons.fiber_new_rounded),
  Tendencia.sube => (variacion == null ? 'Sube' : '+${variacion.round()} %', RBColores.rojo, Icons.trending_up_rounded),
  Tendencia.baja => ('${variacion?.round() ?? ''} %', RBColores.verde, Icons.trending_down_rounded),
  Tendencia.igual => ('Estable', RBColores.texto2, Icons.trending_flat_rounded),
};

/// Píldora con la tendencia frente al período anterior.
class InsigniaTendencia extends StatelessWidget {
  final Tendencia tendencia;
  final double? variacion;

  const InsigniaTendencia({super.key, required this.tendencia, this.variacion});

  @override
  Widget build(BuildContext context) {
    final (texto, color, icono) = estiloTendencia(tendencia, variacion);
    return Semantics(
      label: 'Tendencia: $texto',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 15, color: color),
            const SizedBox(width: 3),
            Text(
              texto,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barras de hechos por día, con la línea del promedio y el día tocado resaltado.
class BarrasPorDia extends StatefulWidget {
  final List<DiaAnalisis> dias;
  final double promedio;
  final double alto;

  const BarrasPorDia({super.key, required this.dias, required this.promedio, this.alto = 190});

  @override
  State<BarrasPorDia> createState() => _BarrasPorDiaState();
}

class _BarrasPorDiaState extends State<BarrasPorDia> {
  int? _tocado;

  int _indiceEn(double x, double ancho) {
    final n = widget.dias.length;
    return (x / ancho * n).floor().clamp(0, n - 1);
  }

  @override
  Widget build(BuildContext context) {
    final dias = widget.dias;
    if (dias.isEmpty) return SizedBox(height: widget.alto);
    final maximo = dias.map((d) => d.total).fold(0, math.max);
    final elegido = _tocado == null ? null : dias[_tocado!];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 22,
          child: Text(
            elegido == null
                ? 'Toca una barra para ver el día'
                : '${diaCorto(elegido.dia)}: ${elegido.total} ${elegido.total == 1 ? 'hecho' : 'hechos'}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: elegido == null ? FontWeight.w500 : FontWeight.w700,
              color: elegido == null ? RBColores.texto2 : RBColores.tinta,
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, c) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => setState(() => _tocado = _indiceEn(d.localPosition.dx - 28, c.maxWidth - 28)),
            onHorizontalDragUpdate: (d) =>
                setState(() => _tocado = _indiceEn(d.localPosition.dx - 28, c.maxWidth - 28)),
            child: Semantics(
              label: 'Gráfico de hechos por día. Máximo $maximo en un día.',
              child: CustomPaint(
                size: Size(c.maxWidth, widget.alto),
                painter: _PintorBarras(dias: dias, maximo: maximo, promedio: widget.promedio, tocado: _tocado),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PintorBarras extends CustomPainter {
  final List<DiaAnalisis> dias;
  final int maximo;
  final double promedio;
  final int? tocado;

  _PintorBarras({required this.dias, required this.maximo, required this.promedio, required this.tocado});

  static const _margenIzq = 28.0;
  static const _margenAbajo = 22.0;

  void _texto(
    Canvas canvas,
    String texto,
    Offset pos, {
    double tamano = 11,
    Color color = RBColores.texto2,
    bool derecha = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: texto,
        style: TextStyle(fontSize: tamano, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, derecha ? pos.translate(-tp.width, -tp.height / 2) : pos.translate(-tp.width / 2, 0));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final alto = size.height - _margenAbajo;
    final ancho = size.width - _margenIzq;
    final tope = math.max(maximo, 1);
    final rejilla = Paint()
      ..color = RBColores.linea
      ..strokeWidth = 1;

    // Rejilla y valores del eje: 0, la mitad y el máximo.
    for (final valor in {0, (tope / 2).ceil(), tope}) {
      final y = alto - valor / tope * (alto - 8);
      canvas.drawLine(Offset(_margenIzq, y), Offset(size.width, y), rejilla);
      _texto(canvas, '$valor', Offset(_margenIzq - 6, y), derecha: true);
    }

    final paso = ancho / dias.length;
    final anchoBarra = math.max(2.0, math.min(paso * 0.68, 26.0));
    for (var i = 0; i < dias.length; i++) {
      final d = dias[i];
      final x = _margenIzq + paso * i + (paso - anchoBarra) / 2;
      final h = d.total / tope * (alto - 8);
      final color = tocado == null || tocado == i ? RBColores.azul : RBColores.azul.withValues(alpha: 0.35);
      if (d.total > 0) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(x, alto - h, anchoBarra, h),
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(4),
          ),
          Paint()..color = color,
        );
      }
    }

    // Promedio diario: línea punteada verde.
    if (promedio > 0) {
      final y = alto - promedio / tope * (alto - 8);
      final linea = Paint()
        ..color = RBColores.verde
        ..strokeWidth = 1.5;
      for (var x = _margenIzq; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, size.width), y), linea);
      }
    }

    // Fechas del eje: unas 6 marcas repartidas, siempre la primera y la última.
    final cada = math.max(1, (dias.length / 6).ceil());
    for (var i = 0; i < dias.length; i += cada) {
      _texto(canvas, diaCorto(dias[i].dia), Offset(_margenIzq + paso * i + paso / 2, alto + 6));
    }
  }

  @override
  bool shouldRepaint(_PintorBarras viejo) => viejo.dias != dias || viejo.tocado != tocado || viejo.promedio != promedio;
}

/// Mini serie de un sector: cómo se repartieron sus hechos en los tramos del período.
class MiniSerie extends StatelessWidget {
  final List<int> serie;
  final Color color;
  final double ancho;
  final double alto;

  const MiniSerie({super.key, required this.serie, required this.color, this.ancho = 88, this.alto = 30});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Evolución: ${serie.join(', ')}',
      child: CustomPaint(size: Size(ancho, alto), painter: _PintorSerie(serie, color)),
    );
  }
}

class _PintorSerie extends CustomPainter {
  final List<int> serie;
  final Color color;

  _PintorSerie(this.serie, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (serie.isEmpty) return;
    final maximo = math.max(serie.fold(0, math.max), 1);
    final paso = serie.length == 1 ? 0.0 : size.width / (serie.length - 1);
    Offset punto(int i) => Offset(paso * i, size.height - 3 - serie[i] / maximo * (size.height - 6));

    final camino = Path()..moveTo(punto(0).dx, punto(0).dy);
    for (var i = 1; i < serie.length; i++) {
      camino.lineTo(punto(i).dx, punto(i).dy);
    }
    final relleno = Path.from(camino)
      ..lineTo(paso * (serie.length - 1), size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(relleno, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
      camino,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(punto(serie.length - 1), 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PintorSerie viejo) => viejo.serie != serie || viejo.color != color;
}

/// Barra horizontal proporcional (para el ranking de calles).
class BarraProporcion extends StatelessWidget {
  final double fraccion;
  final Color color;

  const BarraProporcion({super.key, required this.fraccion, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: fraccion.clamp(0.0, 1.0),
        minHeight: 6,
        color: color,
        backgroundColor: RBColores.linea,
      ),
    );
  }
}
