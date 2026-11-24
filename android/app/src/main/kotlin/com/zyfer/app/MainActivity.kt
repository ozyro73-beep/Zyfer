package com.zyfer.app

import android.content.*
import android.media.AudioManager
import android.provider.AlarmClock
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
  private var eventSink: EventChannel.EventSink? = null
  private val receiver = object: BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) { intent?.getStringExtra("text")?.let { eventSink?.success(it) } }
  }
  private fun norm(s: String) = s.lowercase().filter { it.isLetterOrDigit() }
  private fun openApp(name: String): String? {
    val q=norm(name); if(q.isEmpty()) return null
    val i=Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER); var best:String?=null; var pkg:String?=null; var score=0
    for(r in packageManager.queryIntentActivities(i,0)) { val label=r.loadLabel(packageManager).toString(); val l=norm(label); val sc=when { l==q->3; l.startsWith(q)->2; l.contains(q)||(l.length>=3&&q.contains(l))->1; else->0 }; if(sc>score){score=sc;best=label;pkg=r.activityInfo.packageName} }
    val launch=pkg?.let { packageManager.getLaunchIntentForPackage(it) } ?: return null
    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK); startActivity(launch); return best
  }
  override fun configureFlutterEngine(engine: FlutterEngine) {
    super.configureFlutterEngine(engine)
    EventChannel(engine.dartExecutor.binaryMessenger,"zyfer/background_events").setStreamHandler(object: EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { eventSink=events }
      override fun onCancel(arguments: Any?) { eventSink=null }
    })
    val filter=IntentFilter(ZyferListeningService.ACTION_TEXT)
    if(Build.VERSION.SDK_INT>=33) registerReceiver(receiver,filter,Context.RECEIVER_NOT_EXPORTED) else registerReceiver(receiver,filter)
    MethodChannel(engine.dartExecutor.binaryMessenger,"zyfer/audio").setMethodCallHandler { call,result ->
      when(call.method) {
        "startBackgroundListening" -> { try { val i=Intent(this,ZyferListeningService::class.java).putExtra("locale",call.argument<String>("locale") ?: "en_IN"); if(Build.VERSION.SDK_INT>=26) startForegroundService(i) else startService(i); result.success(true) } catch(e:Exception){ result.error("SERVICE_START",e.message,null) } }
        "stopBackgroundListening" -> { stopService(Intent(this,ZyferListeningService::class.java)); result.success(true) }
        "mute","unmute" -> { val am=getSystemService(Context.AUDIO_SERVICE) as AudioManager; val dir=if(call.method=="mute") AudioManager.ADJUST_MUTE else AudioManager.ADJUST_UNMUTE; for(s in intArrayOf(AudioManager.STREAM_NOTIFICATION,AudioManager.STREAM_SYSTEM)) try{am.adjustStreamVolume(s,dir,0)}catch(_:Exception){}; result.success(true) }
        "openApp" -> try { result.success(openApp(call.argument<String>("name") ?: "")) } catch(e:Exception){ result.success(null) }
        "setAlarm" -> try { val i=Intent(AlarmClock.ACTION_SET_ALARM).putExtra(AlarmClock.EXTRA_HOUR,call.argument<Int>("hour")?:0).putExtra(AlarmClock.EXTRA_MINUTES,call.argument<Int>("minute")?:0).putExtra(AlarmClock.EXTRA_MESSAGE,"ZYFER").putExtra(AlarmClock.EXTRA_SKIP_UI,true).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK); startActivity(i); result.success(true) } catch(e:Exception){ result.success(false) }
        "setTimer" -> try { val i=Intent(AlarmClock.ACTION_SET_TIMER).putExtra(AlarmClock.EXTRA_LENGTH,call.argument<Int>("seconds")?:60).putExtra(AlarmClock.EXTRA_MESSAGE,"ZYFER").putExtra(AlarmClock.EXTRA_SKIP_UI,true).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK); startActivity(i); result.success(true) } catch(e:Exception){ result.success(false) }
        else -> result.notImplemented()
      }
    }
  }
  override fun onDestroy(){ try{unregisterReceiver(receiver)}catch(_:Exception){}; super.onDestroy() }
}
