import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rb_alertas/servicios/admin_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/categoria_visual.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Color de las relaciones sin un significado propio.
const _colorLinea = RBColores.bordeCampo;

/// Nombre visible, ícono y color de cada tipo de elemento del grafo.
(String, IconData, Color) _estilo(NodoGrafo nodo) {
  switch (nodo.tipo) {
    case 'Usuario':
      return ('Vecino', Icons.person_rounded, RBColores.azul);
    case 'Reporte':
      final codigo = (nodo.datos['categoria_codigo'] ?? '').toString();
      return (
        'Reporte',
        iconoCategoria(codigo),
        colorCategoria(codigo, colorHex: nodo.datos['color']?.toString()),
      );
    case 'Categoria':
      final codigo = (nodo.datos['codigo'] ?? '').toString();
      return (
        'Categoría',
        iconoCategoria(codigo),
        colorCategoria(codigo, colorHex: nodo.datos['color']?.toString()),
      );
    case 'Comuna':
      return ('Comuna', Icons.location_city_rounded, RBColores.petroleo);
    case 'Localidad':
      return ('Localidad', Icons.place_rounded, RBColores.texto2);
    case 'ZonaSegura':
      return ('Zona segura', Icons.shield_rounded, RBColores.verde);
    default:
      return (nodo.tipo, Icons.circle, RBColores.placeholder);
  }
}

/// Texto de la relación vista desde el elemento en foco.
String _textoRelacion(AristaGrafo arista) {
  switch (arista.tipo) {
    case 'CREO':
      return 'creó';
    case 'VOTO':
      return arista.datos['tipo'] == 'DESMIENTE' ? 'desmintió' : 'confirmó';
    case 'ES_DE':
      return 'categoría';
    case 'OCURRIO_EN':
      return 'ocurrió en';
    case 'PERTENECE_A':
      return 'pertenece a';
    case 'TIENE_ZONA':
      return 'su zona';
    case 'ALERTO_A':
      return 'alertó a';
    default:
      return arista.tipo.toLowerCase();
  }
}

Color _colorRelacion(AristaGrafo arista) {
  switch (arista.tipo) {
    case 'VOTO':
      return arista.datos['tipo'] == 'DESMIENTE'
          ? RBColores.rojo
          : RBColores.verde;
    case 'CREO':
      return RBColores.azul;
    case 'ALERTO_A':
      return RBColores.petroleo;
    default:
      return _colorLinea;
  }
}

/// Ícono de un elemento como cuadrado redondeado de su color; las categorías
/// usan el mismo ícono que en el resto de la app.
Widget _iconoNodo(NodoGrafo nodo, double tamano) {
  if (nodo.tipo == 'Reporte' || nodo.tipo == 'Categoria') {
    final campo = nodo.tipo == 'Reporte' ? 'categoria_codigo' : 'codigo';
    return IconoCategoria(
      codigo: (nodo.datos[campo] ?? '').toString(),
      colorHex: nodo.datos['color']?.toString(),
      tamano: tamano,
    );
  }
  final (_, icono, color) = _estilo(nodo);
  return Container(
    width: tamano,
    height: tamano,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(tamano * 0.28),
    ),
    child: Icon(icono, color: Colors.white, size: tamano * 0.46),
  );
}

String _textoEstado(String? estado) => switch (estado) {
  'PENDIENTE' => 'Pendiente',
  'VALIDADO' => 'Validado',
  'RESUELTO' => 'Resuelto',
  'DESCARTADO' => 'Descartado',
  'EXPIRADO' => 'Expirado',
  'ACTIVO' => 'Cuenta activa',
  'SUSPENDIDO' => 'Cuenta suspendida',
  _ => estado ?? '',
};

/// Pestaña "Grafo" del panel. Empieza con los hallazgos y, al elegir un
/// elemento, lo pone al centro con sus conexiones en dos anillos (estilo
/// Neo4j Bloom). Tocar otro elemento lo trae al centro.
class PestanaGrafo extends StatefulWidget {
  const PestanaGrafo({super.key});

  @override
  State<PestanaGrafo> createState() => _PestanaGrafoState();
}

class _PestanaGrafoState extends State<PestanaGrafo>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  final _servicio = AdminServicio();
  late final AnimationController _animacion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  InicioGrafo? _inicio;
  FocoGrafo? _foco;
  final List<NodoGrafo> _rastro = [];
  String? _error;
  bool _cargando = false;
  bool _sincronizando = false;

  /// Posiciones relativas (−1 a 1) antes y después de cambiar de foco.
  Map<String, Offset> _desde = {};
  Map<String, Offset> _hacia = {};

  /// Para cada nodo del anillo 2, el nodo del anillo 1 junto al que se dibuja.
  Map<String, String> _padres = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargarInicio();
  }

  @override
  void dispose() {
    _animacion.dispose();
    super.dispose();
  }

  String get _token => Sesion.token ?? '';

  Future<void> _ejecutar(Future<void> Function() accion) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await accion();
    } on AdminServicioException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo conectar con el servidor');
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarInicio() => _ejecutar(() async {
    final inicio = await _servicio.inicioGrafo(_token);
    if (!mounted) return;
    setState(() {
      _inicio = inicio;
      _foco = null;
      _rastro.clear();
    });
  });

  Future<void> _enfocar(NodoGrafo nodo, {bool agregarAlRastro = true}) =>
      _ejecutar(() async {
        final foco = await _servicio.focoGrafo(_token, nodo);
        if (!mounted) return;
        final anterior = _posicionesActuales();
        setState(() {
          if (agregarAlRastro) {
            _rastro.removeWhere((n) => n.clave == nodo.clave);
            _rastro.add(foco.nodoFoco);
          }
          _foco = foco;
          _hacia = _distribuir(foco);
          // Lo que ya estaba en pantalla parte de donde estaba; lo nuevo,
          // desde el elemento que se tocó (que pasa a ser el centro).
          final origen = anterior[foco.foco] ?? Offset.zero;
          _desde = {
            for (final clave in _hacia.keys) clave: anterior[clave] ?? origen,
          };
        });
        _animacion.forward(from: 0);
      });

  void _volverA(int indice) {
    final nodo = _rastro[indice];
    _rastro.removeRange(indice + 1, _rastro.length);
    _enfocar(nodo, agregarAlRastro: false);
  }

  Future<void> _sincronizar() async {
    setState(() => _sincronizando = true);
    try {
      await _servicio.sincronizarGrafo(_token);
      if (!mounted) return;
      _avisar('Grafo actualizado con los datos de ahora');
      final foco = _foco;
      if (foco == null) {
        await _cargarInicio();
      } else {
        await _enfocar(foco.nodoFoco, agregarAlRastro: false);
      }
    } on AdminServicioException catch (e) {
      if (mounted) _avisar(e.mensaje);
    } catch (_) {
      if (mounted) _avisar('No se pudo conectar con el servidor');
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  void _avisar(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // ---------------------------------------------------------------------------
  // Distribución en anillos

  Map<String, Offset> _posicionesActuales() {
    final t = Curves.easeOutCubic.transform(_animacion.value);
    return {
      for (final clave in _hacia.keys)
        clave: Offset.lerp(_desde[clave] ?? _hacia[clave], _hacia[clave], t)!,
    };
  }

  /// Foco al centro, anillo 1 repartido en círculo (agrupado por relación) y
  /// cada nodo del anillo 2 cerca del nodo del anillo 1 que lo conecta.
  Map<String, Offset> _distribuir(FocoGrafo foco) {
    final posiciones = <String, Offset>{foco.foco: Offset.zero};
    _padres = {};
    final primeros = foco.nodos.where((n) => n.anillo == 1).toList();
    String relacionConFoco(NodoGrafo n) =>
        foco.aristas
            .where(
              (a) =>
                  (a.origen == foco.foco && a.destino == n.clave) ||
                  (a.destino == foco.foco && a.origen == n.clave),
            )
            .firstOrNull
            ?.tipo ??
        '';
    primeros.sort((a, b) {
      final ra = relacionConFoco(a), rb = relacionConFoco(b);
      if (ra != rb) return ra.compareTo(rb);
      if (a.tipo != b.tipo) return a.tipo.compareTo(b.tipo);
      return a.etiqueta.compareTo(b.etiqueta);
    });
    final paso = 2 * math.pi / math.max(primeros.length, 1);
    final angulos = <String, double>{};
    for (final (i, n) in primeros.indexed) {
      final angulo = -math.pi / 2 + i * paso;
      angulos[n.clave] = angulo;
      posiciones[n.clave] = Offset(math.cos(angulo), math.sin(angulo)) * 0.58;
    }

    final hijos = <String, List<NodoGrafo>>{};
    for (final n in foco.nodos.where((n) => n.anillo == 2)) {
      String? padre;
      for (final a in foco.aristas) {
        final otro = a.origen == n.clave
            ? a.destino
            : (a.destino == n.clave ? a.origen : null);
        if (otro != null && angulos.containsKey(otro)) {
          padre = otro;
          break;
        }
      }
      if (padre != null) {
        (hijos[padre] ??= []).add(n);
        _padres[n.clave] = padre;
      }
    }
    for (final MapEntry(key: padre, value: lista) in hijos.entries) {
      final abanico = math.min(paso * 0.9, 1.2);
      for (final (i, n) in lista.indexed) {
        final desfase = lista.length == 1
            ? 0.0
            : -abanico / 2 + abanico * i / (lista.length - 1);
        final angulo = angulos[padre]! + desfase;
        posiciones[n.clave] = Offset(math.cos(angulo), math.sin(angulo)) * 0.95;
      }
    }
    return posiciones;
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _barra(),
        Expanded(
          child: _error != null
              ? _mensajeError()
              : (_foco == null ? _vistaInicio() : _vistaFoco()),
        ),
      ],
    );
  }

  Widget _barra() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _miga(
                    'Inicio',
                    Icons.home_rounded,
                    activa: _foco == null,
                    alTocar: _cargarInicio,
                  ),
                  for (final (i, n) in _rastro.indexed) ...[
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: RBColores.placeholder,
                    ),
                    _miga(
                      n.etiqueta,
                      _estilo(n).$2,
                      activa: i == _rastro.length - 1,
                      alTocar: () => _volverA(i),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_cargando || _sincronizando)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: RBColores.azul,
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Actualizar con los datos de ahora',
              onPressed: _sincronizar,
              icon: const Icon(Icons.sync_rounded, color: RBColores.azul),
            ),
        ],
      ),
    );
  }

  Widget _miga(
    String texto,
    IconData icono, {
    required bool activa,
    required VoidCallback alTocar,
  }) {
    return Material(
      color: activa ? RBColores.azul : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: activa ? RBColores.azul : RBColores.linea),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: activa ? null : alTocar,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icono,
                size: 16,
                color: activa ? Colors.white : RBColores.azul,
              ),
              const SizedBox(width: 6),
              Text(
                texto,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: activa ? Colors.white : RBColores.tinta,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mensajeError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.hub_outlined,
              size: 44,
              color: RBColores.placeholder,
            ),
            const SizedBox(height: 10),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: RBColores.texto2),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                final foco = _foco;
                if (foco == null) {
                  _cargarInicio();
                } else {
                  _enfocar(foco.nodoFoco, agregarAlRastro: false);
                }
              },
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Inicio: hallazgos y puntos de partida

  Widget _vistaInicio() {
    final inicio = _inicio;
    if (inicio == null) {
      return const Center(
        child: CircularProgressIndicator(color: RBColores.azul),
      );
    }
    final vacio =
        inicio.reportes.isEmpty &&
        inicio.vecinos.isEmpty &&
        inicio.lugares.isEmpty;
    return RefreshIndicator(
      onRefresh: _cargarInicio,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text(
            'Explora cómo se conectan vecinos, reportes y lugares. '
            'Toca cualquier elemento para ponerlo al centro.',
            style: TextStyle(
              fontSize: 14.5,
              color: RBColores.texto2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          if (vacio)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'El grafo todavía no tiene datos. Toca ⟳ para copiarlos ahora.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: RBColores.texto2),
              ),
            ),
          if (inicio.hallazgos.isNotEmpty) ...[
            _tituloSeccion('Para revisar'),
            for (final h in inicio.hallazgos) _tarjetaHallazgo(h),
            const SizedBox(height: 20),
          ],
          if (inicio.reportes.isNotEmpty) ...[
            _tituloSeccion('Reportes recientes'),
            _filaNodos(inicio.reportes),
            const SizedBox(height: 20),
          ],
          if (inicio.vecinos.isNotEmpty) ...[
            _tituloSeccion('Vecinos más activos'),
            _filaNodos(inicio.vecinos),
            const SizedBox(height: 20),
          ],
          if (inicio.lugares.isNotEmpty) ...[
            _tituloSeccion('Lugares con más reportes'),
            _filaNodos(inicio.lugares),
          ],
          if (inicio.sincronizadoEn != null)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Text(
                'Datos copiados el '
                '${inicio.sincronizadoEn!.replaceFirst('T', ' a las ').substring(0, 21)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: RBColores.texto2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tituloSeccion(String texto) => Padding(
    padding: const EdgeInsets.only(bottom: 10, left: 4),
    child: EtiquetaSeccion(texto),
  );

  Widget _tarjetaHallazgo(HallazgoGrafo h) {
    final color = h.esAlerta ? RBColores.rojo : RBColores.azul;
    final fondo = h.esAlerta ? RBColores.rojo50 : RBColores.azul50;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: fondo,
        borderRadius: BorderRadius.circular(RBRadios.tarjeta),
        child: InkWell(
          borderRadius: BorderRadius.circular(RBRadios.tarjeta),
          onTap: () => _enfocar(h.nodo),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    h.esAlerta
                        ? Icons.warning_amber_rounded
                        : Icons.insights_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    h.texto,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: RBColores.tinta,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filaNodos(List<NodoGrafo> nodos) {
    return SizedBox(
      height: 124,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 6),
        itemCount: nodos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final n = nodos[i];
          final (tipo, _, _) = _estilo(n);
          final subtitulo =
              n.detalle ??
              (n.tipo == 'Reporte'
                  ? '${n.datos['categoria'] ?? ''}'
                  : _textoEstado(n.estado));
          return SizedBox(
            width: 128,
            child: TarjetaRB(
              onTap: () => _enfocar(n),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _iconoNodo(n, 36),
                  const Spacer(),
                  Text(
                    n.etiqueta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: RBColores.tinta,
                    ),
                  ),
                  Text(
                    subtitulo.isEmpty ? tipo : subtitulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: RBColores.texto2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Foco: el elemento al centro y sus anillos

  Widget _vistaFoco() {
    final foco = _foco!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, restricciones) => AnimatedBuilder(
              animation: _animacion,
              builder: (context, _) => _lienzo(foco, restricciones.biggest),
            ),
          ),
        ),
        _ficha(foco),
      ],
    );
  }

  Widget _lienzo(FocoGrafo foco, Size tamano) {
    final t = Curves.easeOutCubic.transform(_animacion.value);
    final escala = (math.min(tamano.width, tamano.height) / 420).clamp(
      0.75,
      1.3,
    );
    final medidas = {0: 66.0 * escala, 1: 44.0 * escala, 2: 30.0 * escala};
    // Radios del óvalo: se deja margen para el nodo y su nombre.
    final rx = tamano.width / 2 - 46 * escala;
    final ry = tamano.height / 2 - 40 * escala;
    final centro = Offset(tamano.width / 2, tamano.height / 2 - 6);

    Offset aPantalla(Offset relativa) =>
        centro + Offset(relativa.dx * rx, relativa.dy * ry);

    final posiciones = <String, Offset>{
      for (final clave in _hacia.keys)
        clave: aPantalla(
          Offset.lerp(_desde[clave] ?? _hacia[clave], _hacia[clave], t)!,
        ),
    };
    final nodos = [...foco.nodos.where((n) => posiciones.containsKey(n.clave))]
      ..sort((a, b) => b.anillo.compareTo(a.anillo));
    final primerAnillo = nodos.where((n) => n.anillo == 1).length;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _PintorRelaciones(
              foco: foco,
              posiciones: posiciones,
              centro: centro,
              radios: Offset(rx, ry),
              progreso: t,
              conTextos: primerAnillo <= 12,
              padres: _padres,
            ),
          ),
        ),
        for (final n in nodos)
          _burbuja(n, posiciones[n.clave]!, medidas[n.anillo] ?? 30, t),
        if (nodos.length == 1)
          const Align(
            alignment: Alignment(0, 0.6),
            child: Text(
              'No tiene conexiones todavía.',
              style: TextStyle(fontSize: 14.5, color: RBColores.texto2),
            ),
          ),
      ],
    );
  }

  Widget _burbuja(NodoGrafo n, Offset posicion, double tamano, double t) {
    final (_, icono, color) = _estilo(n);
    final esFoco = n.anillo == 0;
    final descartado = n.tipo == 'Reporte' && n.estado == 'DESCARTADO';
    final suspendido = n.tipo == 'Usuario' && n.estado == 'SUSPENDIDO';
    final borde = descartado
        ? RBColores.rojo
        : (suspendido ? RBColores.tinta : color);
    // Lo que entra nuevo aparece suave; lo que ya estaba se mantiene visible.
    final opacidad = _desde[n.clave] == _hacia[n.clave] || esFoco
        ? 1.0
        : (0.25 + 0.75 * t);
    final anchoTexto = esFoco ? 150.0 : 96.0;

    return Positioned(
      left: posicion.dx - anchoTexto / 2,
      top: posicion.dy - tamano / 2,
      width: anchoTexto,
      child: Opacity(
        opacity: opacidad.clamp(0, 1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: esFoco ? color : Colors.white,
              shape: CircleBorder(
                side: esFoco
                    ? BorderSide.none
                    : BorderSide(color: borde, width: 2.2),
              ),
              elevation: esFoco ? 6 : (n.anillo == 1 ? 2 : 0),
              shadowColor: color.withValues(alpha: 0.4),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: esFoco ? null : () => _enfocar(n),
                child: SizedBox(
                  width: tamano,
                  height: tamano,
                  child: Icon(
                    icono,
                    size: tamano * 0.5,
                    color: esFoco ? Colors.white : borde,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                n.etiqueta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: esFoco ? 13 : (n.anillo == 1 ? 11.5 : 10),
                  fontWeight: n.anillo == 2 ? FontWeight.w500 : FontWeight.w700,
                  color: n.anillo == 2 ? RBColores.texto2 : RBColores.tinta,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Ficha fija del elemento en foco, con sus acciones.
  Widget _ficha(FocoGrafo foco) {
    final n = foco.nodoFoco;
    final (tipo, icono, color) = _estilo(n);
    final directas = foco.nodos.where((x) => x.anillo == 1).length;
    final datos = n.datos;
    final lineas = <String>[
      if (n.tipo == 'Reporte' && datos['categoria'] != null)
        '${datos['categoria']}',
      if (n.tipo == 'Reporte' && datos['descripcion'] != null)
        '«${datos['descripcion']}»',
      if (n.tipo == 'Reporte')
        '${datos['confirmaciones'] ?? 0} confirman · '
            '${datos['desmentidos'] ?? 0} desmienten',
      if (n.tipo == 'ZonaSegura' && datos['radio'] != null)
        'Radio de ${datos['radio']} m',
      '$directas conexiones directas',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(RBRadios.hoja),
        ),
        boxShadow: [
          BoxShadow(
            color: RBColores.azul.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _iconoNodo(n, 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tipo.toUpperCase(), style: RBTexto.etiqueta),
                    const SizedBox(height: 2),
                    Text(
                      n.etiqueta,
                      style: const TextStyle(
                        fontFamily: RBFuentes.titulos,
                        fontSize: 21,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: RBColores.azul,
                      ),
                    ),
                  ],
                ),
              ),
              if (n.estado != null) _chipEstado(n),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            lineas.join('\n'),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              color: RBColores.tinta,
              height: 1.4,
            ),
          ),
          ..._acciones(n),
        ],
      ),
    );
  }

  /// Reportes con la píldora del sistema; cuentas en verde, azul o rojo.
  Widget _chipEstado(NodoGrafo n) {
    final estado = n.estado!;
    if (n.tipo == 'Reporte') {
      return ChipEstado(
        estado: EstadoVisual.desdeApi(estado),
        texto: _textoEstado(estado),
      );
    }
    final (fondo, color) = switch (estado) {
      'ACTIVO' => (RBColores.verde50, RBColores.verde),
      'PENDIENTE' => (RBColores.azul50, RBColores.azul),
      'SUSPENDIDO' || 'DESCARTADO' => (RBColores.rojo50, RBColores.rojo),
      _ => (RBColores.linea, RBColores.texto2),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _textoEstado(estado),
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  List<Widget> _acciones(NodoGrafo n) {
    final Widget boton;
    if (n.tipo == 'Usuario' && n.datos['es_admin'] != true) {
      final suspendido = n.estado == 'SUSPENDIDO';
      final color = suspendido ? RBColores.verde : RBColores.rojo;
      boton = OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color, width: 1.4),
        ),
        onPressed: () => _cambiarCuenta(n),
        icon: Icon(
          suspendido ? Icons.lock_open_rounded : Icons.block_rounded,
          size: 18,
        ),
        label: Text(suspendido ? 'Reactivar cuenta' : 'Suspender cuenta'),
      );
    } else if (n.tipo == 'Reporte' && n.estado != 'DESCARTADO') {
      boton = OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: RBColores.rojo,
          side: const BorderSide(color: RBColores.rojo, width: 1.4),
        ),
        onPressed: () => _descartar(n),
        icon: const Icon(Icons.block_rounded, size: 18),
        label: const Text('Descartar reporte'),
      );
    } else {
      return const [];
    }
    return [
      const SizedBox(height: 14),
      SizedBox(width: double.infinity, child: boton),
    ];
  }

  Future<void> _cambiarCuenta(NodoGrafo n) async {
    final suspender = n.estado != 'SUSPENDIDO';
    if (!await _confirmar(
      suspender ? 'Suspender a ${n.etiqueta}' : 'Reactivar a ${n.etiqueta}',
      suspender
          ? 'No podrá entrar a la app y se cerrarán sus sesiones.'
          : 'Podrá volver a entrar a la app.',
      color: suspender ? RBColores.rojo : RBColores.verde,
    )) {
      return;
    }
    await _aplicar(
      () => _servicio.cambiarEstadoUsuario(
        _token,
        n.id,
        suspender ? 'SUSPENDIDO' : 'ACTIVO',
      ),
      suspender ? 'Cuenta suspendida' : 'Cuenta reactivada',
    );
  }

  Future<void> _descartar(NodoGrafo n) async {
    if (!await _confirmar(
      'Descartar reporte ${n.etiqueta}',
      'Dejará de mostrarse en el mapa.',
    )) {
      return;
    }
    await _aplicar(
      () => _servicio.cambiarEstadoReporte(
        _token,
        n.id,
        'DESCARTADO',
        motivo: 'Descartado desde el grafo',
      ),
      'Reporte ${n.etiqueta} descartado',
    );
  }

  Future<void> _aplicar(Future<void> Function() accion, String exito) async {
    try {
      await accion();
      if (!mounted) return;
      _avisar(exito);
      // El grafo es una copia de MySQL: se rehace para que muestre el cambio.
      await _sincronizar();
    } on AdminServicioException catch (e) {
      if (mounted) _avisar(e.mensaje);
    } catch (_) {
      if (mounted) _avisar('No se pudo conectar con el servidor');
    }
  }

  Future<bool> _confirmar(
    String titulo,
    String texto, {
    Color color = RBColores.rojo,
  }) async {
    final respuesta = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return respuesta == true;
  }
}

/// Dibuja las guías de los anillos y las relaciones (con su texto en el anillo 1).
class _PintorRelaciones extends CustomPainter {
  final FocoGrafo foco;
  final Map<String, Offset> posiciones;
  final Offset centro;
  final Offset radios;
  final double progreso;
  final bool conTextos;
  final Map<String, String> padres;

  _PintorRelaciones({
    required this.foco,
    required this.posiciones,
    required this.centro,
    required this.radios,
    required this.progreso,
    required this.conTextos,
    required this.padres,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final guia = Paint()
      ..color = RBColores.azul.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final factor in [0.58, 0.95]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: centro,
          width: radios.dx * 2 * factor,
          height: radios.dy * 2 * factor,
        ),
        guia,
      );
    }

    final anillo = {for (final n in foco.nodos) n.clave: n.anillo};
    // Primero las del segundo anillo (más suaves) y encima las del foco.
    final aristas = [
      ...foco.aristas.where((a) => !_esDelFoco(a)),
      ...foco.aristas.where(_esDelFoco),
    ];
    for (final a in aristas) {
      final pa = posiciones[a.origen], pb = posiciones[a.destino];
      if (pa == null || pb == null) continue;
      final delFoco = _esDelFoco(a);
      // Uniones entre dos nodos del mismo anillo: se omiten para no enredar.
      if (!delFoco && anillo[a.origen] == anillo[a.destino]) continue;
      // Cada nodo de afuera se une solo con el del anillo 1 junto al que está:
      // así no cruzan líneas largas por todo el dibujo.
      if (!delFoco &&
          padres[a.origen] != a.destino &&
          padres[a.destino] != a.origen) {
        continue;
      }
      final color = _colorRelacion(a);
      canvas.drawLine(
        pa,
        pb,
        Paint()
          ..color = color.withValues(alpha: (delFoco ? 0.9 : 0.4) * progreso)
          ..strokeWidth = delFoco ? 2.2 : 1.3
          ..strokeCap = StrokeCap.round,
      );
      if (delFoco && conTextos && progreso > 0.6) {
        _textoEnLinea(
          canvas,
          _textoRelacion(a),
          Offset.lerp(
            a.origen == foco.foco ? pa : pb,
            a.origen == foco.foco ? pb : pa,
            0.42,
          )!,
          color,
        );
      }
    }
  }

  bool _esDelFoco(AristaGrafo a) =>
      a.origen == foco.foco || a.destino == foco.foco;

  void _textoEnLinea(Canvas canvas, String texto, Offset punto, Color color) {
    final pintor = TextPainter(
      text: TextSpan(
        text: texto,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color == _colorLinea ? RBColores.texto2 : color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final caja = Rect.fromCenter(
      center: punto,
      width: pintor.width + 10,
      height: pintor.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(caja, const Radius.circular(8)),
      Paint()..color = RBColores.fondo,
    );
    pintor.paint(canvas, caja.topLeft + const Offset(5, 2));
  }

  @override
  bool shouldRepaint(covariant _PintorRelaciones viejo) => true;
}
