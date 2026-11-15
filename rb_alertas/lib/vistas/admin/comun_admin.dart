// Piezas compartidas por las pestañas del panel de administración.
import 'package:flutter/material.dart';
import 'package:rb_alertas/servicios/api/api_cliente.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/dialogos.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Etiqueta y color de cada estado de reporte o de cuenta.
(String, Color) estiloEstado(String estado) => switch (estado) {
  'PENDIENTE' => ('Pendiente', RBColores.azul),
  'VALIDADO' => ('Validado', RBColores.verde),
  'RESUELTO' => ('Resuelto', RBColores.verde),
  'DESCARTADO' => ('Descartado', RBColores.rojo),
  'EXPIRADO' => ('Expirado', RBColores.texto2),
  'ACTIVO' => ('Activa', RBColores.verde),
  'SUSPENDIDO' => ('Suspendida', RBColores.rojo),
  'ELIMINADO' => ('Eliminada', RBColores.texto2),
  _ => (estado, RBColores.texto2),
};

/// Estado de un reporte con la píldora del sistema visual.
Widget chipReporte(String estado) =>
    ChipEstado(estado: EstadoVisual.desdeApi(estado), texto: estiloEstado(estado).$1);

/// Píldora de color: Activa en verde, Pendiente en azul y Suspendida en rojo.
Widget chipCuenta(String estado, {String? texto}) {
  final (fondo, color) = switch (estado) {
    'ACTIVO' => (RBColores.verde50, RBColores.verde),
    'PENDIENTE' => (RBColores.azul50, RBColores.azul),
    'SUSPENDIDO' => (RBColores.rojo50, RBColores.rojo),
    _ => (RBColores.linea, RBColores.texto2),
  };
  return PildoraAdmin(texto: texto ?? estiloEstado(estado).$1, fondo: fondo, color: color);
}

/// Etiqueta redondeada de color.
class PildoraAdmin extends StatelessWidget {
  final String texto;
  final Color fondo;
  final Color color;
  final EdgeInsets padding;
  final double tamano;

  const PildoraAdmin({
    super.key,
    required this.texto,
    required this.fondo,
    required this.color,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    this.tamano = 12.5,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(20)),
      child: Text(texto, style: TextStyle(fontSize: tamano, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

/// Aviso centrado. Es un ListView para que el gesto de recargar funcione igual.
class MensajeCentro extends StatelessWidget {
  final String texto;
  final VoidCallback? reintentar;

  const MensajeCentro(this.texto, {super.key, this.reintentar});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        Text(
          texto,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: RBColores.texto2),
        ),
        if (reintentar != null) ...[
          const SizedBox(height: 16),
          Center(child: OutlinedButton(onPressed: reintentar, child: const Text('Reintentar'))),
        ],
      ],
    );
  }
}

/// Indicador de carga, o el error con "Reintentar" si la carga falló.
Widget cargandoOError(String? error, VoidCallback reintentar) => error == null
    ? const Center(child: CircularProgressIndicator(color: RBColores.azul))
    : MensajeCentro(error, reintentar: reintentar);

/// Lista de tarjetas que se recarga deslizando hacia abajo.
class ListaAdmin<T> extends StatelessWidget {
  /// null mientras carga.
  final List<T>? elementos;
  final String? error;
  final Future<void> Function() recargar;
  final String textoVacio;
  final Widget Function(T elemento) tarjeta;

  const ListaAdmin({
    super.key,
    required this.elementos,
    required this.error,
    required this.recargar,
    required this.textoVacio,
    required this.tarjeta,
  });

  @override
  Widget build(BuildContext context) {
    final lista = elementos;
    if (lista == null) return cargandoOError(error, recargar);
    return RefreshIndicator(
      onRefresh: recargar,
      child: lista.isEmpty
          ? MensajeCentro(textoVacio)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              itemCount: lista.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => tarjeta(lista[i]),
            ),
    );
  }
}

/// Fila horizontal de chips para filtrar una lista por estado.
class FiltrosAdmin<T> extends StatelessWidget {
  final List<(T, String)> opciones;
  final T seleccionado;
  final ValueChanged<T> alElegir;

  const FiltrosAdmin({
    super.key,
    required this.opciones,
    required this.seleccionado,
    required this.alElegir,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        children: [
          for (final (valor, etiqueta) in opciones)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChipFiltro(
                etiqueta: etiqueta,
                activo: seleccionado == valor,
                onTap: () => alElegir(valor),
              ),
            ),
        ],
      ),
    );
  }
}

/// Buscador de texto con un interruptor de filtro debajo.
class BuscadorAdmin extends StatelessWidget {
  final TextEditingController controlador;
  final String pista;
  final VoidCallback alBuscar;
  final String etiquetaInterruptor;
  final bool valorInterruptor;
  final ValueChanged<bool> alCambiarInterruptor;

  const BuscadorAdmin({
    super.key,
    required this.controlador,
    required this.pista,
    required this.alBuscar,
    required this.etiquetaInterruptor,
    required this.valorInterruptor,
    required this.alCambiarInterruptor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: controlador,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => alBuscar(),
            decoration: InputDecoration(
              hintText: pista,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                tooltip: 'Buscar',
                icon: const Icon(Icons.arrow_forward_rounded, color: RBColores.azul),
                onPressed: alBuscar,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text(
            etiquetaInterruptor,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: RBColores.tinta),
          ),
          value: valorInterruptor,
          activeThumbColor: Colors.white,
          activeTrackColor: RBColores.azul,
          onChanged: alCambiarInterruptor,
        ),
      ],
    );
  }
}

/// Ejecuta una acción de moderación y avisa el resultado.
/// Devuelve true si se aplicó, para recargar lo que se está mostrando.
Future<bool> ejecutarAccionAdmin(
  BuildContext context,
  Future<void> Function() accion,
  String exito,
) async {
  try {
    await accion();
    if (context.mounted) mostrarAviso(context, exito);
    return true;
  } catch (e) {
    if (context.mounted) mostrarAviso(context, mensajeDeError(e));
    return false;
  }
}

/// Encabezado de una hoja inferior: título azul y botón para cerrarla.
class EncabezadoHoja extends StatelessWidget {
  final String titulo;
  final EdgeInsets padding;

  const EncabezadoHoja(this.titulo, {super.key, this.padding = const EdgeInsets.fromLTRB(20, 18, 8, 10)});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              titulo,
              style: const TextStyle(
                fontFamily: RBFuentes.titulos,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: RBColores.azul,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: RBColores.texto2),
          ),
        ],
      ),
    );
  }
}
