import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/zona_segura.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/servicios/zonas_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/zonas/widgets/fila_zona.dart';
import 'package:rb_alertas/vistas/zonas/widgets/mapa_zonas.dart';
import 'package:rb_alertas/vistas/zonas/zona_detalle_vista.dart';
import 'package:rb_alertas/widgets/barra_navegacion_inferior.dart';
import 'package:rb_alertas/widgets/dialogos.dart';
import 'package:rb_alertas/widgets/editor_area.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Lista de zonas seguras del usuario. Se entra desde Perfil.
class ZonasSegurasVista extends StatefulWidget {
  const ZonasSegurasVista({super.key});

  @override
  State<ZonasSegurasVista> createState() => _ZonasSegurasVistaState();
}

class _ZonasSegurasVistaState extends State<ZonasSegurasVista> {
  final _servicio = ZonasServicio();
  ZonasUsuario? _datos;
  String? _error;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (!Sesion.activa) {
      setState(() {
        _cargando = false;
        _error = 'Inicia sesión para configurar tus zonas seguras';
      });
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final datos = await _servicio.listar();
      if (!mounted) return;
      setState(() {
        _datos = datos;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = mensajeDeError(e);
      });
    }
  }

  /// Abre el editor. Con [zona] en null se crea una nueva.
  /// Si el editor devuelve true, algo cambió y hay que recargar la lista.
  Future<void> _abrirDetalle({ZonaSegura? zona}) async {
    final datos = _datos;
    if (datos == null) return;
    final cambio = await ZonaDetalleVista.abrir(
      context,
      zona: zona,
      radiosPermitidos: datos.radiosPermitidos,
    );
    if (cambio == true) _cargar();
  }

  void _avisarTope() {
    final maximo = _datos?.maximo ?? 3;
    mostrarAviso(context, 'Ya tienes $maximo zonas seguras. Elimina una para agregar otra.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RBColores.fondo,
      body: SafeArea(bottom: false, child: _cuerpo()),
      bottomNavigationBar: const BarraNavegacionInferior(seccionActiva: SeccionApp.perfil),
    );
  }

  Widget _encabezado() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 20, 16, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Volver',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded, size: 30, color: RBColores.tinta),
          ),
          const SizedBox(width: 6),
          const Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'Zonas seguras',
                style: TextStyle(
                  fontFamily: RBFuentes.titulos,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: RBColores.azul,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Encabezado arriba y [contenido] ocupando el resto (carga o error).
  Widget _conEncabezado(Widget contenido) =>
      Column(children: [_encabezado(), Expanded(child: contenido)]);

  Widget _cuerpo() {
    if (_cargando) return _conEncabezado(const Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return _conEncabezado(
        EstadoVacio(
          icono: Icons.cloud_off_rounded,
          titulo: 'No se pudieron cargar tus zonas',
          detalle: _error!,
          accion: 'Reintentar',
          onAccion: _cargar,
        ),
      );
    }

    final datos = _datos!;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _encabezado(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Te avisaremos cuando alguien reporte un incidente dentro '
                  'del radio de tus ubicaciones.',
                  style: TextStyle(fontSize: 17, height: 1.45, color: RBColores.texto2),
                ),
                const SizedBox(height: 18),
                MapaZonas(zonas: datos.zonas),
                const SizedBox(height: 26),
                const EtiquetaSeccion('Mis ubicaciones'),
                const SizedBox(height: 12),
                for (final zona in datos.zonas) FilaZona(zona: zona, onTap: () => _abrirDetalle(zona: zona)),
                if (datos.zonas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Aún no tienes zonas seguras. Agrega tu casa o tu trabajo '
                      'para recibir alertas de lo que pase cerca, aunque no estés ahí.',
                      style: TextStyle(fontSize: 15, height: 1.45, color: RBColores.texto2),
                    ),
                  ),
                const SizedBox(height: 4),
                BotonAgregarArea(
                  texto: 'Añadir ubicación',
                  habilitado: datos.puedeAgregar,
                  onTap: datos.puedeAgregar ? () => _abrirDetalle() : _avisarTope,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
