
package com.zyfer.app

import android.app.*
import android.content.*
import android.os.*
import android.speech.*
import android.content.pm.ServiceInfo
import androidx.core.app.NotificationCompat

class ZyferListeningService : Service() {
  private var recognizer: SpeechRecognizer? = null
  private lateinit var intentRec: Intent
  private var locale = "en_IN"
  private var stopped = false
  private val channel = "zyfer_listening"

  override fun onBind(intent: Intent?) = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    if (intent?.action == ACTION_STOP) {
      stopped = true
      stopSelf()
      return START_NOT_STICKY
    }

    stopped = false
    locale = intent?.getStringExtra("locale") ?: locale
    createNotification()
    startRecognition()
    return START_STICKY
  }

  private fun createNotification() {
    val nm = getSystemService(NotificationManager::class.java)

    if (Build.VERSION.SDK_INT >= 26) {
      nm.createNotificationChannel(
        NotificationChannel(
          channel,
          "ZYFER listening",
          NotificationManager.IMPORTANCE_LOW
        )
      )
    }

    val stop = Intent(this, ZyferListeningService::class.java)
      .setAction(ACTION_STOP)

    val pi = PendingIntent.getService(
      this, 44, stop,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    val n = NotificationCompat.Builder(this, channel)
      .setSmallIcon(android.R.drawable.ic_btn_speak_now)
      .setContentTitle("ZYFER is listening")
      .setContentText("Say Krish or Krishna. Open ZYFER to pause or resume.")
      .setOngoing(true)
      .addAction(android.R.drawable.ic_media_pause, "Stop listening", pi)
      .build()

    if (Build.VERSION.SDK_INT >= 29) {
      startForeground(44, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
    } else {
      startForeground(44, n)
    }
  }

  private fun startRecognition() {
    if (stopped || !SpeechRecognizer.isRecognitionAvailable(this)) return

    try {
      recognizer?.destroy()
      recognizer = SpeechRecognizer.createSpeechRecognizer(this)

      recognizer?.setRecognitionListener(object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}

        override fun onError(error: Int) {
          if (!stopped) {
            Handler(Looper.getMainLooper()).postDelayed(
              { startRecognition() }, 700
            )
          }
        }

        override fun onResults(results: Bundle?) {
          emit(results)
          if (!stopped) {
            Handler(Looper.getMainLooper()).postDelayed(
              { startRecognition() }, 350
            )
          }
        }

        override fun onPartialResults(partialResults: Bundle?) {
          emit(partialResults)
        }

        override fun onEvent(eventType: Int, params: Bundle?) {}
      })

      intentRec = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(
          RecognizerIntent.EXTRA_LANGUAGE_MODEL,
          RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
        )
        putExtra(
          RecognizerIntent.EXTRA_LANGUAGE,
          locale.replace('_', '-')
        )
        putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
      }

      recognizer?.startListening(intentRec)

    } catch (_: Exception) {
      Handler(Looper.getMainLooper()).postDelayed(
        { startRecognition() }, 1500
      )
    }
  }

  private fun emit(bundle: Bundle?) {
    val words = bundle
      ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
      ?.firstOrNull() ?: return

    sendBroadcast(
      Intent(ACTION_TEXT)
        .setPackage(packageName)
        .putExtra("text", words)
    )
  }

  override fun onDestroy() {
    stopped = true
    try {
      recognizer?.cancel()
      recognizer?.destroy()
    } catch (_: Exception) {}

    stopForeground(STOP_FOREGROUND_REMOVE)
    super.onDestroy()
  }

  companion object {
    const val ACTION_STOP = "com.zyfer.STOP_LISTENING"
    const val ACTION_TEXT = "com.zyfer.RECOGNIZED_TEXT"
  }
}
