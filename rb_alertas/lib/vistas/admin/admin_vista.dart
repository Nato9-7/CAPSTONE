import 'package:flutter/material.dart';
import 'package:rb_alertas/servicios/perfil_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/admin/analisis/seccion_analisis.dart';
import 'package:rb_alertas/vistas/admin/moderacion_reporte.dart';
import 'package:rb_alertas/vistas/admin/pestana_denuncias.dart';
import 'package:rb_alertas/vistas/admin/pestana_grupos.dart';
import 'package:rb_alertas/vistas/admin/pestana_reportes.dart';
import 'package:rb_alertas/vistas/admin/pestana_resumen.dart';
import 'package:rb_alertas/vistas/admin/pestana_usuarios.dart';
import 'package:rb_alertas/vistas/mapa/mapa_vista.dart';
import 'package:rb_alertas/widgets/dialogos.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Una sección del panel.
typedef _Seccion = ({String nombre, IconData icono, IconData iconoActivo});

/// Panel de administración: es la única pantalla de la cuenta admin (el login
/// la abre en vez del mapa). La API vuelve a comprobarlo en cada ruta /api/admin.
///
/// - Computador (≥ 1000 px): menú lateral con todas las secciones.
/// - Celular: barra inferior con las 4 secciones de uso diario y "Más" para el
///   resto (Material recomienda 3 a 5 destinos; 7 pestañas no caben legibles).
class AdminVista extends StatefulWidget {
  const AdminVista({super.key});

  @override
  State<AdminVista> createState() => _AdminVistaState();
}

class _AdminVistaState extends State<AdminVista> {
  static const List<_Seccion> _secciones = [
    (nombre: 'Resumen', icono: Icons.dashboard_outlined, iconoActivo: Icons.dashboard_rounded),
    (nombre: 'Reportes', icono: Icons.report_outlined, iconoActivo: Icons.report_rounded),
    (nombre: 'Denuncias', icono: Icons.flag_outlined, iconoActivo: Icons.flag_rounded),
    (nombre: 'Análisis', icono: Icons.insights_outlined, iconoActivo: Icons.insights_rounded),
    (nombre: 'Mapa', icono: Icons.map_outlined, iconoActivo: Icons.map_rounded),
    (nombre: 'Usuarios', icono: Icons.people_outline_rounded, iconoActivo: Icons.people_rounded),
    (nombre: 'Grupos', icono: Icons.groups_outlined, iconoActivo: Icons.groups_rounded),
  ];

  static const _indiceReportes = 1;
  static const _indiceAnalisis = 3;
  static const _indiceMapa = 4;

  /// En el celular, las secciones desde esta van en "Más".
  static const _primerasEnMas = 4;

  int _indice = 0;

  /// Cambia cada vez que se entra al mapa, para que se recargue con lo moderado.
  int _versionMapa = 0;

  /// Para abrir Reportes en un estado desde otra sección (p. ej. el Resumen).
  final _estadoReportes = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _estadoReportes.dispose();
    super.dispose();
  }

  List<Widget> get _paginas => [
    PestanaResumen(
      alAbrirAnalisis: () => _ir(_indiceAnalisis),
      alAbrirPendientes: () {
        _estadoReportes.value = null; // fuerza el aviso aunque ya estuviera en PENDIENTE
        _estadoReportes.value = 'PENDIENTE';
        _ir(_indiceReportes);
      },
    ),
    PestanaReportes(estadoSolicitado: _estadoReportes),
    const PestanaDenuncias(),
    const SeccionAnalisis(),
    MapaVista(key: ValueKey(_versionMapa), alModerar: (idReporte) => abrirModeracion(context, idReporte)),
    const PestanaUsuarios(),
    const PestanaGrupos(),
  ];

  void _ir(int indice) {
    setState(() {
      if (indice == _indiceMapa && _indice != _indiceMapa) _versionMapa++;
      _indice = indice;
    });
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
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const MapaVista()), (ruta) => false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) => c.maxWidth >= 1000 ? _escritorio() : _movil());
  }

  Widget get _contenido => IndexedStack(index: _indice, children: _paginas);

  /// Computador: menú lateral fijo y el contenido a la derecha.
  Widget _escritorio() {
    return Scaffold(
      backgroundColor: RBColores.fondo,
      body: SafeArea(
        child: Row(
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
                            Text('Panel de administración', style: TextStyle(fontSize: 12.5, color: RBColores.texto2)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  for (final (i, s) in _secciones.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _ItemMenuLateral(seccion: s, activo: _indice == i, alTocar: () => _ir(i)),
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_indice != _indiceMapa)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                      child: _TituloSeccion(_secciones[_indice].nombre),
                    ),
                  Expanded(child: _contenido),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Celular: encabezado con el nombre de la sección y barra de navegación inferior.
  Widget _movil() {
    final enMas = _indice >= _primerasEnMas;
    return Scaffold(
      backgroundColor: RBColores.fondo,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleSpacing: 16,
        title: Row(
          children: [
            const AvatarSuricata(tamano: 34),
            const SizedBox(width: 10),
            Expanded(child: _TituloSeccion(_secciones[_indice].nombre, tamano: 20)),
          ],
        ),
      ),
      body: _contenido,
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: RBColores.azul50,
        height: 68,
        selectedIndex: enMas ? _primerasEnMas : _indice,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) => i == _primerasEnMas ? _abrirMas() : _ir(i),
        destinations: [
          for (final s in _secciones.take(_primerasEnMas))
            NavigationDestination(
              icon: Icon(s.icono, color: RBColores.texto2),
              selectedIcon: Icon(s.iconoActivo, color: RBColores.azul),
              label: s.nombre,
            ),
          NavigationDestination(
            icon: const Icon(Icons.menu_rounded, color: RBColores.texto2),
            selectedIcon: const Icon(Icons.menu_open_rounded, color: RBColores.azul),
            label: enMas ? _secciones[_indice].nombre : 'Más',
          ),
        ],
      ),
    );
  }

  /// Hoja con las secciones que no caben en la barra, más cerrar sesión.
  Future<void> _abrirMas() async {
    final elegido = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (hoja) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = _primerasEnMas; i < _secciones.length; i++)
              ListTile(
                leading: Icon(
                  _indice == i ? _secciones[i].iconoActivo : _secciones[i].icono,
                  color: _indice == i ? RBColores.azul : RBColores.texto2,
                ),
                title: Text(
                  _secciones[i].nombre,
                  style: TextStyle(
                    fontWeight: _indice == i ? FontWeight.w800 : FontWeight.w600,
                    color: _indice == i ? RBColores.azul : RBColores.tinta,
                  ),
                ),
                selected: _indice == i,
                onTap: () => Navigator.pop(hoja, i),
              ),
            const Divider(height: 1, color: RBColores.linea),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: RBColores.rojo),
              title: const Text(
                'Cerrar sesión',
                style: TextStyle(fontWeight: FontWeight.w600, color: RBColores.rojo),
              ),
              onTap: () => Navigator.pop(hoja, -1),
            ),
          ],
        ),
      ),
    );
    if (!mounted || elegido == null) return;
    if (elegido == -1) {
      _cerrarSesion();
    } else {
      _ir(elegido);
    }
  }
}

class _TituloSeccion extends StatelessWidget {
  final String texto;
  final double tamano;

  const _TituloSeccion(this.texto, {this.tamano = 24});

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      texto,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: RBFuentes.titulos,
        fontSize: tamano,
        fontWeight: FontWeight.w800,
        color: RBColores.azul,
      ),
    ),
  );
}

class _ItemMenuLateral extends StatelessWidget {
  final _Seccion seccion;
  final bool activo;
  final VoidCallback alTocar;

  const _ItemMenuLateral({required this.seccion, required this.activo, required this.alTocar});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: activo ? RBColores.azul50 : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: alTocar,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(
                activo ? seccion.iconoActivo : seccion.icono,
                size: 21,
                color: activo ? RBColores.azul : RBColores.texto2,
              ),
              const SizedBox(width: 12),
              Text(
                seccion.nombre,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: activo ? FontWeight.w800 : FontWeight.w600,
                  color: activo ? RBColores.azul : RBColores.tinta,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
