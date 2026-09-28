package be.perso.coffre

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

/**
 * Widget statique (aucune donnée affichée, donc rien de privé sur l'écran
 * d'accueil) : trois boutons qui ouvrent directement l'écran Capture.
 */
class CaptureWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = RemoteViews(context.packageName, R.layout.widget_capture).apply {
            setOnClickPendingIntent(R.id.widget_idea, launch(context, "coffre://capture?kind=idea", 1))
            setOnClickPendingIntent(R.id.widget_task, launch(context, "coffre://capture?kind=task", 2))
            setOnClickPendingIntent(
                R.id.widget_voice,
                launch(context, "coffre://capture?kind=task&voice=1", 3),
            )
        }
        manager.updateAppWidget(ids, views)
    }

    private fun launch(context: Context, uri: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse(uri)
            // Réutilise l'instance existante (onNewIntent) au lieu d'en créer une seconde.
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
