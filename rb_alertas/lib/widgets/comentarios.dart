import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:rb_alertas/servicios/comentario_servicio.dart';
import 'package:rb_alertas/tema/rb_tema.dart';
import 'package:rb_alertas/widgets/rb_componentes.dart';

// Piezas de la conversación de un reporte (detalle del incidente).

/// Un comentario con su burbuja; con [respuesta] se dibuja más chico, para
/// ir indentado bajo el comentario raíz.
class TarjetaComentario extends StatelessWidget {
  final Comentario comentario;
  final bool respuesta;
  final VoidCallback? onResponder;
  final VoidCallback? onEliminar;
  final ValueChanged<String>? onVerFoto;

  const TarjetaComentario({
    super.key,
    required this.comentario,
    this.respuesta = false,
    this.onResponder,
    this.onEliminar,
    this.onVerFoto,
  });

  @override
  Widget build(BuildContext context) {
    final c = comentario;
    final avatar = respuesta ? 34.0 : 46.0;

    if (!c.publicado) return _marcador(avatar);

    final acciones = [
      if (onResponder != null) _accion('Responder', RBColores.azul, onResponder!),
      if (onEliminar != null) _accion('Eliminar', RBColores.rojo, onEliminar!),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AvatarSuricata(tamano: avatar),
        SizedBox(width: respuesta ? 10 : 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(respuesta ? 12 : 16, 12, respuesta ? 12 : 16, 14),
                decoration: BoxDecoration(
                  color: RBColores.fondo,
                  borderRadius: BorderRadius.circular(RBRadios.campo),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  c.autor ?? 'Vecino',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: RBColores.tinta,
                                  ),
                                ),
                              ),
                              if (c.esAutorReporte) ...[
                                const SizedBox(width: 6),
                                const _ChipAutor(),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          tiempoRelativo(c.fechaCreacion),
                          style: const TextStyle(fontSize: 13.5, color: RBColores.texto2),
                        ),
                      ],
                    ),
                    if (c.contenido != null && c.contenido!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        c.contenido!,
                        style: const TextStyle(fontSize: 15.5, height: 1.4, color: RBColores.tinta),
                      ),
                    ],
                    if (c.imagenUrl != null) ...[
                      const SizedBox(height: 10),
                      _foto(c.imagenUrl!),
                    ],
                  ],
                ),
              ),
              if (acciones.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 2),
                  child: Row(children: acciones),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _foto(String url) {
    return GestureDetector(
      onTap: onVerFoto == null ? null : () => onVerFoto!(url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url,
          height: 160,
          width: double.infinity,
          fit: BoxFit.cover,
          loadingBuilder: (context, hijo, progreso) => progreso == null
              ? hijo
              : Container(
                  height: 160,
                  color: RBColores.azul50,
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
          errorBuilder: (context, error, pila) => Container(
            height: 100,
            color: RBColores.azul50,
            child: const Center(
              child: Icon(Icons.broken_image_outlined, size: 32, color: RBColores.texto2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _accion(String texto, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        // Alto mínimo cómodo para el dedo sin agrandar la conversación.
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Text(
          texto,
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color),
        ),
      ),
    );
  }

  /// Comentario raíz eliminado u oculto que se mantiene porque tiene respuestas.
  Widget _marcador(double avatar) {
    final texto = comentario.estado == 'OCULTO'
        ? 'Comentario oculto por moderación'
        : 'Comentario eliminado';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: avatar,
          height: avatar,
          decoration: const BoxDecoration(color: RBColores.linea, shape: BoxShape.circle),
          child: Icon(Icons.chat_bubble_outline_rounded, size: avatar * 0.45, color: RBColores.texto2),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: RBColores.fondo,
              borderRadius: BorderRadius.circular(RBRadios.campo),
            ),
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                color: RBColores.texto2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChipAutor extends StatelessWidget {
  const _ChipAutor();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: RBColores.verde50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'Autor',
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: RBColores.verde),
      ),
    );
  }
}

/// Barra fija al pie del detalle para escribir: cámara, galería, texto y enviar.
/// Arriba muestra a quién se responde y la foto adjunta, si los hay.
class BarraComentario extends StatelessWidget {
  final TextEditingController controlador;
  final FocusNode foco;
  final String? respondiendoA;
  final Uint8List? foto;
  final bool enviando;
  final VoidCallback onCamara;
  final VoidCallback onGaleria;
  final VoidCallback onEnviar;
  final VoidCallback onCancelarRespuesta;
  final VoidCallback onQuitarFoto;

  static const largoMaximo = 500;

  const BarraComentario({
    super.key,
    required this.controlador,
    required this.foco,
    required this.respondiendoA,
    required this.foto,
    required this.enviando,
    required this.onCamara,
    required this.onGaleria,
    required this.onEnviar,
    required this.onCancelarRespuesta,
    required this.onQuitarFoto,
  });

  @override
  Widget build(BuildContext context) {
    final angosta = context.pantallaAngosta;
    final boton = angosta ? 42.0 : 48.0;

    return Container(
      padding: EdgeInsets.fromLTRB(
        angosta ? 10 : 16,
        10,
        angosta ? 10 : 16,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: RBColores.linea)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (respondiendoA != null) _respondiendo(),
          if (foto != null) _vistaFoto(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _botonAdjuntar(Icons.photo_camera_outlined, 'Tomar foto', boton, onCamara),
              const SizedBox(width: 8),
              _botonAdjuntar(Icons.image_outlined, 'Elegir foto', boton, onGaleria),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controlador,
                  focusNode: foco,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: largoMaximo,
                  textCapitalization: TextCapitalization.sentences,
                  // El contador aparece solo cerca del límite.
                  buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                      currentLength > largoMaximo - 100
                          ? Text('$currentLength/$largoMaximo',
                              style: const TextStyle(fontSize: 12, color: RBColores.texto2))
                          : null,
                  style: const TextStyle(fontSize: 16, color: RBColores.tinta),
                  decoration: InputDecoration(
                    hintText: respondiendoA != null ? 'Tu respuesta…' : 'Escribe un comentario…',
                    hintMaxLines: 1,
                    hintStyle: const TextStyle(
                      fontSize: 15.5,
                      color: RBColores.placeholder,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(26),
                      borderSide: const BorderSide(color: RBColores.bordeCampo),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(26),
                      borderSide: const BorderSide(color: RBColores.bordeCampo),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(26),
                      borderSide: const BorderSide(color: RBColores.azul, width: 1.6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: boton + 4,
                height: boton + 4,
                child: Material(
                  color: enviando ? RBColores.azul.withValues(alpha: 0.6) : RBColores.azul,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: enviando ? null : onEnviar,
                    child: Center(
                      child: enviando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                            )
                          : const Icon(Icons.near_me_outlined, color: Colors.white, size: 24,
                              semanticLabel: 'Enviar comentario'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _botonAdjuntar(IconData icono, String tooltip, double tamano, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: tamano,
        height: tamano,
        child: Material(
          color: RBColores.azul50,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enviando ? null : onTap,
            child: Icon(icono, color: RBColores.azul, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _respondiendo() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.reply_rounded, size: 18, color: RBColores.azul),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: 'Respondiendo a ',
                children: [
                  TextSpan(
                    text: respondiendoA,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: RBColores.tinta),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: RBColores.texto2),
            ),
          ),
          IconButton(
            tooltip: 'Cancelar respuesta',
            visualDensity: VisualDensity.compact,
            onPressed: enviando ? null : onCancelarRespuesta,
            icon: const Icon(Icons.close_rounded, size: 20, color: RBColores.texto2),
          ),
        ],
      ),
    );
  }

  Widget _vistaFoto() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(foto!, width: 72, height: 72, fit: BoxFit.cover),
            ),
            Positioned(
              top: -8,
              right: -8,
              child: Material(
                color: RBColores.tinta,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: enviando ? null : onQuitarFoto,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, size: 16, color: Colors.white,
                        semanticLabel: 'Quitar foto'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Foto de un comentario a pantalla completa, con zoom.
Future<void> verFotoComentario(BuildContext context, String url) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              maxScale: 4,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (context, error, pila) => const Center(
                  child: Icon(Icons.broken_image_outlined, size: 48, color: Colors.white70),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
