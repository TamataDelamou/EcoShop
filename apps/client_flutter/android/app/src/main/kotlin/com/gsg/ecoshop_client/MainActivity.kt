package com.gsg.ecoshop_client

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        creerCanalAlertes()
        // Verrou (REG-18) : le contenu n'apparaît jamais dans la liste des
        // applications récentes (Android 13 et plus ; avant, l'écran uni de
        // l'application le cache dès qu'elle quitte le premier plan).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            setRecentsScreenshotEnabled(false)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ecoshop/ecran").setMethodCallHandler { appel, resultat ->
            when (appel.method) {
                "proteger" -> {
                    protegerCaptures(appel.argument<Boolean>("captures") == true)
                    resultat.success(null)
                }
                else -> resultat.notImplemented()
            }
        }
    }

    // Personnel et administration (décision du 2026-10-23) : captures
    // d'écran bloquées avant Android 13, où l'aperçu des applications
    // récentes ne peut pas être désactivé autrement.
    private fun protegerCaptures(proteger: Boolean) {
        if (proteger && Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    // Canal des notifications push envoyées par le serveur (`channel_id`
    // « ecoshop_alertes » de la fonction envoyer_push) : importance haute,
    // pour qu'une arrivée au portail ou une absence s'affiche tout de suite.
    private fun creerCanalAlertes() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val canal = NotificationChannel(
            "ecoshop_alertes",
            "Alertes de l'école",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Arrivée et sortie au portail, absences, scolarité, inscriptions"
        }
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(canal)
    }
}
