package cl.rbalertas.rb_alertas

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Mismo nombre que AvisoZonasRiesgo._canal en Dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cl.rbalertas/zonas_riesgo")
            .setMethodCallHandler { llamada, resultado ->
                when (llamada.method) {
                    "registrar" -> {
                        val zonas = JSONArray(llamada.argument<String>("zonas") ?: "[]")
                        resultado.success(ZonasRiesgo.registrar(applicationContext, zonas))
                    }
                    "quitar" -> {
                        ZonasRiesgo.quitar(applicationContext)
                        resultado.success(null)
                    }
                    "notificar" -> resultado.success(
                        ZonasRiesgo.notificar(
                            applicationContext,
                            llamada.argument<String>("id") ?: "",
                            llamada.argument<String>("titulo") ?: "",
                            llamada.argument<String>("texto") ?: "",
                        ),
                    )
                    "tienePermisoDeFondo" -> resultado.success(ZonasRiesgo.tienePermisoDeFondo(applicationContext))
                    else -> resultado.notImplemented()
                }
            }
    }
}
