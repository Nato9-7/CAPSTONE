import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/lectura_json.dart';
import 'package:rb_alertas/modelos/modelos.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/utilidades/formato.dart';
import 'package:rb_alertas/vistas/admin/red/piezas_red.dart';
import 'package:rb_alertas/vistas/admin/red/textos_red.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Lo que encontró el análisis de la red, en cuatro secciones: cuentas
/// sospechosas, reputación, incidentes y zonas con más hechos.
/// Las listas en null se muestran cargando.
class PanelHallazgosRed extends StatelessWidget {
  final ResumenGrafo? resumen;

  /// Índice en [seccionesHallazgos].
  final int seccion;
  final List<GrupoSospechoso>? sospechosos;
  final List<VecinoReputacion>? reputacion;
  final bool reputacionAlta;
  final List<IncidenteGrafo>? incidentes;
  final List<NodoGrafo>? zonas;

  /// Chips de categoría que van arriba del ranking de zonas.
  final Widget filtroCategorias;

  final Future<void> Function() alRecargar;
  final ValueChanged<int> alElegirSeccion;
  final ValueChanged<bool> alOrdenarReputacion;
  final void Function(NodoGrafo nodo, {String? aviso}) alMostrarEnRed;
  final ValueChanged<GrupoSospechoso> alSuspenderGrupo;
  final void Function(int id, String estado) alModerarIncidente;

  const PanelHallazgosRed({
    super.key,
    required this.resumen,
    required this.seccion,
    required this.sospechosos,
    required this.reputacion,
    required this.reputacionAlta,
    required this.incidentes,
    required this.zonas,
    required this.filtroCategorias,
    required this.alRecargar,
    required this.alElegirSeccion,
    required this.alOrdenarReputacion,
    required this.alMostrarEnRed,
    required this.alSuspenderGrupo,
    required this.alModerarIncidente,
  });

  static const _iconos = [
    Icons.gpp_maybe_rounded,
    Icons.verified_user_rounded,
    Icons.layers_rounded,
    Icons.local_fire_department_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final r = resumen;
    final contadores = [r?.sospechosos, r?.bajaReputacion, r?.incidentesAbiertos, null];
    return Container(
      color: Colors.white,
      child: RefreshIndicator(
        onRefresh: alRecargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            const Text(
              'Hallazgos',
              style: TextStyle(fontFamily: RBFuentes.titulos, fontSize: 22, fontWeight: FontWeight.w800, color: RBColores.azul),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final (i, (nombre, _)) in seccionesHallazgos.indexed) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _BotonSeccion(
                      nombre: nombre,
                      icono: _iconos[i],
                      contador: contadores[i],
                      activa: seccion == i,
                      // Los incidentes no son una alerta: su contador va en azul.
                      colorContador: i == 2 ? RBColores.azul : RBColores.rojo,
                      alTocar: () => alElegirSeccion(i),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(
              seccionesHallazgos[seccion].$2,
              style: const TextStyle(fontSize: 13.5, height: 1.4, color: RBColores.texto2),
            ),
            const SizedBox(height: 12),
            ...switch (seccion) {
              0 => _listaSospechosos(context),
              1 => _listaReputacion(),
              2 => _listaIncidentes(),
              _ => _listaZonas(),
            },
          ],
        ),
      ),
    );
  }

  List<Widget> _listaSospechosos(BuildContext context) {
    final grupos = sospechosos;
    if (grupos == null) return const [_Cargando()];
    if (grupos.isEmpty) return const [_SinHallazgos('No hay cuentas que se confirmen entre ellas.')];
    return [
      for (final g in grupos)
        TarjetaRB(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          colorBorde: g.nivel == 'ALTO' ? RBColores.rojo : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.gpp_maybe_rounded, color: RBColores.rojo),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${g.miembros.length} cuentas coordinadas',
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    g.nivel == 'ALTO' ? 'Sospecha alta' : 'Sospecha media',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: g.nivel == 'ALTO' ? RBColores.rojo : RBColores.texto2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [for (final m in g.miembros) m.etiqueta].join(' · '),
                style: const TextStyle(fontSize: 13, color: RBColores.texto2),
              ),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: const Text('¿Por qué?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: RBColores.azul)),
                  children: [EvidenciaSospechosoRed(g)],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => alMostrarEnRed(g.nodo, aviso: 'Resaltado: el grupo y sus votos entre ellas'),
                      icon: const Icon(Icons.hub_outlined, size: 18),
                      label: const Text('Ver en la red'),
                    ),
                  ),
                  if (g.miembros.any((m) => m.estado != 'SUSPENDIDO')) ...[
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Suspender el grupo',
                      style: IconButton.styleFrom(backgroundColor: RBColores.rojo),
                      onPressed: () => alSuspenderGrupo(g),
                      icon: const Icon(Icons.block_rounded),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _listaReputacion() {
    final vecinos = reputacion;
    return [
      Row(
        children: [
          ChipFiltro(etiqueta: 'Menos confiables', activo: !reputacionAlta, onTap: () => alOrdenarReputacion(false)),
          const SizedBox(width: 8),
          ChipFiltro(etiqueta: 'Más confiables', activo: reputacionAlta, onTap: () => alOrdenarReputacion(true)),
        ],
      ),
      const SizedBox(height: 10),
      if (vecinos == null)
        const _Cargando()
      else if (vecinos.isEmpty)
        const _SinHallazgos('Todavía no hay vecinos con reportes o votos.')
      else
        for (final v in vecinos) _TarjetaVecino(v, alTocar: () => alMostrarEnRed(v.nodo)),
    ];
  }

  List<Widget> _listaIncidentes() {
    final lista = incidentes;
    if (lista == null) return const [_Cargando()];
    if (lista.isEmpty) return const [_SinHallazgos('No hay incidentes abiertos con más de un reporte.')];
    return [
      for (final i in lista)
        TarjetaRB(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconoNodoRed(i.nodo, tamano: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i.categoria, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                        Text(
                          [
                            '${i.reportes.length} reportes',
                            if (i.lugar != null) i.lugar!,
                            if (i.ultimo != null) tiempoRelativoInicio(i.ultimo),
                          ].join(' · '),
                          style: const TextStyle(fontSize: 12.5, color: RBColores.texto2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _BotonVerEnRed(
                'Ver en la red',
                () => alMostrarEnRed(i.nodo, aviso: 'Resaltado: los reportes del mismo hecho'),
              ),
              BotonesIncidenteRed(idIncidente: i.id, alModerar: alModerarIncidente),
            ],
          ),
        ),
    ];
  }

  List<Widget> _listaZonas() {
    final lista = zonas;
    return [
      filtroCategorias,
      const SizedBox(height: 12),
      if (lista == null)
        const _Cargando()
      else if (lista.isEmpty)
        const _SinHallazgos('No hay reportes con lugar en este período.\nPrueba con otra categoría o un período más largo.')
      else
        for (final (posicion, z) in lista.indexed)
          _TarjetaZona(
            zona: z,
            posicion: posicion,
            alVerEnRed: () => alMostrarEnRed(z, aviso: 'Resaltado: ${z.etiqueta} y sus reportes'),
          ),
    ];
  }
}

/// Botón de sección con ícono, nombre y cuántos hallazgos tiene.
class _BotonSeccion extends StatelessWidget {
  final String nombre;
  final IconData icono;
  final int? contador;
  final bool activa;
  final Color colorContador;
  final VoidCallback alTocar;

  const _BotonSeccion({
    required this.nombre,
    required this.icono,
    required this.contador,
    required this.activa,
    required this.colorContador,
    required this.alTocar,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: activa ? RBColores.azul : RBColores.fondo,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: activa ? null : alTocar,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            children: [
              Icon(icono, size: 20, color: activa ? Colors.white : RBColores.azul),
              const SizedBox(height: 3),
              Text(
                nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: activa ? Colors.white : RBColores.tinta),
              ),
              if (contador != null && contador! > 0)
                Text(
                  '$contador',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: activa ? Colors.white : colorContador,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vecino con su puntaje en un anillo y un resumen de su actividad.
class _TarjetaVecino extends StatelessWidget {
  final VecinoReputacion vecino;
  final VoidCallback alTocar;

  const _TarjetaVecino(this.vecino, {required this.alTocar});

  @override
  Widget build(BuildContext context) {
    final v = vecino;
    return TarjetaRB(
      onTap: alTocar,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: v.puntaje / 100,
                  strokeWidth: 4.5,
                  backgroundColor: RBColores.linea,
                  color: colorPuntajeRed(v.puntaje),
                ),
                Text('${v.puntaje}', style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(v.nodo.etiqueta, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    if (v.sospechoso) ...[
                      const SizedBox(width: 4),
                      const Tooltip(
                        message: 'Está en un grupo sospechoso',
                        child: Icon(Icons.gpp_maybe_rounded, size: 16, color: RBColores.rojo),
                      ),
                    ],
                  ],
                ),
                Text(
                  '${v.reportes} reportes · ${v.confirmaciones} confirmaciones · '
                  '${v.descartados} descartados',
                  style: const TextStyle(fontSize: 12.5, color: RBColores.texto2),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: RBColores.placeholder),
        ],
      ),
    );
  }
}

/// Un lugar del ranking "Dónde ocurre más": posición, total de hechos y sus
/// tres categorías más frecuentes.
class _TarjetaZona extends StatelessWidget {
  final NodoGrafo zona;
  final int posicion;
  final VoidCallback alVerEnRed;

  const _TarjetaZona({required this.zona, required this.posicion, required this.alVerEnRed});

  @override
  Widget build(BuildContext context) {
    final z = zona;
    final total = z.datos.entero('total');
    return TarjetaRB(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      colorBorde: posicion == 0 ? RBColores.rojo : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 26,
                child: Text(
                  '${posicion + 1}',
                  style: const TextStyle(
                    fontFamily: RBFuentes.titulos,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: RBColores.texto2,
                  ),
                ),
              ),
              IconoNodoRed(z, tamano: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(z.etiqueta, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                    if (z.datos['comuna'] != null)
                      Text('${z.datos['comuna']}', style: const TextStyle(fontSize: 12.5, color: RBColores.texto2)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$total',
                    style: const TextStyle(
                      fontFamily: RBFuentes.titulos,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: RBColores.rojo,
                    ),
                  ),
                  Text(
                    total == 1 ? 'hecho' : 'hechos',
                    style: const TextStyle(fontSize: 11.5, color: RBColores.texto2),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              for (final c in z.datos.lista('por_categoria', (c) => c).take(3))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      iconoCategoria(c.texto('codigo')),
                      size: 15,
                      color: colorCategoria(c.texto('codigo'), colorHex: c.textoOpcional('color')),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${etiquetaCortaCategoria(c.texto('codigo'), c.texto('nombre'))} ${c['total']}',
                      style: const TextStyle(fontSize: 12.5, color: RBColores.tinta),
                    ),
                  ],
                ),
            ],
          ),
          _BotonVerEnRed('Ver sus reportes en la red', alVerEnRed),
        ],
      ),
    );
  }
}

class _BotonVerEnRed extends StatelessWidget {
  final String texto;
  final VoidCallback alTocar;

  const _BotonVerEnRed(this.texto, this.alTocar);

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
      onPressed: alTocar,
      icon: const Icon(Icons.hub_outlined, size: 18),
      label: Text(texto),
    );
  }
}

class _SinHallazgos extends StatelessWidget {
  final String texto;

  const _SinHallazgos(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          const Icon(Icons.check_circle_outline_rounded, size: 36, color: RBColores.verde),
          const SizedBox(height: 8),
          Text(texto, textAlign: TextAlign.center, style: const TextStyle(color: RBColores.texto2)),
        ],
      ),
    );
  }
}

class _Cargando extends StatelessWidget {
  const _Cargando();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 30),
      child: Center(child: CircularProgressIndicator(color: RBColores.azul)),
    );
  }
}
