package com.gsg.ecoshop_client

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        creerCanalAlertes()
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
