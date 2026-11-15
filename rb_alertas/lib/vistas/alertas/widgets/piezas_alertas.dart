import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/zona_segura.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Número grande + texto, dentro de la tarjeta verde.
class Cifra extends StatelessWidget {
  final String valor;
  final String etiqueta;

  const Cifra({super.key, required this.valor, required this.etiqueta});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          valor,
          style: const TextStyle(
            fontFamily: RBFuentes.titulos,
            fontSize: 40,
            height: 1.05,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        Text(etiqueta, style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.9))),
      ],
    );
  }
}

/// Fila horizontal de filtros de estado.
class FiltrosEstado<T> extends StatelessWidget {
  final List<(T, String)> opciones;
  final T seleccionado;
  final ValueChanged<T> onSeleccionar;

  const FiltrosEstado({
    super.key,
    required this.opciones,
    required this.seleccionado,
    required this.onSeleccionar,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (valor, etiqueta) in opciones) ...[
            ChipFiltro(etiqueta: etiqueta, activo: valor == seleccionado, onTap: () => onSeleccionar(valor)),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

/// Tarjeta de una zona segura con su radio y cuántas alertas vigentes tiene.
class TarjetaZona extends StatelessWidget {
  final ZonaSegura zona;
  final int alertas;
  final VoidCallback onTap;

  const TarjetaZona({super.key, required this.zona, required this.alertas, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: TarjetaRB(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(18, 18, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(color: RBColores.verde50, borderRadius: BorderRadius.circular(14)),
              child: Icon(zona.tipo.icono, color: RBColores.verde, size: 26),
            ),
            const Spacer(),
            Text(
              zona.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w700, color: RBColores.tinta),
            ),
            Text('Radio ${zona.radioTexto}', style: const TextStyle(fontSize: 14, color: RBColores.texto2)),
            const SizedBox(height: 4),
            Text(
              alertas == 0 ? 'Sin alertas' : '$alertas ${alertas == 1 ? 'alerta' : 'alertas'}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: alertas == 0 ? RBColores.verde : RBColores.rojo,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta punteada para crear la primera zona segura.
class TarjetaAnadirZona extends StatelessWidget {
  final VoidCallback onTap;

  const TarjetaAnadirZona({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: CustomPaint(
        painter: const BordePunteado(color: RBColores.placeholder, radio: RBRadios.tarjeta),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(RBRadios.tarjeta),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, color: RBColores.azul, size: 30),
                SizedBox(height: 6),
                Text('Añadir zona', style: TextStyle(fontWeight: FontWeight.w700, color: RBColores.azul)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
