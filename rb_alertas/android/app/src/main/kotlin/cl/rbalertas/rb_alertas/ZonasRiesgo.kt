package cl.rbalertas.rb_alertas

// Avisos al pasar por zonas de riesgo, también con la app cerrada.
//
// Se usan las geocercas de Android (Google Play Services): el sistema vigila
// la ubicación y despierta a ReceptorGeocercas al entrar a una zona, sin que
// la app tenga que estar abierta y gastando poca batería. Las zonas se guardan
// en SharedPreferences para poder volver a registrarlas al reiniciar el
// teléfono (Android borra las geocercas al apagarse).

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import org.json.JSONArray
import org.json.JSONObject

object ZonasRiesgo {
    private const val TAG = "ZonasRiesgo"
    private const val PREFS = "zonas_riesgo"
    private const val CLAVE_ZONAS = "zonas"
    private const val PREFIJO_ULTIMO_AVISO = "ultimo_aviso_"

    const val CANAL = "zonas_riesgo"

    /// Android permite hasta 100 geocercas por app.
    private const val MAXIMO_GEOCERCAS = 100

    /// Si la app no se abre en una semana, las zonas viejas dejan de avisar.
    private const val DURACION_MS = 7L * 24 * 60 * 60 * 1000

    /// No se repite el aviso de la misma zona antes de esto.
    private const val ESPERA_ENTRE_AVISOS_MS = 6L * 60 * 60 * 1000

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun tienePermisoDeFondo(context: Context): Boolean {
        val fina = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        if (!fina) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true
        return ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun intentGeocercas(context: Context): PendingIntent {
        val intent = Intent(context, ReceptorGeocercas::class.java)
        // Las geocercas necesitan un PendingIntent mutable: Android le agrega
        // los datos del evento.
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) flags = flags or PendingIntent.FLAG_MUTABLE
        return PendingIntent.getBroadcast(context, 0, intent, flags)
    }

    /// Guarda las zonas y las vigila. Devuelve false si falta el permiso de
    /// ubicación "todo el tiempo".
    fun registrar(context: Context, zonas: JSONArray): Boolean {
        prefs(context).edit().putString(CLAVE_ZONAS, zonas.toString()).apply()
        return vigilarGuardadas(context)
    }

    /// Vuelve a registrar las zonas guardadas (al reiniciar el teléfono).
    @SuppressLint("MissingPermission")
    fun vigilarGuardadas(context: Context): Boolean {
        val cliente = LocationServices.getGeofencingClient(context)
        val pendiente = intentGeocercas(context)
        cliente.removeGeofences(pendiente)

        val zonas = JSONArray(prefs(context).getString(CLAVE_ZONAS, "[]"))
        if (zonas.length() == 0) return true
        if (!tienePermisoDeFondo(context)) return false

        val geocercas = (0 until minOf(zonas.length(), MAXIMO_GEOCERCAS)).map { i ->
            val z = zonas.getJSONObject(i)
            Geofence.Builder()
                .setRequestId(z.getString("id"))
                .setCircularRegion(z.getDouble("latitud"), z.getDouble("longitud"), z.getDouble("radio").toFloat())
                .setExpirationDuration(DURACION_MS)
                .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER)
                .build()
        }
        val pedido = GeofencingRequest.Builder()
            // Sin aviso por estar ya dentro al registrar: de eso se encarga el
            // banner del mapa, y así no llega un aviso cada vez que se abre.
            .setInitialTrigger(0)
            .addGeofences(geocercas)
            .build()
        cliente.addGeofences(pedido, pendiente)
            .addOnSuccessListener { Log.d(TAG, "vigilando ${geocercas.size} zonas") }
            .addOnFailureListener { Log.w(TAG, "no se pudieron registrar las zonas", it) }
        return true
    }

    fun quitar(context: Context) {
        LocationServices.getGeofencingClient(context).removeGeofences(intentGeocercas(context))
        prefs(context).edit().clear().apply()
    }

    fun zonaGuardada(context: Context, id: String): JSONObject? {
        val zonas = JSONArray(prefs(context).getString(CLAVE_ZONAS, "[]"))
        for (i in 0 until zonas.length()) {
            val z = zonas.getJSONObject(i)
            if (z.getString("id") == id) return z
        }
        return null
    }

    /// Muestra el aviso de una zona, salvo que ya se haya avisado hace poco
    /// (la app abierta y la geocerca pueden detectar la misma entrada).
    /// Devuelve true si se mostró.
    fun notificar(context: Context, id: String, titulo: String, texto: String): Boolean {
        val ahora = System.currentTimeMillis()
        val p = prefs(context)
        if (ahora - p.getLong(PREFIJO_ULTIMO_AVISO + id, 0) < ESPERA_ENTRE_AVISOS_MS) return false

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return false

        crearCanal(context)
        val abrir = PendingIntent.getActivity(
            context,
            id.hashCode(),
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val aviso = NotificationCompat.Builder(context, CANAL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(titulo)
            .setContentText(texto)
            .setStyle(NotificationCompat.BigTextStyle().bigText(texto))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_RECOMMENDATION)
            .setContentIntent(abrir)
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(id.hashCode(), aviso)
        } catch (e: SecurityException) {
            return false
        }
        p.edit().putLong(PREFIJO_ULTIMO_AVISO + id, ahora).apply()
        return true
    }

    private fun crearCanal(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val canal = NotificationChannel(CANAL, "Zonas de riesgo", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Aviso al pasar por lugares con robos o accidentes frecuentes"
        }
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(canal)
    }
}

/// Android lo despierta al entrar a una zona, aunque la app esté cerrada.
class ReceptorGeocercas : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val evento = GeofencingEvent.fromIntent(intent) ?: return
        if (evento.hasError() || evento.geofenceTransition != Geofence.GEOFENCE_TRANSITION_ENTER) return
        for (geocerca in evento.triggeringGeofences.orEmpty()) {
            val zona = ZonasRiesgo.zonaGuardada(context, geocerca.requestId) ?: continue
            ZonasRiesgo.notificar(context, geocerca.requestId, zona.getString("titulo"), zona.getString("texto"))
        }
    }
}

/// Al reiniciar el teléfono o actualizar la app, las geocercas se pierden:
/// se vuelven a registrar con las zonas guardadas.
class ReceptorArranque : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> ZonasRiesgo.vigilarGuardadas(context)
        }
    }
}
