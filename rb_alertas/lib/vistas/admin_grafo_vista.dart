import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:rb_alertas/servicios/admin_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';

const _colorAzul = Color(0xFF0056D2);
const _colorTitulo = Color(0xFF111827);
const _colorTextoGris = Color(0xFF6B7280);
const _colorBorde = Color(0xFFE5E7EB);
const _colorVerde = Color(0xFF16A34A);
const _colorRojo = Color(0xFFDC2626);
const _colorAmbar = Color(0xFFF59E0B);

/// Color e ícono de cada tipo de nodo (los mismos de la leyenda).
const _estiloTipo = <String, (String, Color)>{
  'Usuario': ('Vecino', _colorAzul),
  'Reporte': ('Reporte', _colorAmbar),
  'Categoria': ('Categoría', Color(0xFF7C3AED)),
  'Comuna': ('Comuna', Color(0xFF0F766E)),
  'Localidad': ('Localidad', Color(0xFF14B8A6)),
  'ZonaSegura': ('Zona segura', Color(0xFFDB2777)),
};

Color _colorNodo(NodoGrafo nodo) {
  if (nodo.tipo == 'Reporte') {
    switch (nodo.datos['estado']) {
      case 'DESCARTADO':
        return _colorRojo;
      case 'RESUELTO':
        return _colorVerde;
      case 'EXPIRADO':
        return _colorTextoGris;
    }
  }
  if (nodo.tipo == 'Usuario' && nodo.datos['estado'] == 'SUSPENDIDO') {
    return _colorTitulo;
  }
  return _estiloTipo[nodo.tipo]?.$2 ?? _colorTextoGris;
}

Color _colorArista(AristaGrafo arista) {
  switch (arista.tipo) {
    case 'CONFIRMA_A':
      return _colorVerde;
    case 'DESMIENTE_A':
      return _colorRojo;
    case 'VOTO':
      return arista.datos['tipo'] == 'DESMIENTE' ? _colorRojo : _colorVerde;
    case 'ALERTO_A':
      return const Color(0xFFDB2777);
    case 'CREO':
      return _colorAzul;
    default:
      return const Color(0xFFB6BCC6);
  }
}

const _nombreRelacion = {
  'CREO': 'creó',
  'VOTO': 'votó',
  'ES_DE': 'es de',
  'OCURRIO_EN': 'ocurrió en',
  'PERTENECE_A': 'pertenece a',
  'TIENE_ZONA': 'tiene zona',
  'ALERTO_A': 'alertó a',
  'CONFIRMA_A': 'confirma a',
  'DESMIENTE_A': 'desmiente a',
};

/// Pestaña "Grafo" del panel: la red de Neo4j dibujada con una simulación de
/// fuerzas (los nodos se repelen y las relaciones los atraen como resortes).
class PestanaGrafo extends StatefulWidget {
  const PestanaGrafo({super.key});

  @override
  State<PestanaGrafo> createState() => _PestanaGrafoState();
}

class _PestanaGrafoState extends State<PestanaGrafo>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  static const _vistas = [
    ('general', 'Reportes recientes'),
    ('votos', 'Quién apoya a quién'),
    ('sospechosos', 'Sospechosos'),
  ];

  /// Tamaño del lienzo: más grande que la pantalla, se recorre con zoom y arrastre.
  static const _lienzo = Size(1400, 1400);

  final _servicio = AdminServicio();
  final _transformacion = TransformationController();
  late final Ticker _ticker;

  String _vista = 'general';
  GrafoAdmin? _grafo;
  NodoGrafo? _explorando;
  String? _error;
  bool _cargando = false;
  bool _sincronizando = false;

  /// Tamaño visible del área del grafo, para encuadrar el dibujo.
  Size _tamanoVista = Size.zero;

  final Map<String, Offset> _posiciones = {};
  final Map<String, Offset> _velocidades = {};
  final Map<String, int> _grados = {};
  int _pasosRestantes = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _paso());
    _cargar();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _transformacion.dispose();
    super.dispose();
  }

  Future<void> _cargar({NodoGrafo? desde}) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final token = Sesion.token ?? '';
      final grafo = desde == null
          ? await _servicio.grafo(token, _vista)
          : await _servicio.vecindario(token, desde);
      if (!mounted) return;
      setState(() {
        _grafo = grafo;
        _explorando = desde;
        _cargando = false;
      });
      _iniciarSimulacion(grafo, centro: desde?.clave);
    } on AdminServicioException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.mensaje;
          _cargando = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo conectar con el servidor';
          _cargando = false;
        });
      }
    }
  }

  Future<void> _sincronizar() async {
    setState(() => _sincronizando = true);
    try {
      await _servicio.sincronizarGrafo(Sesion.token ?? '');
      if (!mounted) return;
      _avisar('Grafo actualizado con los datos de ahora');
      await _cargar(desde: _explorando);
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
  // Simulación de fuerzas (Fruchterman-Reingold simplificado)

  void _iniciarSimulacion(GrafoAdmin grafo, {String? centro}) {
    final aleatorio = math.Random(7);
    final medio = Offset(_lienzo.width / 2, _lienzo.height / 2);
    final anteriores = Map.of(_posiciones);
    _posiciones.clear();
    _velocidades.clear();
    _grados.clear();
    for (final a in grafo.aristas) {
      _grados[a.origen] = (_grados[a.origen] ?? 0) + 1;
      _grados[a.destino] = (_grados[a.destino] ?? 0) + 1;
    }
    for (final (i, nodo) in grafo.nodos.indexed) {
      // Los nodos que ya estaban en pantalla parten donde estaban: al explorar
      // un vecindario el dibujo no salta de golpe.
      final angulo = i * 2.4;
      final radio = 60.0 + 14 * math.sqrt(i) + aleatorio.nextDouble() * 20;
      _posiciones[nodo.clave] = nodo.clave == centro
          ? medio
          : anteriores[nodo.clave] ??
                medio + Offset(math.cos(angulo), math.sin(angulo)) * radio;
      _velocidades[nodo.clave] = Offset.zero;
    }
    _pasosRestantes = 260;
    if (!_ticker.isActive) _ticker.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _encuadrar());
  }

  void _paso() {
    final grafo = _grafo;
    if (grafo == null || _pasosRestantes <= 0) {
      _ticker.stop();
      _encuadrar();
      return;
    }
    final n = grafo.nodos.length;
    final k = 45.0 + 160 / math.sqrt(n + 1);
    final enfriamiento = _pasosRestantes / 260;
    final medio = Offset(_lienzo.width / 2, _lienzo.height / 2);
    final fuerzas = {for (final nodo in grafo.nodos) nodo.clave: Offset.zero};

    final claves = fuerzas.keys.toList();
    for (var i = 0; i < claves.length; i++) {
      for (var j = i + 1; j < claves.length; j++) {
        final delta = _posiciones[claves[i]]! - _posiciones[claves[j]]!;
        final distancia = math.max(delta.distance, 1.0);
        final empuje = delta / distancia * (k * k / distancia);
        fuerzas[claves[i]] = fuerzas[claves[i]]! + empuje;
        fuerzas[claves[j]] = fuerzas[claves[j]]! - empuje;
      }
    }
    for (final a in grafo.aristas) {
      final pa = _posiciones[a.origen], pb = _posiciones[a.destino];
      if (pa == null || pb == null) continue;
      final delta = pb - pa;
      final distancia = math.max(delta.distance, 1.0);
      final tiron = delta / distancia * (distancia * distancia / k) * 0.5;
      fuerzas[a.origen] = fuerzas[a.origen]! + tiron;
      fuerzas[a.destino] = fuerzas[a.destino]! - tiron;
    }

    for (final clave in claves) {
      // Leve gravedad hacia el centro para que los grupos sueltos no se alejen.
      final fuerza = fuerzas[clave]! + (medio - _posiciones[clave]!) * 0.04;
      var velocidad = (_velocidades[clave]! + fuerza * 0.05) * 0.6;
      final tope = 30 * enfriamiento + 1;
      if (velocidad.distance > tope) {
        velocidad = velocidad / velocidad.distance * tope;
      }
      _velocidades[clave] = velocidad;
      final p = _posiciones[clave]! + velocidad;
      _posiciones[clave] = Offset(
        p.dx.clamp(30, _lienzo.width - 30),
        p.dy.clamp(30, _lienzo.height - 30),
      );
    }
    _pasosRestantes--;
    // Mientras se acomoda, la cámara lo sigue para que no quede nada fuera de la pantalla.
    if (_pasosRestantes % 20 == 0) _encuadrar();
    setState(() {});
  }

  double _radio(String clave) =>
      10 + math.min(14, math.sqrt((_grados[clave] ?? 0).toDouble()) * 3);

  /// Ajusta el zoom para que todos los nodos (con sus nombres) queden a la vista.
  void _encuadrar() {
    if (!mounted || _posiciones.isEmpty || _tamanoVista.isEmpty) return;
    var caja = Rect.fromPoints(
      _posiciones.values.first,
      _posiciones.values.first,
    );
    for (final p in _posiciones.values) {
      caja = caja.expandToInclude(Rect.fromCircle(center: p, radius: 1));
    }
    caja = caja.inflate(60);
    final escala = math
        .min(_tamanoVista.width / caja.width, _tamanoVista.height / caja.height)
        .clamp(0.2, 1.6);
    final centro = caja.center;
    _transformacion.value = Matrix4.identity()
      ..translateByDouble(
        _tamanoVista.width / 2 - centro.dx * escala,
        _tamanoVista.height / 2 - centro.dy * escala,
        0,
        1,
      )
      ..scaleByDouble(escala, escala, 1, 1);
  }

  void _tocar(Offset punto) {
    final grafo = _grafo;
    if (grafo == null) return;
    NodoGrafo? elegido;
    var menor = double.infinity;
    for (final nodo in grafo.nodos) {
      final distancia = (_posiciones[nodo.clave]! - punto).distance;
      if (distancia < _radio(nodo.clave) + 10 && distancia < menor) {
        elegido = nodo;
        menor = distancia;
      }
    }
    if (elegido != null) _mostrarDetalle(elegido);
  }

  // ---------------------------------------------------------------------------
  // Detalle de un nodo

  Future<void> _mostrarDetalle(NodoGrafo nodo) async {
    final grafo = _grafo!;
    final conexiones = grafo.aristas
        .where((a) => a.origen == nodo.clave || a.destino == nodo.clave)
        .length;
    final datos = nodo.datos;
    final lineas = <String>[
      if (datos['estado'] != null) 'Estado: ${datos['estado']}',
      if (nodo.tipo == 'Reporte' && datos['descripcion'] != null)
        '«${datos['descripcion']}»',
      if (nodo.tipo == 'Reporte')
        '${datos['confirmaciones'] ?? 0} confirman · ${datos['desmentidos'] ?? 0} desmienten',
      if (datos['fecha_creacion'] != null)
        'Desde ${datos['fecha_creacion'].toString().split('T').first}',
      if (nodo.tipo == 'ZonaSegura' && datos['radio'] != null)
        'Radio: ${datos['radio']} m',
      '$conexiones conexiones en esta vista',
    ];

    final accion = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 7, backgroundColor: _colorNodo(nodo)),
                  const SizedBox(width: 8),
                  Text(
                    _estiloTipo[nodo.tipo]?.$1 ?? nodo.tipo,
                    style: const TextStyle(color: _colorTextoGris),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                nodo.etiqueta,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: _colorTitulo,
                ),
              ),
              const SizedBox(height: 8),
              for (final linea in lineas)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    linea,
                    style: const TextStyle(fontSize: 13.5, color: _colorTitulo),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _colorAzul),
                onPressed: () => Navigator.pop(context, 'explorar'),
                icon: const Icon(Icons.hub_outlined, size: 18),
                label: const Text('Explorar sus conexiones'),
              ),
              if (nodo.tipo == 'Usuario' && datos['es_admin'] != true) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, 'cuenta'),
                  child: Text(
                    datos['estado'] == 'SUSPENDIDO'
                        ? 'Reactivar cuenta'
                        : 'Suspender cuenta',
                    style: TextStyle(
                      color: datos['estado'] == 'SUSPENDIDO'
                          ? _colorVerde
                          : _colorRojo,
                    ),
                  ),
                ),
              ],
              if (nodo.tipo == 'Reporte' &&
                  datos['estado'] != 'DESCARTADO') ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, 'descartar'),
                  child: const Text(
                    'Descartar reporte',
                    style: TextStyle(color: _colorRojo),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (!mounted || accion == null) return;
    final token = Sesion.token ?? '';
    try {
      switch (accion) {
        case 'explorar':
          await _cargar(desde: nodo);
          return;
        case 'cuenta':
          final suspender = datos['estado'] != 'SUSPENDIDO';
          if (!await _confirmar(
            suspender
                ? 'Suspender a ${nodo.etiqueta}'
                : 'Reactivar a ${nodo.etiqueta}',
            suspender
                ? 'No podrá entrar a la app y se cerrarán sus sesiones.'
                : 'Podrá volver a entrar a la app.',
          )) {
            return;
          }
          await _servicio.cambiarEstadoUsuario(
            token,
            nodo.id,
            suspender ? 'SUSPENDIDO' : 'ACTIVO',
          );
          _avisar(suspender ? 'Cuenta suspendida' : 'Cuenta reactivada');
        case 'descartar':
          if (!await _confirmar(
            'Descartar reporte ${nodo.etiqueta}',
            'Dejará de mostrarse en el mapa.',
          )) {
            return;
          }
          await _servicio.cambiarEstadoReporte(
            token,
            nodo.id,
            'DESCARTADO',
            motivo: 'Descartado desde el grafo',
          );
          _avisar('Reporte ${nodo.etiqueta} descartado');
      }
      // El grafo se copia desde MySQL: se rehace para que muestre el cambio.
      await _sincronizar();
    } on AdminServicioException catch (e) {
      if (mounted) _avisar(e.mensaje);
    } catch (_) {
      if (mounted) _avisar('No se pudo conectar con el servidor');
    }
  }

  Future<bool> _confirmar(String titulo, String texto) async {
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
            style: FilledButton.styleFrom(backgroundColor: _colorRojo),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return respuesta == true;
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            children: [
              for (final (vista, etiqueta) in _vistas)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(etiqueta),
                    selected: _explorando == null && _vista == vista,
                    showCheckmark: false,
                    selectedColor: _colorAzul.withValues(alpha: 0.12),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _explorando == null && _vista == vista
                          ? _colorAzul
                          : _colorTextoGris,
                    ),
                    onSelected: (_) {
                      _vista = vista;
                      _cargar();
                    },
                  ),
                ),
              IconButton(
                tooltip: 'Actualizar con los datos de ahora',
                onPressed: _sincronizando ? null : _sincronizar,
                icon: _sincronizando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync, color: _colorAzul),
              ),
            ],
          ),
        ),
        if (_explorando != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Conexiones de ${_explorando!.etiqueta}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _colorTitulo,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _cargar(),
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Volver'),
                ),
              ],
            ),
          ),
        _hallazgos(),
        Expanded(child: _area()),
        _leyenda(),
      ],
    );
  }

  Widget _hallazgos() {
    final hallazgos = _grafo?.hallazgos ?? const [];
    if (_explorando != null || hallazgos.isEmpty) return const SizedBox();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final h in hallazgos.take(4))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.insights, size: 15, color: _colorAmbar),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      h,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: _colorTitulo,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _area() {
    final grafo = _grafo;
    if (_cargando && grafo == null) {
      return const Center(child: CircularProgressIndicator(color: _colorAzul));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hub_outlined, size: 40, color: _colorTextoGris),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _colorTextoGris),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _cargar(desde: _explorando),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    if (grafo == null || grafo.nodos.isEmpty) {
      return const Center(
        child: Text(
          'No hay datos para esta vista.',
          style: TextStyle(color: _colorTextoGris),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, restricciones) {
        _tamanoVista = restricciones.biggest;
        return _dibujo(grafo);
      },
    );
  }

  Widget _dibujo(GrafoAdmin grafo) {
    return ClipRect(
      child: Stack(
        children: [
          InteractiveViewer(
            transformationController: _transformacion,
            constrained: false,
            minScale: 0.2,
            maxScale: 3,
            boundaryMargin: const EdgeInsets.all(400),
            child: GestureDetector(
              onTapUp: (detalle) => _tocar(detalle.localPosition),
              child: CustomPaint(
                size: _lienzo,
                painter: _PintorGrafo(
                  grafo: grafo,
                  posiciones: _posiciones,
                  radio: _radio,
                  resaltado: _explorando?.clave,
                ),
              ),
            ),
          ),
          if (_cargando)
            const Positioned(
              top: 8,
              right: 8,
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          Positioned(
            left: 12,
            bottom: 8,
            child: Text(
              '${grafo.nodos.length} nodos · ${grafo.aristas.length} relaciones'
              '${grafo.sincronizadoEn != null ? ' · datos de ${grafo.sincronizadoEn!.replaceFirst('T', ' ').substring(0, 16)}' : ''}',
              style: const TextStyle(fontSize: 11, color: _colorTextoGris),
            ),
          ),
        ],
      ),
    );
  }

  Widget _leyenda() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _colorBorde)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final (nombre, color) in _estiloTipo.values)
            _itemLeyenda(color, nombre),
          _itemLeyenda(_colorRojo, 'Descartado / desmiente'),
          _itemLeyenda(_colorVerde, 'Resuelto / confirma'),
        ],
      ),
    );
  }

  Widget _itemLeyenda(Color color, String texto) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CircleAvatar(radius: 5, backgroundColor: color),
      const SizedBox(width: 4),
      Text(texto, style: const TextStyle(fontSize: 11, color: _colorTextoGris)),
    ],
  );
}

class _PintorGrafo extends CustomPainter {
  final GrafoAdmin grafo;
  final Map<String, Offset> posiciones;
  final double Function(String clave) radio;
  final String? resaltado;

  _PintorGrafo({
    required this.grafo,
    required this.posiciones,
    required this.radio,
    required this.resaltado,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linea = Paint()
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final relleno = Paint();

    for (final a in grafo.aristas) {
      final pa = posiciones[a.origen], pb = posiciones[a.destino];
      if (pa == null || pb == null) continue;
      linea.color = _colorArista(a).withValues(alpha: 0.65);
      final delta = pb - pa;
      final distancia = delta.distance;
      if (distancia < 1) continue;
      final unidad = delta / distancia;
      // La línea termina en el borde del nodo de destino, con una punta de flecha.
      final fin = pb - unidad * (radio(a.destino) + 2);
      canvas.drawLine(pa, fin, linea);
      final normal = Offset(-unidad.dy, unidad.dx);
      final punta = Path()
        ..moveTo(fin.dx, fin.dy)
        ..lineTo(
          (fin - unidad * 9 + normal * 4).dx,
          (fin - unidad * 9 + normal * 4).dy,
        )
        ..lineTo(
          (fin - unidad * 9 - normal * 4).dx,
          (fin - unidad * 9 - normal * 4).dy,
        )
        ..close();
      relleno.color = linea.color;
      canvas.drawPath(punta, relleno);
    }

    for (final nodo in grafo.nodos) {
      final p = posiciones[nodo.clave];
      if (p == null) continue;
      final r = radio(nodo.clave);
      relleno.color = _colorNodo(nodo);
      canvas.drawCircle(p, r, relleno);
      canvas.drawCircle(
        p,
        r,
        Paint()
          ..color = nodo.clave == resaltado ? _colorTitulo : Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = nodo.clave == resaltado ? 3 : 2,
      );
      final texto = TextPainter(
        text: TextSpan(
          text: nodo.etiqueta,
          style: TextStyle(
            fontSize: nodo.tipo == 'Reporte' ? 10 : 11.5,
            fontWeight: nodo.tipo == 'Reporte'
                ? FontWeight.w500
                : FontWeight.w700,
            color: _colorTitulo,
            backgroundColor: Colors.white.withValues(alpha: 0.75),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 140);
      texto.paint(canvas, p + Offset(-texto.width / 2, r + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _PintorGrafo viejo) => true;
}

/// Texto de una relación para mostrarlo en pantalla (p. ej. "CREO" -> "creó").
String nombreRelacion(String tipo) => _nombreRelacion[tipo] ?? tipo;
