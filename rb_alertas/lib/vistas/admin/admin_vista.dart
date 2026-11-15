import 'package:flutter/material.dart';
import 'package:rb_alertas/servicios/perfil_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/admin/moderacion_reporte.dart';
import 'package:rb_alertas/vistas/admin/pestana_denuncias.dart';
import 'package:rb_alertas/vistas/admin/pestana_grupos.dart';
import 'package:rb_alertas/vistas/admin/pestana_reportes.dart';
import 'package:rb_alertas/vistas/admin/pestana_resumen.dart';
import 'package:rb_alertas/vistas/admin/pestana_usuarios.dart';
import 'package:rb_alertas/vistas/admin/red/seccion_red.dart';
import 'package:rb_alertas/vistas/mapa/mapa_vista.dart';
import 'package:rb_alertas/widgets/dialogos.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Panel de administración: es la única pantalla de la cuenta admin (el login
/// la abre en vez del mapa). La API vuelve a comprobarlo en cada ruta /api/admin.
///
/// En pantallas anchas (computador) usa un menú lateral; en el celular, pestañas.
class AdminVista extends StatefulWidget {
  const AdminVista({super.key});

  @override
  State<AdminVista> createState() => _AdminVistaState();
}

class _AdminVistaState extends State<AdminVista> with SingleTickerProviderStateMixin {
  static const _secciones = [
    ('Resumen', Icons.dashboard_outlined, Icons.dashboard_rounded),
    ('Mapa', Icons.map_outlined, Icons.map_rounded),
    ('Reportes', Icons.report_outlined, Icons.report_rounded),
    ('Denuncias', Icons.flag_outlined, Icons.flag_rounded),
    ('Usuarios', Icons.people_outline_rounded, Icons.people_rounded),
    ('Grupos', Icons.groups_outlined, Icons.groups_rounded),
    ('Red', Icons.hub_outlined, Icons.hub_rounded),
  ];

  static const _indiceMapa = 1;
  static const _indiceRed = 6;

  late final TabController _pestanas = TabController(length: _secciones.length, vsync: this)
    ..addListener(() {
      if (_indice != _pestanas.index) _cambiar(_pestanas.index);
    });
  int _indice = 0;

  /// Cambia cada vez que se entra al mapa, para que se recargue con lo moderado.
  int _versionMapa = 0;

  List<Widget> get _paginas => [
    PestanaResumen(alAbrirRed: () => _ir(_indiceRed)),
    MapaVista(
      key: ValueKey(_versionMapa),
      alModerar: (idReporte) => abrirModeracion(context, idReporte),
    ),
    const PestanaReportes(),
    const PestanaDenuncias(),
    const PestanaUsuarios(),
    const PestanaGrupos(),
    const SeccionRed(),
  ];

  @override
  void dispose() {
    _pestanas.dispose();
    super.dispose();
  }

  void _cambiar(int indice) {
    setState(() {
      if (indice == _indiceMapa && _indice != _indiceMapa) _versionMapa++;
      _indice = indice;
    });
  }

  void _ir(int indice) {
    _cambiar(indice);
    _pestanas.animateTo(indice);
  }

  Future<void> _cerrarSesion() async {
    final confirmado = await confirmar(
      context,
      titulo: 'Cerrar sesión',
      mensaje: '¿Quieres salir del panel de administración?',
      accion: 'Cerrar sesión',
    );
    if (!confirmado) return;
    await PerfilServicio().cerrarSesion();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const MapaVista()),
      (ruta) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RBColores.fondo,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 1000 ? _escritorio() : _movil(),
        ),
      ),
    );
  }

  /// Computador: menú lateral fijo y el contenido a la derecha.
  Widget _escritorio() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 236,
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  AvatarSuricata(tamano: 42),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MarcaRB(tamano: 20),
                        Text(
                          'Administración',
                          style: TextStyle(fontSize: 12.5, color: RBColores.texto2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              for (final (i, (nombre, icono, iconoActivo)) in _secciones.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Material(
                    color: _indice == i ? RBColores.azul50 : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _ir(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        child: Row(
                          children: [
                            Icon(
                              _indice == i ? iconoActivo : icono,
                              size: 21,
                              color: _indice == i ? RBColores.azul : RBColores.texto2,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              nombre,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: _indice == i ? FontWeight.w800 : FontWeight.w600,
                                color: _indice == i ? RBColores.azul : RBColores.tinta,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: RBColores.rojo,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onPressed: _cerrarSesion,
                icon: const Icon(Icons.logout_rounded, size: 20),
                label: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: RBColores.linea),
        Expanded(child: IndexedStack(index: _indice, children: _paginas)),
      ],
    );
  }

  /// Celular: encabezado con la marca y pestañas segmentadas.
  Widget _movil() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
          child: Row(
            children: [
              const AvatarSuricata(tamano: 46),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MarcaRB(tamano: 23),
                    SizedBox(height: 2),
                    Text(
                      'Panel de Administración',
                      style: TextStyle(fontSize: 13.5, color: RBColores.texto2),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cerrar sesión',
                icon: const Icon(Icons.logout_rounded, color: RBColores.rojo),
                onPressed: _cerrarSesion,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SelectorSegmentado(
            controlador: _pestanas,
            opciones: [for (final (nombre, _, _) in _secciones) nombre],
          ),
        ),
        const SizedBox(height: 8),
        // Sin deslizar entre pestañas: el gesto se confundiría con mover los mapas.
        Expanded(
          child: TabBarView(
            controller: _pestanas,
            physics: const NeverScrollableScrollPhysics(),
            children: _paginas,
          ),
        ),
      ],
    );
  }
}
