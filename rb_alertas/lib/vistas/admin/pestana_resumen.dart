import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/modelos.dart';
import 'package:rb_alertas/servicios/admin_servicio.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/admin/comun_admin.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';
import 'package:rb_alertas/widgets/lienzo_grafo.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Cifras generales de reportes y usuarios, con la red en miniatura.
class PestanaResumen extends StatefulWidget {
  /// Abre la sección Red (desde la miniatura).
  final VoidCallback alAbrirRed;

  const PestanaResumen({super.key, required this.alAbrirRed});

  @override
  State<PestanaResumen> createState() => _PestanaResumenState();
}

class _PestanaResumenState extends State<PestanaResumen> with AutomaticKeepAliveClientMixin {
  final _servicio = AdminServicio();
  ResumenAdmin? _resumen;
  RedGrafo? _red;
  ResumenGrafo? _resumenRed;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// La red en miniatura es un extra: si Neo4j no responde, el resumen se ve igual.
  Future<void> _cargarRed() async {
    try {
      final red = await _servicio.red();
      final resumen = await _servicio.resumenGrafo();
      if (mounted) {
        setState(() {
          _red = red;
          _resumenRed = resumen;
        });
      }
    } catch (_) {
      // sin miniatura
    }
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    _cargarRed();
    try {
      final resumen = await _servicio.resumen();
      if (mounted) setState(() => _resumen = resumen);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final r = _resumen;
    if (r == null) return cargandoOError(_error, _cargar);

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (_red != null && _red!.nodos.isNotEmpty) ...[
            const _Titulo('La red de vecinos'),
            _MiniRed(red: _red!, resumen: _resumenRed, alAbrir: widget.alAbrirRed),
            const SizedBox(height: 28),
          ],
          const _Titulo('Reportes'),
          _FilaCifras([
            ('Vigentes', r.reportesVigentes, RBColores.azul),
            ('Últimas 24 h', r.reportes24h, RBColores.azul),
            ('Últimos 7 días', r.reportes7d, RBColores.verde),
          ]),
          const SizedBox(height: 12),
          _Desglose(r.reportesPorEstado, chipReporte),
          const SizedBox(height: 28),
          const _Titulo('Usuarios'),
          _FilaCifras([
            ('Cuentas', r.totalUsuarios, RBColores.azul),
            ('Nuevas (7 días)', r.usuariosNuevos7d, RBColores.verde),
            ('Suspendidas', r.usuariosPorEstado['SUSPENDIDO'] ?? 0, RBColores.rojo),
          ]),
          const SizedBox(height: 12),
          _Desglose(r.usuariosPorEstado, chipCuenta),
          const SizedBox(height: 28),
          const _Titulo('Reportes por categoría (30 días)'),
          _BarrasCategorias(r.categorias30d),
        ],
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  final String texto;

  const _Titulo(this.texto);

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 10, left: 4), child: EtiquetaSeccion(texto));
}

/// Vista pequeña de quién apoya a quién, con los hallazgos al lado.
class _MiniRed extends StatelessWidget {
  final RedGrafo red;
  final ResumenGrafo? resumen;
  final VoidCallback alAbrir;

  const _MiniRed({required this.red, required this.resumen, required this.alAbrir});

  @override
  Widget build(BuildContext context) {
    Widget cifra(int? valor, String texto, Color color) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            '${valor ?? 0}',
            style: TextStyle(fontFamily: RBFuentes.titulos, fontSize: 24, fontWeight: FontWeight.w800, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 13, color: RBColores.texto2))),
        ],
      ),
    );
    final cifras = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        cifra(resumen?.sospechosos, 'grupos de cuentas sospechosas', RBColores.rojo),
        cifra(resumen?.bajaReputacion, 'vecinos con reputación baja', colorAmbarRed),
        cifra(resumen?.incidentesAbiertos, 'incidentes abiertos con varios reportes', RBColores.azul),
        FilledButton.icon(
          onPressed: alAbrir,
          icon: const Icon(Icons.hub_rounded, size: 18),
          label: const Text('Explorar la red'),
        ),
      ],
    );
    final lienzo = SizedBox(
      height: 220,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ColoredBox(
          color: RBColores.fondo,
          child: LienzoGrafo(nodos: red.nodos, aristas: red.aristas, interactivo: false),
        ),
      ),
    );
    return TarjetaRB(
      onTap: alAbrir,
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 560
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(flex: 3, child: lienzo),
                  const SizedBox(width: 18),
                  Expanded(flex: 2, child: cifras),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [lienzo, const SizedBox(height: 14), cifras],
              ),
      ),
    );
  }
}

/// Tarjetas con una cifra grande y su etiqueta, repartidas en una fila.
class _FilaCifras extends StatelessWidget {
  final List<(String, int, Color)> cifras;

  const _FilaCifras(this.cifras);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (i, (etiqueta, valor, color)) in cifras.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: TarjetaRB(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
              child: Column(
                children: [
                  Text(
                    '$valor',
                    style: TextStyle(
                      fontFamily: RBFuentes.titulos,
                      fontSize: 28,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    etiqueta,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5, color: RBColores.texto2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Cantidad por estado, cada una con su píldora.
class _Desglose extends StatelessWidget {
  final Map<String, int> conteo;
  final Widget Function(String estado) chip;

  const _Desglose(this.conteo, this.chip);

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final e in conteo.entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              chip(e.key),
              const SizedBox(width: 5),
              Text(
                '${e.value}',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: RBColores.tinta),
              ),
            ],
          ),
      ],
    );
  }
}

/// Barras horizontales con los reportes de cada categoría.
class _BarrasCategorias extends StatelessWidget {
  final List<({String nombre, String? colorHex, int total})> categorias;

  const _BarrasCategorias(this.categorias);

  @override
  Widget build(BuildContext context) {
    final maximo = categorias.fold<int>(1, (m, c) => c.total > m ? c.total : m);
    return TarjetaRB(
      child: Column(
        children: [
          for (final c in categorias)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      c.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, color: RBColores.tinta),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: c.total / maximo,
                        minHeight: 10,
                        backgroundColor: RBColores.linea,
                        color: colorCategoria('', colorHex: c.colorHex),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${c.total}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: RBColores.tinta),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
