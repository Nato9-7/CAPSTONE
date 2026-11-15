import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

/// Mapa pequeño con el pin del incidente, la dirección y el botón "Ajustar".
/// Tocar el mapa mueve el pin a ese punto.
class TarjetaUbicacion extends StatelessWidget {
  final MapController mapController;
  final LatLng ubicacion;

  /// false mientras solo se muestra el centro de la ciudad por defecto.
  final bool confirmada;

  /// true si el punto vino del GPS; false si se marcó a mano.
  final bool porGps;
  final String? direccion;
  final bool buscando;
  final VoidCallback onMapaListo;
  final ValueChanged<LatLng> onTocarMapa;
  final VoidCallback onAjustar;

  const TarjetaUbicacion({
    super.key,
    required this.mapController,
    required this.ubicacion,
    required this.confirmada,
    required this.porGps,
    required this.direccion,
    required this.buscando,
    required this.onMapaListo,
    required this.onTocarMapa,
    required this.onAjustar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(RBRadios.tarjeta + 4),
        border: Border.all(color: RBColores.linea),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 150, child: _mapa()),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 16),
            child: Row(
              children: [
                Expanded(child: _textos()),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: onAjustar,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: RBColores.azul,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    minimumSize: const Size(0, 52),
                  ),
                  child: const Text('Ajustar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapa() {
    return Stack(
      children: [
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: ubicacion,
            initialZoom: 16,
            // El mapa no se arrastra: tocarlo mueve el pin a ese punto.
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
            onMapReady: onMapaListo,
            onTap: (_, punto) => onTocarMapa(punto),
          ),
          children: [capaMapaBase()],
        ),
        // Pin fijo al centro: el mapa siempre se centra en la ubicación.
        IgnorePointer(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Icon(
                Icons.location_on_rounded,
                size: 46,
                color: confirmada ? RBColores.azul : RBColores.placeholder,
                shadows: const [Shadow(color: Colors.white, blurRadius: 6)],
              ),
            ),
          ),
        ),
        if (buscando)
          const Positioned(
            top: 10,
            left: 10,
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        const Positioned(left: 4, bottom: 2, child: AtribucionMapa()),
      ],
    );
  }

  Widget _textos() {
    final String titulo;
    final Widget subtitulo;
    if (!confirmada) {
      titulo = buscando ? 'Detectando ubicación…' : 'Sin ubicación';
      subtitulo = const Text(
        'Usa «Ajustar» para marcar el lugar',
        style: TextStyle(fontSize: 14.5, color: RBColores.texto2),
      );
    } else {
      titulo = direccion ?? 'Buscando dirección…';
      subtitulo = Row(
        children: [
          Icon(
            porGps ? Icons.check_rounded : Icons.touch_app_outlined,
            size: 17,
            color: RBColores.verde,
          ),
          const SizedBox(width: 4),
          Text(
            porGps ? 'Detectada con tu GPS' : 'Marcada en el mapa',
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: RBColores.verde),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: RBColores.tinta),
        ),
        const SizedBox(height: 3),
        subtitulo,
      ],
    );
  }
}
