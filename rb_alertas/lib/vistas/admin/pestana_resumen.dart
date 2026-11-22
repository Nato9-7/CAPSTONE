import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/modelos.dart';
import 'package:rb_alertas/servicios/admin_servicio.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/admin/analisis/graficos_analisis.dart';
import 'package:rb_alertas/vistas/admin/comun_admin.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Cifras generales de reportes y usuarios, con un adelanto del análisis.
class PestanaResumen extends StatefulWidget {
  /// Abre la sección Análisis.
  final VoidCallback alAbrirAnalisis;

  /// Abre Reportes en la cola de pendientes.
  final VoidCallback alAbrirPendientes;

  const PestanaResumen({super.key, required this.alAbrirAnalisis, required this.alAbrirPendientes});

  @override
  State<PestanaResumen> createState() => _PestanaResumenState();
}

class _PestanaResumenState extends State<PestanaResumen> with AutomaticKeepAliveClientMixin {
  final _servicio = AdminServicio();
  ResumenAdmin? _resumen;
  ResumenGrafo? _analisis;
  bool _analisisFallo = false;
  DateTime? _actualizado;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// El análisis viene de Neo4j: si no responde, el resumen se ve igual y la tarjeta lo avisa.
  Future<void> _cargarAnalisis() async {
    try {
      final analisis = await _servicio.resumenGrafo();
      if (mounted) {
        setState(() {
          _analisis = analisis;
          _analisisFallo = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _analisisFallo = true);
    }
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final (resumen, _) = await (_servicio.resumen(), _cargarAnalisis()).wait;
      if (mounted) {
        setState(() {
          _resumen = resumen;
          _actualizado = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final r = _resumen;
    if (r == null) return cargandoOError(_error, _cargar);
    final pendientes = r.reportesPorEstado['PENDIENTE'] ?? 0;

    return RefreshIndicator(
      onRefresh: _cargar,
      child: LayoutBuilder(
        builder: (context, c) => ListView(
          padding: EdgeInsets.fromLTRB(c.maxWidth < 600 ? 16 : 24, 12, c.maxWidth < 600 ? 16 : 24, 32),
          children: [
            if (_actualizado != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Text(
                  'Actualizado a las ${_actualizado!.hour.toString().padLeft(2, '0')}:'
                  '${_actualizado!.minute.toString().padLeft(2, '0')} · desliza hacia abajo para recargar',
                  style: const TextStyle(fontSize: 12.5, color: RBColores.texto2),
                ),
              ),
            if (pendientes > 0) ...[
              _AvisoPendientes(total: pendientes, alAbrir: widget.alAbrirPendientes),
              const SizedBox(height: 20),
            ],
            const _Titulo('Reportes'),
            _FilaCifras([
              ('Vigentes', r.reportesVigentes, RBColores.azul),
              ('Últimas 24 h', r.reportes24h, RBColores.azul),
              ('Últimos 7 días', r.reportes7d, RBColores.azul),
            ]),
            const SizedBox(height: 12),
            _Desglose(r.reportesPorEstado),
            const SizedBox(height: 28),
            const _Titulo('Últimos 30 días'),
            _TarjetaAnalisis(analisis: _analisis, fallo: _analisisFallo, alAbrir: widget.alAbrirAnalisis),
            const SizedBox(height: 28),
            const _Titulo('Reportes por categoría (30 días)'),
            _BarrasCategorias(r.categorias30d),
            const SizedBox(height: 28),
            const _Titulo('Usuarios'),
            _FilaCifras([
              ('Activas', r.usuariosPorEstado['ACTIVO'] ?? 0, RBColores.azul),
              ('Nuevas (7 días)', r.usuariosNuevos7d, RBColores.verde),
              ('Suspendidas', r.usuariosPorEstado['SUSPENDIDO'] ?? 0, RBColores.rojo),
            ]),
            const SizedBox(height: 12),
            _Desglose(r.usuariosPorEstado),
          ],
        ),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  final String texto;

  const _Titulo(this.texto);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10, left: 4),
    child: Semantics(header: true, child: EtiquetaSeccion(texto)),
  );
}

/// Llamado a la acción cuando hay reportes esperando revisión.
class _AvisoPendientes extends StatelessWidget {
  final int total;
  final VoidCallback alAbrir;

  const _AvisoPendientes({required this.total, required this.alAbrir});

  @override
  Widget build(BuildContext context) {
    return TarjetaRB(
      onTap: alAbrir,
      colorBorde: RBColores.azul.withValues(alpha: 0.25),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: RBColores.azul50, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.pending_actions_rounded, color: RBColores.azul),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              total == 1 ? '1 reporte pendiente de revisión' : '$total reportes pendientes de revisión',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: RBColores.tinta),
            ),
          ),
          if (MediaQuery.sizeOf(context).width >= 420)
            const Text(
              'Revisar',
              style: TextStyle(fontWeight: FontWeight.w700, color: RBColores.azul),
            ),
          const Icon(Icons.chevron_right_rounded, color: RBColores.azul),
        ],
      ),
    );
  }
}

/// Adelanto del análisis: las calles con más hechos y los sectores en alza.
class _TarjetaAnalisis extends StatelessWidget {
  final ResumenGrafo? analisis;
  final bool fallo;
  final VoidCallback alAbrir;

  const _TarjetaAnalisis({required this.analisis, required this.fallo, required this.alAbrir});

  @override
  Widget build(BuildContext context) {
    final a = analisis;
    if (a == null) {
      return TarjetaRB(
        child: SizedBox(
          height: 80,
          child: Center(
            child: fallo
                ? const Text('El análisis no está disponible ahora.', style: TextStyle(color: RBColores.texto2))
                : const CircularProgressIndicator(color: RBColores.azul),
          ),
        ),
      );
    }
    Widget cifra(int valor, String texto) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$valor',
            style: const TextStyle(
              fontFamily: RBFuentes.titulos,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: RBColores.azul,
            ),
          ),
          Text(texto, style: const TextStyle(fontSize: 12.5, color: RBColores.texto2)),
        ],
      ),
    );
    return TarjetaRB(
      onTap: alAbrir,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              cifra(a.callesConHechos, 'calles con hechos'),
              cifra(a.sectoresEnAlza, 'sectores en alza o nuevos'),
              cifra(a.incidentesAbiertos, 'incidentes con varios reportes'),
            ],
          ),
          if (a.callesTop.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Calles con más hechos',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: RBColores.tinta),
            ),
            const SizedBox(height: 6),
            for (final (i, calle) in a.callesTop.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: RBColores.texto2),
                      ),
                    ),
                    Expanded(child: Text(calle.nombre, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text('${calle.total}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    InsigniaTendencia(tendencia: Tendencia.desdeApi(calle.tendencia)),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: alAbrir,
              icon: const Icon(Icons.insights_rounded, size: 18),
              label: const Text('Ver análisis'),
            ),
          ),
        ],
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

/// Cantidad por estado: todas las píldoras con el mismo estilo, el número adentro.
class _Desglose extends StatelessWidget {
  final Map<String, int> conteo;

  const _Desglose(this.conteo);

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in conteo.entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: RBColores.linea),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: estiloEstado(e.key).$2, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(estiloEstado(e.key).$1, style: const TextStyle(fontSize: 13, color: RBColores.tinta)),
                const SizedBox(width: 6),
                Text(
                  '${e.value}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: RBColores.tinta),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Barras horizontales con la parte del total que tiene cada categoría.
class _BarrasCategorias extends StatelessWidget {
  final List<({String nombre, String? colorHex, int total})> categorias;

  const _BarrasCategorias(this.categorias);

  @override
  Widget build(BuildContext context) {
    final total = categorias.fold<int>(0, (s, c) => s + c.total);
    final ordenadas = [...categorias]..sort((a, b) => b.total.compareTo(a.total));
    return TarjetaRB(
      child: Column(
        children: [
          for (final c in ordenadas)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      c.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, color: RBColores.tinta),
                    ),
                  ),
                  Expanded(
                    flex: 6,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : c.total / total,
                        minHeight: 10,
                        backgroundColor: RBColores.linea,
                        color: colorCategoria('', colorHex: c.colorHex),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 76,
                    child: Text(
                      total == 0 ? '0' : '${c.total} · ${(c.total / total * 100).round()} %',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: RBColores.tinta),
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
