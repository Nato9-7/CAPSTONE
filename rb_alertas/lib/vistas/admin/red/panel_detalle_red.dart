import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/lectura_json.dart';
import 'package:rb_alertas/modelos/modelos.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/vistas/admin/red/filtros_red.dart';
import 'package:rb_alertas/vistas/admin/red/piezas_red.dart';
import 'package:rb_alertas/vistas/admin/red/textos_red.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';

/// Ficha del elemento elegido en la red: qué es, por qué tiene ese color,
/// cómo explorarlo y las acciones de moderación que le corresponden.
class PanelDetalleRed extends StatelessWidget {
  /// null muestra cómo usar la red.
  final NodoGrafo? nodo;

  /// Relaciones de la red visible (para contar conexiones y miembros).
  final List<AristaGrafo> aristas;

  /// Grupos sospechosos cargados, para la evidencia de un nodo "Coordinacion".
  final List<GrupoSospechoso>? sospechosos;
  final FiltrosRed filtros;

  final VoidCallback alCerrar;
  final ValueChanged<NodoGrafo> alAmpliar;
  final ValueChanged<NodoGrafo> alVerSoloConexiones;
  final ValueChanged<NodoGrafo> alBuscarCamino;
  final ValueChanged<NodoGrafo> alCambiarCuenta;
  final ValueChanged<NodoGrafo> alDescartarReporte;
  final ValueChanged<GrupoSospechoso> alSuspenderGrupo;
  final void Function(int id, String estado) alModerarIncidente;

  const PanelDetalleRed({
    super.key,
    required this.nodo,
    required this.aristas,
    required this.sospechosos,
    required this.filtros,
    required this.alCerrar,
    required this.alAmpliar,
    required this.alVerSoloConexiones,
    required this.alBuscarCamino,
    required this.alCambiarCuenta,
    required this.alDescartarReporte,
    required this.alSuspenderGrupo,
    required this.alModerarIncidente,
  });

  GrupoSospechoso? _grupoDe(NodoGrafo n) => sospechosos?.where((g) => g.id == n.id).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final n = nodo;
    if (n == null) return const _Instrucciones();
    final conexiones = aristas.where((a) => a.origen == n.clave || a.destino == n.clave).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
      children: [
        Row(
          children: [
            IconoNodoRed(n, tamano: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nombreTipoRed(n.tipo).toUpperCase(), style: RBTexto.etiqueta),
                  Text(
                    n.etiqueta,
                    style: const TextStyle(
                      fontFamily: RBFuentes.titulos,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: RBColores.azul,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Cerrar',
              onPressed: alCerrar,
              icon: const Icon(Icons.close_rounded, color: RBColores.texto2),
            ),
          ],
        ),
        if (n.estado != null) ...[
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: ChipEstadoRed(n.estado!)),
        ],
        const SizedBox(height: 14),
        ..._contenido(n),
        const SizedBox(height: 6),
        Text(
          '$conexiones conexiones en la red que estás viendo',
          style: const TextStyle(fontSize: 13, color: RBColores.texto2),
        ),
        const SizedBox(height: 14),
        _AccionRed(Icons.unfold_more_rounded, 'Ampliar sus conexiones', () => alAmpliar(n)),
        _AccionRed(Icons.center_focus_strong_rounded, 'Ver solo sus conexiones', () => alVerSoloConexiones(n)),
        _AccionRed(Icons.route_rounded, '¿Cómo se conecta con…?', () => alBuscarCamino(n)),
        const SizedBox(height: 10),
        ..._accionesModeracion(n),
      ],
    );
  }

  /// Lo que se explica de cada tipo de elemento.
  List<Widget> _contenido(NodoGrafo n) {
    final d = n.datos;
    switch (n.tipo) {
      case 'Usuario':
        final puntaje = (d['reputacion'] as num?)?.round();
        if (puntaje == null) return const [];
        return [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$puntaje',
                style: TextStyle(
                  fontFamily: RBFuentes.titulos,
                  fontSize: 40,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: colorPuntajeRed(puntaje),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 6, bottom: 5),
                child: Text('/ 100 de reputación', style: TextStyle(color: RBColores.texto2)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('¿Por qué este puntaje?', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _BarraPuntaje(
            'Respaldo de la comunidad',
            d.decimal('respaldo', 0.5),
            '${d.entero('confirmaciones_recibidas')} confirmaciones y ${d.entero('desmentidos_recibidos')} '
                'desmentidos recibidos. Pesa más la confirmación de un vecino confiable.',
          ),
          _BarraPuntaje(
            'Historial de sus reportes',
            d.decimal('historial', 0.5),
            '${d.entero('reportes_buenos')} validados o resueltos y ${d.entero('reportes_descartados')} descartados.',
          ),
        ];
      case 'Reporte':
        return [
          if (d['categoria'] != null) Text('${d['categoria']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          if (d['descripcion'] != null) ...[
            const SizedBox(height: 4),
            Text('«${d['descripcion']}»', style: const TextStyle(height: 1.4)),
          ],
          const SizedBox(height: 6),
          Text(
            '${d.entero('confirmaciones')} confirman · ${d.entero('desmentidos')} desmienten',
            style: const TextStyle(color: RBColores.texto2),
          ),
          if (d['fecha_creacion'] != null)
            Text(tiempoRelativoInicio(d.fecha('fecha_creacion')), style: const TextStyle(color: RBColores.texto2)),
          const SizedBox(height: 8),
        ];
      case 'Coordinacion':
        final grupo = _grupoDe(n);
        return [
          Text(
            'El ${(d.decimal('reciprocidad') * 100).round()} % de las confirmaciones que dan '
            'se quedan dentro del grupo.',
            style: const TextStyle(height: 1.4),
          ),
          if (grupo != null) ...[const SizedBox(height: 10), EvidenciaSospechosoRed(grupo)],
          const SizedBox(height: 8),
        ];
      case 'Incidente':
        return [
          Text('${d.entero('total')} reportes del mismo hecho · ${d['categoria'] ?? ''}'),
          const SizedBox(height: 4),
          const Text(
            'Misma categoría, a menos de 300 m y con menos de 3 horas de diferencia.',
            style: TextStyle(fontSize: 13, color: RBColores.texto2),
          ),
          const SizedBox(height: 8),
        ];
      case 'Comuna':
      case 'Localidad':
      case 'Categoria':
        return _contenidoLugar(n);
      case 'ZonaSegura':
        return [if (d['radio'] != null) Text('Radio de ${d['radio']} m'), const SizedBox(height: 8)];
      case 'Grupo':
        return _contenidoGrupo(n);
      default:
        return const [];
    }
  }

  /// Cuántos hechos hay en el lugar o la categoría, desglosados por categoría.
  List<Widget> _contenidoLugar(NodoGrafo n) {
    final d = n.datos;
    if (d['total'] is! num) return const [];
    final porCategoria = d.lista('por_categoria', (c) => c);
    final total = d.entero('total');
    final reportes = d.entero('reportes');
    return [
      Text(
        '$total ${total == 1 ? 'hecho' : 'hechos'}'
        '${filtros.categoria != null && n.tipo != 'Categoria' ? ' de esta categoría' : ''}'
        ' · ${filtros.nombrePeriodo.toLowerCase()}',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: RBColores.tinta),
      ),
      // Varios vecinos pueden reportar el mismo hecho: cuenta una vez.
      if (reportes > total)
        Text('Reportados $reportes veces por los vecinos', style: const TextStyle(color: RBColores.texto2)),
      if (d['comuna'] != null) Text('Comuna de ${d['comuna']}', style: const TextStyle(color: RBColores.texto2)),
      if (porCategoria.isNotEmpty) ...[
        const SizedBox(height: 10),
        for (final c in porCategoria) _FilaCategoria(c, total),
      ],
      const SizedBox(height: 4),
      const Text(
        'Los reportes del mismo hecho cuentan una vez y los descartados no cuentan. '
        'Usa «Ver solo sus conexiones» para ver los reportes.',
        style: TextStyle(fontSize: 12.5, color: RBColores.texto2),
      ),
      const SizedBox(height: 8),
    ];
  }

  /// Miembros y reportes compartidos según lo que se ve en la red.
  List<Widget> _contenidoGrupo(NodoGrafo n) {
    final d = n.datos;
    final miembros = aristas.where((a) => a.tipo == 'INTEGRA' && a.destino == n.clave).length;
    final compartidos = aristas.where((a) => a.tipo == 'COMPARTIDO_EN' && a.destino == n.clave).length;
    return [
      Text(d['activo'] == false ? 'Grupo cerrado' : 'Grupo activo', style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(
        '$miembros ${miembros == 1 ? 'miembro' : 'miembros'} y $compartidos '
        '${compartidos == 1 ? 'reporte compartido' : 'reportes compartidos'} en esta vista'
        '${d['radio'] != null ? ' · área de ${d['radio']} m' : ''}.',
        style: const TextStyle(color: RBColores.texto2, height: 1.4),
      ),
      const SizedBox(height: 4),
      const Text(
        'Usa «Ampliar sus conexiones» para ver todos sus miembros y reportes.',
        style: TextStyle(fontSize: 12.5, color: RBColores.texto2),
      ),
      const SizedBox(height: 8),
    ];
  }

  List<Widget> _accionesModeracion(NodoGrafo n) {
    if (n.tipo == 'Usuario' && n.datos['es_admin'] != true) {
      final suspendido = n.estado == 'SUSPENDIDO';
      return [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: suspendido ? RBColores.verde : RBColores.rojo),
          onPressed: () => alCambiarCuenta(n),
          icon: Icon(suspendido ? Icons.lock_open_rounded : Icons.block_rounded, size: 18),
          label: Text(suspendido ? 'Reactivar cuenta' : 'Suspender cuenta'),
        ),
      ];
    }
    if (n.tipo == 'Reporte' && n.estado != 'DESCARTADO') {
      return [_botonRojo('Descartar reporte', () => alDescartarReporte(n))];
    }
    if (n.tipo == 'Coordinacion') {
      final grupo = _grupoDe(n);
      if (grupo == null) return const [];
      return [_botonRojo('Suspender el grupo', () => alSuspenderGrupo(grupo))];
    }
    if (n.tipo == 'Incidente') {
      return [BotonesIncidenteRed(idIncidente: n.id, alModerar: alModerarIncidente)];
    }
    return const [];
  }

  Widget _botonRojo(String texto, VoidCallback alTocar) => FilledButton.icon(
    style: FilledButton.styleFrom(backgroundColor: RBColores.rojo),
    onPressed: alTocar,
    icon: const Icon(Icons.block_rounded, size: 18),
    label: Text(texto),
  );
}

/// Qué hacer cuando todavía no hay nada elegido.
class _Instrucciones extends StatelessWidget {
  const _Instrucciones();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        Icon(Icons.touch_app_outlined, size: 40, color: RBColores.placeholder),
        SizedBox(height: 12),
        Text(
          'Toca un elemento de la red',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: RBColores.tinta),
        ),
        SizedBox(height: 8),
        Text(
          'Verás qué es, por qué tiene ese color y lo que puedes hacer.\n\n'
          '• Doble toque: ampliar sus conexiones.\n'
          '• Rueda del mouse o dos dedos: acercar y alejar.\n'
          '• Arrastra el fondo para moverte.',
          style: TextStyle(fontSize: 14, height: 1.45, color: RBColores.texto2),
        ),
      ],
    );
  }
}

/// Botón de exploración del panel (ampliar, aislar, buscar camino).
class _AccionRed extends StatelessWidget {
  final IconData icono;
  final String texto;
  final VoidCallback alTocar;

  const _AccionRed(this.icono, this.texto, this.alTocar);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        onPressed: alTocar,
        icon: Icon(icono, size: 19),
        label: Text(texto),
      ),
    );
  }
}

/// Barra de 0 a 1 con su explicación (desglose de la reputación).
class _BarraPuntaje extends StatelessWidget {
  final String titulo;
  final double valor;
  final String explicacion;

  const _BarraPuntaje(this.titulo, this.valor, this.explicacion);

  @override
  Widget build(BuildContext context) {
    final color = colorPuntajeRed(valor * 100);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(titulo, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
              Text('${(valor * 100).round()}', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: valor, minHeight: 8, backgroundColor: RBColores.linea, color: color),
          ),
          const SizedBox(height: 3),
          Text(explicacion, style: const TextStyle(fontSize: 12.5, height: 1.35, color: RBColores.texto2)),
        ],
      ),
    );
  }
}

/// Una categoría dentro de un lugar: nombre, cuántos y una barra proporcional.
class _FilaCategoria extends StatelessWidget {
  final Map<String, dynamic> categoria;
  final int totalLugar;

  const _FilaCategoria(this.categoria, this.totalLugar);

  @override
  Widget build(BuildContext context) {
    final codigo = categoria.texto('codigo');
    final total = categoria.entero('total');
    final color = colorCategoria(codigo, colorHex: categoria.textoOpcional('color'));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(iconoCategoria(codigo), size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  categoria.texto('nombre', codigo),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Text('$total', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: totalLugar == 0 ? 0 : total / totalLugar,
              minHeight: 6,
              color: color,
              backgroundColor: RBColores.fondo,
            ),
          ),
        ],
      ),
    );
  }
}
