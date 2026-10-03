import 'package:flutter/material.dart';
import 'package:rb_alertas/servicios/sesion.dart';
import 'package:rb_alertas/servicios/zonas_servicio.dart';
import 'package:rb_alertas/vistas/zona_detalle_vista.dart';

/// Lista de zonas seguras del usuario. Se entra desde Perfil.
class ZonasSegurasVista extends StatefulWidget {
  const ZonasSegurasVista({super.key});

  @override
  State<ZonasSegurasVista> createState() => _ZonasSegurasVistaState();
}

class _ZonasSegurasVistaState extends State<ZonasSegurasVista> {
  static const _colorAzul = Color(0xFF0056D2);
  static const _colorFondo = Color(0xFFF7F8FC);
  static const _colorTitulo = Color(0xFF111827);
  static const _colorTextoGris = Color(0xFF6B7280);
  static const _colorBorde = Color(0xFFE5E7EB);

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
    final token = Sesion.token;
    if (token == null || token.isEmpty) {
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
      final datos = await _servicio.listar(token);
      if (!mounted) return;
      setState(() {
        _datos = datos;
        _cargando = false;
      });
    } on ZonasServicioException catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e.mensaje;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo conectar con el servidor';
      });
    }
  }

  /// Abre el detalle. Con [zona] en null se crea una nueva.
  /// Si la pantalla devuelve true, algo cambió y hay que recargar la lista.
  Future<void> _abrirDetalle({ZonaSegura? zona}) async {
    final datos = _datos;
    if (datos == null) return;
    final cambio = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ZonaDetalleVista(
          zona: zona,
          radiosPermitidos: datos.radiosPermitidos,
        ),
      ),
    );
    if (cambio == true) _cargar();
  }

  void _avisarTope() {
    final maximo = _datos?.maximo ?? 3;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Ya tienes $maximo zonas seguras. Elimina una para agregar otra.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        foregroundColor: _colorTitulo,
        title: const Text(
          'Zonas Seguras',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(child: _cuerpo()),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _mensajeError(_error!);
    }

    final datos = _datos!;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text(
            'Zonas Seguras',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: _colorTitulo,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Gestiona tus ubicaciones frecuentes y define el radio de alerta '
            'para recibir notificaciones relevantes.',
            style: TextStyle(fontSize: 14, height: 1.4, color: _colorTextoGris),
          ),
          const SizedBox(height: 20),
          _tarjetaUbicaciones(datos),
        ],
      ),
    );
  }

  Widget _tarjetaUbicaciones(ZonasUsuario datos) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _encabezado(datos),
          if (datos.zonas.isEmpty)
            _sinZonas()
          else
            for (var i = 0; i < datos.zonas.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: _colorBorde),
              _filaZona(datos.zonas[i]),
            ],
        ],
      ),
    );
  }

  Widget _encabezado(ZonasUsuario datos) {
    final puedeAgregar = datos.puedeAgregar;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5FD),
        borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: _colorAzul, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Mis Ubicaciones',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _colorTitulo,
              ),
            ),
          ),
          TextButton.icon(
            // El botón nunca se oculta: si se deshabilitara sin más, el usuario
            // no sabría por qué. Al tocarlo en el tope, se explica el motivo.
            onPressed: puedeAgregar ? () => _abrirDetalle() : _avisarTope,
            icon: Icon(
              Icons.add,
              size: 18,
              color: puedeAgregar ? _colorAzul : _colorTextoGris,
            ),
            label: Text(
              'Añadir',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: puedeAgregar ? _colorAzul : _colorTextoGris,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sinZonas() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
      child: Column(
        children: [
          const Icon(
            Icons.add_location_alt_outlined,
            size: 36,
            color: _colorTextoGris,
          ),
          const SizedBox(height: 12),
          const Text(
            'Aún no tienes zonas seguras',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _colorTitulo,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Agrega tu casa o tu trabajo para recibir alertas de lo que pase '
            'cerca, aunque no estés ahí.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: _colorTextoGris,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _abrirDetalle(),
            style: FilledButton.styleFrom(
              backgroundColor: _colorAzul,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Añadir una zona'),
          ),
        ],
      ),
    );
  }

  Widget _filaZona(ZonaSegura zona) {
    final esPredefinida = zona.tipo != TipoZona.otro;
    return ListTile(
      onTap: () => _abrirDetalle(zona: zona),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: esPredefinida ? _colorAzul : const Color(0xFFEFF1F5),
          shape: BoxShape.circle,
        ),
        child: Icon(
          zona.tipo.icono,
          size: 21,
          color: esPredefinida ? Colors.white : _colorTitulo,
        ),
      ),
      title: Text(
        zona.nombre,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: _colorTitulo,
        ),
      ),
      subtitle: Text(
        zona.direccion?.isNotEmpty == true
            ? zona.direccion!
            : 'Radio de ${zona.radioTexto}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, color: _colorTextoGris),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5FD),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              zona.radioTexto,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _colorAzul,
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: _colorTextoGris, size: 20),
        ],
      ),
    );
  }

  Widget _mensajeError(String mensaje) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: _colorTextoGris),
            const SizedBox(height: 12),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: _colorTextoGris),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
