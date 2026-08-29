import 'package:flutter/material.dart';
import 'package:rb_alertas/widgets/app_logo.dart';

class PantallaBienvenidaVista extends StatelessWidget {
  const PantallaBienvenidaVista({super.key});

  @override
  Widget build(BuildContext context) {
    const colorRojo = Color(0xFFDC2626);
    const colorAzul = Color(0xFF1D61E7);

    final size = MediaQuery.of(context).size;
    final double logoSize = size.width * 0.35;
    final double paddingH = size.width * 0.06;
    final double fontTitulo = size.width * 0.075;
    final double fontDesc = size.width * 0.035;
    final double fontBoton = size.width * 0.042;
    final double altoBoton = size.height * 0.065;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: size.height),
            child: IntrinsicHeight(
              child: Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: paddingH, vertical: 16.0),
                child: Column(
            children: [
              const Spacer(),

              // Logo de la aplicación
              AppLogo(
                size: logoSize,
              ),


              SizedBox(height: size.height * 0.04),

              // Título principal en Rojo y Negro
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'RB ',
                    style: TextStyle(
                      fontSize: fontTitulo,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    'Alertas',
                    style: TextStyle(
                      fontSize: fontTitulo,
                      fontWeight: FontWeight.bold,
                      color: colorRojo,
                    ),
                  ),
                ],
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
          ),
        ),
      ),
    );
  }
}

