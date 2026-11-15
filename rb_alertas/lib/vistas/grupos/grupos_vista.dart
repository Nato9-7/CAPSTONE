import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/grupo.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/servicios/grupos_servicio.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/grupos/grupo_detalle_vista.dart';
import 'package:rb_alertas/vistas/grupos/grupo_formulario_vista.dart';
import 'package:rb_alertas/vistas/grupos/widgets/fila_grupo.dart';
import 'package:rb_alertas/vistas/grupos/widgets/unirse_grupo_hoja.dart';
import 'package:rb_alertas/widgets/barra_navegacion_inferior.dart';
import 'package:rb_alertas/widgets/dialogos.dart';
import 'package:rb_alertas/widgets/editor_area.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Pestaña Grupos: los grupos vecinales del usuario, crear uno o unirse con
/// el código que comparte el administrador.
class GruposVista extends StatefulWidget {
  const GruposVista({super.key});

  @override
  State<GruposVista> createState() => _GruposVistaState();
}

class _GruposVistaState extends State<GruposVista> {
  final _servicio = GruposServicio();
  MisGrupos? _datos;
  String? _error;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (!Sesion.activa) {
      setState(() => _cargando = false);
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

  Future<void> _abrirGrupo(Grupo grupo) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GrupoDetalleVista(idGrupo: grupo.id, grupoInicial: grupo)),
    );
    // Al volver puede haber salido, eliminado o editado el grupo.
    if (mounted) _cargar();
  }

  Future<void> _crearGrupo() async {
    final datos = _datos;
    if (datos == null) return;
    // El botón nunca se oculta: si no puede crear, se explica el motivo.
    if (!datos.puedeCrear) {
      mostrarAviso(
        context,
        datos.administraUno
            ? 'Ya administras un grupo. Por ahora cada vecino puede crear uno.'
            : 'Ya estás en ${datos.maximo} grupos. Sal de uno para crear otro.',
      );
      return;
    }
    final grupo = await GrupoFormularioVista.abrir(context, radiosPermitidos: datos.radiosPermitidos);
    if (grupo != null && mounted) _abrirGrupo(grupo);
  }

  Future<void> _unirse() async {
    final grupo = await UnirseGrupoHoja.abrir(context);
    if (grupo != null && mounted) _abrirGrupo(grupo);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RBColores.fondo,
      body: SafeArea(bottom: false, child: _cuerpo()),
      bottomNavigationBar: const BarraNavegacionInferior(seccionActiva: SeccionApp.grupos),
    );
  }

  Widget _encabezado() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Align(alignment: Alignment.centerLeft, child: TituloPantalla('Grupos')),
    );
  }

  /// Encabezado arriba y [contenido] ocupando el resto (sin sesión, carga o error).
  Widget _conEncabezado(Widget contenido) =>
      Column(children: [_encabezado(), Expanded(child: contenido)]);

  Widget _cuerpo() {
    if (!Sesion.activa) {
      return _conEncabezado(
        const EstadoVacio(
          icono: Icons.groups_outlined,
          titulo: 'Inicia sesión para usar los grupos',
          detalle: 'Con una cuenta puedes crear el grupo de tu junta de vecinos '
              'o unirte con el código que te compartieron.',
        ),
      );
    }
    if (_cargando && _datos == null) {
      return _conEncabezado(const Center(child: CircularProgressIndicator()));
    }
    if (_error != null && _datos == null) {
      return _conEncabezado(
        EstadoVacio(
          icono: Icons.cloud_off_rounded,
          titulo: 'No se pudieron cargar tus grupos',
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
                  'Los reportes que tus vecinos compartan dentro del área del '
                  'grupo aparecen aquí, y te avisamos al instante.',
                  style: TextStyle(fontSize: 17, height: 1.45, color: RBColores.texto2),
                ),
                const SizedBox(height: 18),
                if (datos.grupos.isEmpty) ...[
                  const _TarjetaBienvenida(),
                  const SizedBox(height: 22),
                ] else ...[
                  const EtiquetaSeccion('Mis grupos'),
                  const SizedBox(height: 12),
                  for (final grupo in datos.grupos) FilaGrupo(grupo: grupo, onTap: () => _abrirGrupo(grupo)),
                  const SizedBox(height: 10),
                ],
                _botonUnirse(),
                const SizedBox(height: 12),
                BotonAgregarArea(texto: 'Crear grupo', habilitado: datos.puedeCrear, onTap: _crearGrupo),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _botonUnirse() {
    return SizedBox(
      height: 60,
      child: ElevatedButton.icon(
        onPressed: _unirse,
        style: ElevatedButton.styleFrom(
          backgroundColor: RBColores.verde,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RBRadios.tarjeta)),
        ),
        icon: const Icon(Icons.vpn_key_outlined),
        label: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('Unirme con un código', style: TextStyle(fontSize: 18)),
        ),
      ),
    );
  }
}

/// Explicación que se ve mientras el usuario no está en ningún grupo.
class _TarjetaBienvenida extends StatelessWidget {
  const _TarjetaBienvenida();

  @override
  Widget build(BuildContext context) {
    return const TarjetaSuricata(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Grupos vecinales',
            style: TextStyle(
              fontFamily: RBFuentes.titulos,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Únete con el código que te compartió tu junta de vecinos, o crea '
            'el grupo de tu pasaje, edificio o parcelación.',
            style: TextStyle(fontSize: 15, height: 1.4, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
