import 'package:flutter/material.dart';
import 'package:rb_alertas/modelos/modelos.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/vistas/admin/red/filtros_red.dart';
import 'package:rb_alertas/vistas/admin/red/piezas_red.dart';
import 'package:rb_alertas/vistas/admin/red/textos_red.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Barra sobre el lienzo: buscador, vista, categoría, capas y línea de tiempo.
/// En pantalla angosta solo deja el buscador y abre el resto en una hoja.
class BarraHerramientasRed extends StatelessWidget {
  final bool compacto;
  final bool cargando;
  final FiltrosRed filtros;
  final List<CategoriaIncidente> categorias;
  final Future<List<NodoGrafo>> Function(String texto) buscar;
  final ValueChanged<NodoGrafo> alElegirResultado;

  /// Cambio inmediato de filtros (vista, categoría o capas).
  final ValueChanged<FiltrosRed> alCambiar;

  /// La línea de tiempo avisa mientras se arrastra y recarga al soltarla.
  final ValueChanged<int> alMoverPeriodo;
  final VoidCallback alSoltarPeriodo;
  final VoidCallback alAbrirFiltros;
  final VoidCallback alSincronizar;

  const BarraHerramientasRed({
    super.key,
    required this.compacto,
    required this.cargando,
    required this.filtros,
    required this.categorias,
    required this.buscar,
    required this.alElegirResultado,
    required this.alCambiar,
    required this.alMoverPeriodo,
    required this.alSoltarPeriodo,
    required this.alAbrirFiltros,
    required this.alSincronizar,
  });

  @override
  Widget build(BuildContext context) {
    final buscador = BuscadorRed(buscar: buscar, alElegir: alElegirResultado);
    final sincronizar = IconButton(
      tooltip: 'Actualizar con los datos de ahora',
      onPressed: cargando ? null : alSincronizar,
      icon: const Icon(Icons.sync_rounded, color: RBColores.azul),
    );
    if (compacto) {
      return Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          children: [
            Expanded(child: buscador),
            IconButton(
              tooltip: 'Filtros',
              onPressed: alAbrirFiltros,
              icon: const Icon(Icons.tune_rounded, color: RBColores.azul),
            ),
            sincronizar,
          ],
        ),
      );
    }
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: buscador),
              const SizedBox(width: 8),
              _menuCapas(),
              sincronizar,
            ],
          ),
          const SizedBox(height: 8),
          SelectorModoRed(
            modo: filtros.modo,
            alElegir: (modo) => alCambiar(filtros.conModo(modo)),
          ),
          const SizedBox(height: 8),
          FiltroCategoriasRed(
            categoria: filtros.categoria,
            disponibles: categorias,
            alElegir: (codigo) => alCambiar(filtros.conCategoria(codigo)),
          ),
          const SizedBox(height: 4),
          _lineaTiempo(),
        ],
      ),
    );
  }

  /// Línea de tiempo: cuánta historia mostrar (de 7 días a todo).
  Widget _lineaTiempo() {
    return Row(
      children: [
        const Icon(Icons.history_rounded, size: 18, color: RBColores.texto2),
        const SizedBox(width: 4),
        Expanded(
          child: SliderPeriodoRed(
            periodo: filtros.periodo,
            alMover: alMoverPeriodo,
            alSoltar: (_) => alSoltarPeriodo(),
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(
            filtros.nombrePeriodo,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: RBColores.tinta),
          ),
        ),
      ],
    );
  }

  Widget _menuCapas() {
    final habilitado = filtros.modo == 'completa';
    return PopupMenuButton<String>(
      tooltip: 'Capas de la red completa',
      enabled: habilitado,
      icon: Icon(Icons.layers_outlined, color: habilitado ? RBColores.azul : RBColores.placeholder),
      onSelected: (capa) => alCambiar(filtros.alternarCapa(capa)),
      itemBuilder: (_) => [
        for (final (clave, nombre, icono) in capasRed)
          CheckedPopupMenuItem(
            value: clave,
            checked: filtros.capas.contains(clave),
            child: Row(
              children: [
                Icon(icono, size: 18, color: RBColores.texto2),
                const SizedBox(width: 8),
                Text(nombre),
              ],
            ),
          ),
      ],
    );
  }
}

/// Chips para elegir qué se dibuja: quién apoya a quién, la red completa o dónde ocurre más.
class SelectorModoRed extends StatelessWidget {
  final String modo;
  final ValueChanged<String> alElegir;

  /// En la barra, "Dónde ocurre más" lleva el ícono de fuego.
  final bool conIconos;

  const SelectorModoRed({super.key, required this.modo, required this.alElegir, this.conIconos = true});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChipFiltro(
          etiqueta: 'Quién apoya a quién',
          activo: modo == 'vecinos',
          onTap: () => alElegir('vecinos'),
        ),
        ChipFiltro(
          etiqueta: 'Red completa',
          activo: modo == 'completa',
          onTap: () => alElegir('completa'),
        ),
        ChipFiltro(
          etiqueta: 'Dónde ocurre más',
          icono: conIconos
              ? Icon(
                  Icons.local_fire_department_rounded,
                  size: 18,
                  color: modo == 'zonas' ? Colors.white : RBColores.rojo,
                )
              : null,
          activo: modo == 'zonas',
          onTap: () => alElegir('zonas'),
        ),
      ],
    );
  }
}

/// Deslizador de [periodosRed].
class SliderPeriodoRed extends StatelessWidget {
  final int periodo;
  final ValueChanged<int> alMover;
  final ValueChanged<int>? alSoltar;

  const SliderPeriodoRed({super.key, required this.periodo, required this.alMover, this.alSoltar});

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: periodo.toDouble(),
      min: 0,
      max: (periodosRed.length - 1).toDouble(),
      divisions: periodosRed.length - 1,
      label: periodosRed[periodo].$2,
      activeColor: RBColores.azul,
      onChanged: (v) => alMover(v.round()),
      onChangeEnd: alSoltar == null ? null : (v) => alSoltar!(v.round()),
    );
  }
}

/// Busca vecinos, reportes o lugares por texto (desde 2 letras).
class BuscadorRed extends StatelessWidget {
  final Future<List<NodoGrafo>> Function(String texto) buscar;
  final ValueChanged<NodoGrafo> alElegir;

  const BuscadorRed({super.key, required this.buscar, required this.alElegir});

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<NodoGrafo>(
      displayStringForOption: (n) => n.etiqueta,
      optionsBuilder: (valor) async {
        final texto = valor.text.trim();
        if (texto.length < 2) return const [];
        try {
          return await buscar(texto);
        } catch (_) {
          return const [];
        }
      },
      onSelected: (n) {
        FocusScope.of(context).unfocus();
        alElegir(n);
      },
      fieldViewBuilder: (context, controlador, foco, alEnviar) => TextField(
        controller: controlador,
        focusNode: foco,
        onSubmitted: (_) => alEnviar(),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Buscar vecino, #reporte o lugar',
          prefixIcon: const Icon(Icons.search_rounded, color: RBColores.texto2),
          filled: true,
          fillColor: RBColores.fondo,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(RBRadios.campo),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      optionsViewBuilder: (context, alElegirOpcion, opciones) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320, maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              shrinkWrap: true,
              children: [
                for (final n in opciones)
                  ListTile(
                    dense: true,
                    leading: IconoNodoRed(n, tamano: 30),
                    title: Text(n.etiqueta, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(nombreTipoRed(n.tipo)),
                    onTap: () => alElegirOpcion(n),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Celular: vista, categoría, línea de tiempo y capas en una hoja que sube
/// desde abajo. Cada cambio se informa al instante con [alCambiar].
class HojaFiltrosRed extends StatefulWidget {
  final FiltrosRed inicial;
  final List<CategoriaIncidente> categorias;
  final ValueChanged<FiltrosRed> alCambiar;

  const HojaFiltrosRed({super.key, required this.inicial, required this.categorias, required this.alCambiar});

  @override
  State<HojaFiltrosRed> createState() => _HojaFiltrosRedState();
}

class _HojaFiltrosRedState extends State<HojaFiltrosRed> {
  late FiltrosRed _filtros = widget.inicial;

  void _cambiar(FiltrosRed nuevos) {
    setState(() => _filtros = nuevos);
    widget.alCambiar(nuevos);
  }

  static const _titulo = TextStyle(fontWeight: FontWeight.w800);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          const Text('Vista', style: _titulo),
          const SizedBox(height: 8),
          SelectorModoRed(
            modo: _filtros.modo,
            conIconos: false,
            alElegir: (modo) => _cambiar(_filtros.conModo(modo)),
          ),
          const SizedBox(height: 16),
          const Text('Categoría', style: _titulo),
          const SizedBox(height: 8),
          FiltroCategoriasRed(
            categoria: _filtros.categoria,
            disponibles: widget.categorias,
            alElegir: (codigo) => _cambiar(_filtros.conCategoria(codigo)),
          ),
          const SizedBox(height: 16),
          const Text('Línea de tiempo', style: _titulo),
          SliderPeriodoRed(
            periodo: _filtros.periodo,
            alMover: (p) => _cambiar(_filtros.conPeriodo(p)),
          ),
          Text('Mostrando: ${_filtros.nombrePeriodo}', style: const TextStyle(color: RBColores.texto2)),
          if (_filtros.modo == 'completa') ...[
            const SizedBox(height: 16),
            const Text('Capas', style: _titulo),
            for (final (clave, nombre, icono) in capasRed)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                secondary: Icon(icono, color: RBColores.texto2),
                title: Text(nombre),
                value: _filtros.capas.contains(clave),
                onChanged: (_) => _cambiar(_filtros.alternarCapa(clave)),
              ),
          ],
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Listo')),
        ],
      ),
    );
  }
}
