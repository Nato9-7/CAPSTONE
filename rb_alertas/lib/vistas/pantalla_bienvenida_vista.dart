import 'package:flutter/material.dart';

class PantallaBienvenidaVista extends StatelessWidget {
  const PantallaBienvenidaVista({super.key});

  @override
  Widget build(BuildContext context) {
    const colorAzul = Color(0xFF1D61E7);
    const colorAzulSuave = Color(0xFFE5EDFF);

    final size = MediaQuery.of(context).size;
    final double iconSize = size.width * 0.27;
    final double iconInner = size.width * 0.13;
    final double paddingH = size.width * 0.06;
    final double fontTitulo = size.width * 0.075;
    final double fontSubtitulo = size.width * 0.055;
    final double fontDesc = size.width * 0.035;
    final double fontBoton = size.width * 0.042;
    final double altoBoton = size.height * 0.065;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: 16.0),
          child: Column(
            children: [
              const Spacer(),

              // Ícono con fondo azul claro
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color: colorAzulSuave,
                  borderRadius: BorderRadius.circular(iconSize * 0.25),
                ),
                child: Icon(
                  Icons.shield,
                  size: iconInner,
                  color: colorAzul,
                ),
              ),

              SizedBox(height: size.height * 0.04),

              // Título
              Text(
                'Alerta',
                style: TextStyle(
                  fontSize: fontTitulo,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),

              SizedBox(height: size.height * 0.005),

              // Subtítulo
              Text(
                'Puerto Montt',
                style: TextStyle(
                  fontSize: fontSubtitulo,
                  fontWeight: FontWeight.bold,
                  color: colorAzul,
                ),
              ),

              SizedBox(height: size.height * 0.02),

              // Descripción
              Text(
                'Seguridad ciudadana en la palma de\ntu mano.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: fontDesc,
                  color: const Color(0xFF6B7280),
                  height: 1.5,
                ),
              ),

              const Spacer(),

              // Botón Comenzar
              SizedBox(
                width: double.infinity,
                height: altoBoton,
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorAzul,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Comenzar',
                        style: TextStyle(
                          fontSize: fontBoton,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: fontBoton),
                    ],
                  ),
                ),
              ),

              SizedBox(height: size.height * 0.025),

              // Versión
              Text(
                'v2.4.0',
                style: TextStyle(
                  fontSize: fontDesc,
                  color: const Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

