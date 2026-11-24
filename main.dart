import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

const bg = Color(0xFF0A3CFF);
const bgDark = Color(0xFF031A6B);
late SharedPreferences prefs;
const groqKey = String.fromEnvironment('GROQ_KEY');
const elevenLabsKey = String.fromEnvironment('ELEVENLABS_API_KEY');
const configuredElevenLabsVoiceId = String.fromEnvironment('ELEVENLABS_VOICE_ID');
final elevenLabsVoiceId = configuredElevenLabsVoiceId.isEmpty
    ? 'JBFqnCBsd6RMkjVDRZzb'
    : configuredElevenLabsVoiceId;
const audioCh = MethodChannel('zyfer/audio');
const backgroundEvents = EventChannel('zyfer/background_events');
StreamSubscription<dynamic>? backgroundSub;
bool allowed(String k) => prefs.getBool(k) ?? true;

Future<dynamic> nativeCall(String m, [Map<String, dynamic>? a]) async {
  try {
    return await audioCh.invokeMethod(m, a);
  } catch (_) {
    return null;
  }
}

String fmt12(int h, int m) {
  final hh = h % 12 == 0 ? 12 : h % 12;
  return '$hh:${m.toString().padLeft(2, '0')} ${h >= 12 ? 'PM' : 'AM'}';
}

List<int>? parseTime(String t) {
  final x = t.replaceAll('.', '');
  final m = RegExp(r'(\d{1,2})(?:[:\s](\d{2}))?\s*(am|pm)?').firstMatch(x);
  if (m == null) return null;
  var h = int.parse(m.group(1)!);
  final min = int.tryParse(m.group(2) ?? '0') ?? 0;
  final ap = m.group(3);
  if (h > 23 || min > 59) return null;
  if (ap == 'pm' && h < 12) h += 12;
  if (ap == 'am' && h == 12) h = 0;
  if (ap == null && h <= 12) {
    final n = DateTime.now();
    int d(int c) {
      final v = ((c * 60 + min) - (n.hour * 60 + n.minute) + 1440) % 1440;
      return v == 0 ? 1440 : v;
    }
    final a = h % 12, b = h % 12 + 12;
    h = d(a) <= d(b) ? a : b;
  }
  return [h, min];
}

Future<void> beepMute(bool m) async {
  try {
    await audioCh.invokeMethod(m ? 'mute' : 'unmute');
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  prefs = await SharedPreferences.getInstance();
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: Splash()));
}

Widget logo(double s) => Image.asset('assets/logo.png', width: s, height: s,
    errorBuilder: (_, __, ___) => Icon(Icons.graphic_eq, size: s, color: Colors.white));

InputDecoration deco(String h) => InputDecoration(
    hintText: h, hintStyle: const TextStyle(color: Colors.white60),
    filled: true, fillColor: Colors.white12,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none));

class Shell extends StatelessWidget {
  final Widget child;
  const Shell(this.child, {super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
      body: Container(
          width: double.infinity, height: double.infinity,
          decoration: const BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [bg, bgDark])),
          child: SafeArea(child: child)));
}

const white = TextStyle(color: Colors.white);

class Splash extends StatefulWidget {
  const Splash({super.key});
  @override
  State<Splash> createState() => _SplashS();
}

class _SplashS extends State<Splash> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => prefs.getBool('setup') == true ? const Home() : const Setup()));
    });
  }
  @override
  Widget build(BuildContext c) => Shell(Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        logo(120), const SizedBox(height: 16),
        const Text('ZYFER', style: TextStyle(color: Colors.white, fontSize: 32, letterSpacing: 6, fontWeight: FontWeight.bold))])));
}

class Setup extends StatefulWidget {
  const Setup({super.key});
  @override
  State<Setup> createState() => _SetupS();
}

class _SetupS extends State<Setup> {
  final name = TextEditingController();
  String lang = 'en-IN', languageChoice = 'Hinglish', title = 'Sir', voice = 'Male';

  Widget chips(List<String> o, String cur, void Function(String) on) => Wrap(spacing: 8, children: [
        for (final x in o) ChoiceChip(label: Text(x), selected: cur == x, onSelected: (_) => setState(() => on(x)))]);

  @override
  void initState() {
    super.initState();
    name.text = prefs.getString('name') ?? '';
    title = prefs.getString('title') ?? 'Sir';
    languageChoice = prefs.getString('language_mode') ?? 'Hinglish';
    lang = languageChoice == 'Hindi' ? 'hi-IN' : 'en-IN';
    voice = (prefs.getBool('male') ?? true) ? 'Male' : 'Female';
  }

  @override
  Widget build(BuildContext c) => Shell(ListView(padding: const EdgeInsets.all(24), children: [
        Center(child: logo(80)), const SizedBox(height: 20),
        TextField(controller: name, style: white, decoration: deco('Your name')),
        const SizedBox(height: 14),
        const SizedBox(height: 10),
        const Text('Language mode', style: white),
        chips(['English', 'Hinglish', 'Hindi'], languageChoice, (x) {
          languageChoice = x;
          lang = x == 'Hindi' ? 'hi-IN' : 'en-IN';
        }),
        const SizedBox(height: 4),
        const Text('Voice type', style: white),
        chips(['Male', 'Female'], voice, (x) => voice = x),
        const SizedBox(height: 10),
        const Text('Call me', style: white),
        chips(['Sir', 'Madam'], title, (x) => title = x),
        const SizedBox(height: 24),
        ElevatedButton(
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
            onPressed: () async {
              await prefs.setString('name', name.text.trim());
              await prefs.setString('lang', lang);
              await prefs.setString('language_mode', languageChoice);
              await prefs.setString('title', title);
              await prefs.setBool('male', voice == 'Male');
              if (!mounted) return;
              Navigator.push(context, MaterialPageRoute(builder: (_) => const Perms()));
            },
            child: const Text('GO', style: TextStyle(fontSize: 18)))]));
}

class Perms extends StatefulWidget {
  const Perms({super.key});
  @override
  State<Perms> createState() => _PermsS();
}

class _PermsS extends State<Perms> {
  bool open = allowed('c_open'), alarm = allowed('c_alarm'), search = allowed('c_search');

  Widget sw(String t, String sub, bool v, void Function(bool) f) => SwitchListTile(
      value: v,
      onChanged: (x) => setState(() => f(x)),
      activeColor: Colors.white,
      title: Text(t, style: white),
      subtitle: Text(sub, style: const TextStyle(color: Colors.white60)));

  @override
  Widget build(BuildContext c) => Shell(ListView(padding: const EdgeInsets.all(24), children: [
        const Icon(Icons.lock_open, color: Colors.white, size: 60),
        const SizedBox(height: 16),
        const Text('Permissions needed:\nMicrophone, Notifications,\nDisplay over other apps (app control)',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 18)),
        const SizedBox(height: 24),
        const Text('Connect apps',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        sw('Open apps', 'Open any app on your phone', open, (x) => open = x),
        sw('Alarms & timers', 'Set alarms and timers', alarm, (x) => alarm = x),
        sw('Search', 'Search Google and YouTube', search, (x) => search = x),
        const SizedBox(height: 16),
        ElevatedButton(
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
            onPressed: () async {
              await [Permission.microphone, Permission.notification, Permission.systemAlertWindow].request();
              await prefs.setBool('c_open', open);
              await prefs.setBool('c_alarm', alarm);
              await prefs.setBool('c_search', search);
              await prefs.setBool('setup', true);
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const Home()), (_) => false);
            },
            child: const Text('Allow permissions'))]));
}


class ZyferOrb extends StatefulWidget {
  final double size;
  const ZyferOrb({super.key, required this.size});
  @override
  State<ZyferOrb> createState() => _ZyferOrbState();
}
class _ZyferOrbState extends State<ZyferOrb> with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat();
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: controller, builder: (_, __) => Transform.rotate(
    angle: controller.value * 6.283185307,
    child: Container(width: widget.size, height: widget.size,
      decoration: BoxDecoration(shape: BoxShape.circle,
        gradient: const SweepGradient(colors: [Color(0xFF8BE9FF), Color(0xFF315BFF), Color(0xFFB6A5FF), Color(0xFF8BE9FF)]),
        boxShadow: [BoxShadow(color: Colors.cyanAccent.withOpacity(.35), blurRadius: 24, spreadRadius: 3)]),
      child: Center(child: Container(width: widget.size*.72, height: widget.size*.72,
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0xFF80DFFF), Color(0xFF1237B8), Color(0xFF06134D)])),
        child: const Icon(Icons.graphic_eq, color: Colors.white, size: 42))))));
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeS();
}

class _HomeS extends State<Home> with WidgetsBindingObserver {
  static const model = 'openai/gpt-oss-120b';
  static final wake = RegExp(
      r'\b(krish|krishna|krishn|krisna|krsna|kishna|kreshna|krishnaa|christina|crishna)\b|\u0915\u0943\u0937\u094d\u0923|\u0915\u094d\u0930\u093f\u0936\u094d\u0928|\u0915\u0943\u0937\u0928|\u0915\u093f\u0937\u094d\u0928)');
  Timer? restartT, debT;
  String latest = '';

  void scheduleListen([int ms = 900]) {
    restartT?.cancel();
    restartT = Timer(Duration(milliseconds: ms), listenOnce);
  }
  final stt = SpeechToText();
  final tts = FlutterTts();
  final elevenPlayer = AudioPlayer();
  final List<Map<String, String>> chatHistory = [];
  bool get friendMode => prefs.getBool('friend_mode') ?? false;
  String get languageMode => prefs.getString('language_mode') ?? 'Hinglish';
  String get responseLanguage => languageMode == 'Hindi'
      ? 'Hindi' : (languageMode == 'English' ? 'English' : 'natural Hinglish (Hindi + English)');
  String status = 'Starting...', heard = '', reply = '', err = '';
  bool on = true, busy = false, starting = false;
  DateTime activeUntil = DateTime.fromMillisecondsSinceEpoch(0);
  String get title => prefs.getString('title') ?? 'Sir';
  String get lang => prefs.getString('language_mode') == 'Hindi' ? 'hi-IN' : 'en-IN';
  String get offlineMsg => '$title, internet connection nahi hai. Main offline commands kar sakta hoon.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    backgroundSub = backgroundEvents.receiveBroadcastStream().listen((event) {
      if (!mounted || !on || busy || event == null) return;
      final text = event.toString().trim();
      if (text.isNotEmpty) {
        setState(() { heard = text; status = 'Heard in background'; });
        if (wake.hasMatch(text.toLowerCase())) run(text);
      }
    }, onError: (_) {});
    Future.microtask(() async {
      await tts.awaitSpeakCompletion(true);
      await speak('Welcome $title to Zyfer');
      await beepMute(true);
      start();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    if (st == AppLifecycleState.resumed) {
      nativeCall('stopBackgroundListening');
      if (on) { beepMute(true); scheduleListen(400); }
    } else if (st == AppLifecycleState.paused) {
      beepMute(false);
      if (on) { stt.stop(); nativeCall('startBackgroundListening', {'locale': lang.replaceAll('-', '_')}); }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    restartT?.cancel();
    debT?.cancel();
    backgroundSub?.cancel();
    nativeCall('stopBackgroundListening');
    beepMute(false);
    stt.stop();
    tts.stop();
    elevenPlayer.dispose();
    super.dispose();
  }

  Future<void> speak(String s) async {
    reply = s;
    if (mounted) setState(() {});
    if (s.trim().isEmpty) return;
    if (elevenLabsKey.isNotEmpty && elevenLabsVoiceId.isNotEmpty) {
      try {
        final response = await http.post(
          Uri.parse('https://api.elevenlabs.io/v1/text-to-speech/$elevenLabsVoiceId?output_format=mp3_44100_128'),
          headers: {
            'xi-api-key': elevenLabsKey,
            'Content-Type': 'application/json',
            'Accept': 'audio/mpeg',
          },
          body: jsonEncode({
            'text': s.length > 4500 ? s.substring(0, 4500) : s,
            'model_id': 'eleven_multilingual_v2',
            'voice_settings': {
              'stability': 0.42,
              'similarity_boost': 0.78,
              'style': 0.25,
              'use_speaker_boost': true,
            },
          }),
        ).timeout(const Duration(seconds: 25));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          await elevenPlayer.stop();
          final done = elevenPlayer.onPlayerComplete.first;
          await elevenPlayer.play(BytesSource(response.bodyBytes));
          await done.timeout(const Duration(minutes: 2));
          return;
        }
        final code = response.statusCode;
        final detail = utf8.decode(response.bodyBytes, allowMalformed: true);
        if (mounted) setState(() => err = 'ElevenLabs $code: ${_shortError(detail)}');
      } catch (e) {
        if (mounted) setState(() => err = 'ElevenLabs voice unavailable: $e');
      }
    } else if (mounted) {
      setState(() => err = 'ElevenLabs key missing; using phone voice.');
    }
    try {
      await tts.setLanguage(lang);
      await tts.setPitch((prefs.getBool('male') ?? true) ? 0.8 : 1.1);
      await tts.speak(s);
    } catch (e) {
      if (mounted) setState(() => err = 'Phone voice error: $e');
    }
  }

  String _shortError(String value) {
    final clean = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.length > 180 ? clean.substring(0, 180) : clean;
  }

  Future<bool> online() async =>
      !(await Connectivity().checkConnectivity()).contains(ConnectivityResult.none);

  Future<void> start() async {
    final ok = await stt.initialize(
        onError: (e) async {
          final quiet = e.errorMsg == 'error_speech_timeout' ||
              e.errorMsg == 'error_no_match' ||
              e.errorMsg == 'error_busy';
          if (mounted) setState(() => err = quiet ? '' : 'Error: ${e.errorMsg}');
          if (e.errorMsg == 'error_busy') {
            try {
              await stt.cancel();
            } catch (_) {}
            if (on && !busy) scheduleListen(1500);
            return;
          }
          if (on && !busy) scheduleListen(1000);
        },
        onStatus: (s) {
          if ((s == 'done' || s == 'notListening') && on && !busy) scheduleListen(900);
        });
    if (!ok) {
      if (mounted) setState(() => status = 'Speech service not found. Check Google app / Speech services');
      return;
    }
    listenOnce();
  }

  Future<void> listenOnce() async {
    if (!mounted || !on || busy || starting || stt.isListening) return;
    starting = true;
    try {
      if (mounted) setState(() => status = 'Say Krishna... I am listening');
      await stt.listen(
          localeId: lang.replaceAll('-', '_'),
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
          onResult: (r) {
            final text = r.recognizedWords;
            if (mounted) setState(() => heard = text);
            latest = text;
            final w = text.toLowerCase();
            final follow = DateTime.now().isBefore(activeUntil);
            if (w.trim().isEmpty || !(wake.hasMatch(w) || follow)) return;
            debT?.cancel();
            if (r.finalResult) {
              run(text);
            } else {
              debT = Timer(const Duration(milliseconds: 1400), () => run(latest));
            }
          });
    } finally {
      starting = false;
    }
  }

  Future<void> run(String text) async {
    if (busy) return;
    busy = true;
    await stt.stop();
    await handle(text);
    activeUntil = DateTime.now().add(const Duration(seconds: 30));
    await Future.delayed(const Duration(milliseconds: 800));
    busy = false;
    listenOnce();
  }

  Future<void> handle(String raw) async {
    final low = raw.toLowerCase();
    final w = wake.firstMatch(low);
    final t = (w == null ? low : low.substring(w.end)).replaceFirst(RegExp(r'^[,\s]+'), '').trim();
    if (t.isEmpty) return speak('Yes $title');

    if (RegExp(r'(stop yourself|stop listening|stop listening now|pause listening|app band kar|sunna band kar|listening band kar|zyfer band kar)').hasMatch(t)) {
      on = false;
      activeUntil = DateTime.fromMillisecondsSinceEpoch(0);
      restartT?.cancel();
      debT?.cancel();
      await stt.stop();
      await beepMute(false);
      if (mounted) setState(() => status = 'Paused by voice. Tap the mic to resume.');
      return speak('Okay $title, listening is paused. Tap the microphone when you want me back.');
    }

    if (RegExp(r'(talk as friend|talk like a friend|friend mode|dost ki tarah|dost jaisa|dost banke|dost ban ke|friend ki tarah|mujhse dost)').hasMatch(t)) {
      await prefs.setBool('friend_mode', true);
      return speak('Done! Ab main aapse dost ki tarah baat karunga.');
    }
    if (RegExp(r'(normal mode|talk normally|sir mode|wapas normal|ab normal|mujhe sir bolo|tu sir bol|sir bolke baat kar)').hasMatch(t)) {
      await prefs.setBool('friend_mode', false);
      await prefs.setString('title', 'Sir');
      return speak('Certainly, Sir. Normal respectful mode is on.');
    }
    if (RegExp(r'(call me jaan|mujhe jaan bulao|jaan bulao)').hasMatch(t)) {
      await prefs.setString('title', 'Jaan');
      return speak('Okay, Jaan.');
    }
    if (RegExp(r'(call me sir|mujhe sir bulao|sir bulao)').hasMatch(t)) {
      await prefs.setString('title', 'Sir');
      return speak('Of course, Sir.');
    }
    if (RegExp(r'(speak|language|bhasha).*(english|angrezi)').hasMatch(t)) {
      await prefs.setString('language_mode', 'English');
      return speak('English mode is on, Sir.');
    }
    if (RegExp(r'(speak|language|bhasha).*(hindi)').hasMatch(t)) {
      await prefs.setString('language_mode', 'Hindi');
      return speak('Hindi mode chalu kar diya hai, Sir.');
    }
    if (RegExp(r'(speak|language|bhasha).*(hinglish|mix language)').hasMatch(t)) {
      await prefs.setString('language_mode', 'Hinglish');
      return speak('Hinglish mode is on, Sir.');
    }

    final m = RegExp(r'(madam|sir)\s*(bulao|bolo|bulana)|call me (madam|sir)|address me as (madam|sir)').firstMatch(t);
    if (m != null) {
      final v = (m.group(1) ?? m.group(3)) == 'madam' ? 'Madam' : 'Sir';
      await prefs.setString('title', v);
      return speak('Okay, $v');
    }
    if (t.length < 40 && RegExp(r'\b(time|samay|kitne baje|baje)\b').hasMatch(t)) {
      final n = DateTime.now();
      final h = n.hour % 12 == 0 ? 12 : n.hour % 12;
      final m = n.minute.toString().padLeft(2, '0');
      final ap = n.hour >= 12 ? 'PM' : 'AM';
      return speak('$title, it is $h:$m $ap');
    }
    if (t.length < 40 && RegExp(r'\b(date|tarikh|aaj kaun sa din|today)\b').hasMatch(t)) {
      const d = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      final n = DateTime.now();
      return speak('$title, today is ${d[n.weekday - 1]}, ${n.day}/${n.month}/${n.year}');
    }
    if (RegExp(r'\b(alarm|wake me)\b').hasMatch(t)) {
      if (!allowed('c_alarm')) return speak('Alarm control is off, $title. Turn it on in settings.');
      final r = parseTime(t);
      if (r == null) return speak('Please tell me the time, like set an alarm for 7:30 AM.');
      final ok = await nativeCall('setAlarm', {'hour': r[0], 'minute': r[1]});
      return speak(ok == true ? 'Alarm set for ${fmt12(r[0], r[1])}' : 'Sorry $title, I could not set the alarm.');
    }
    final tm = RegExp(r'timer.*?(\d+)\s*(second|sec|minute|min|hour|hr)').firstMatch(t);
    if (tm != null) {
      if (!allowed('c_alarm')) return speak('Timer control is off, $title. Turn it on in settings.');
      final n = int.parse(tm.group(1)!);
      final u = tm.group(2)!;
      final secs = u.startsWith('h') ? n * 3600 : (u.startsWith('m') ? n * 60 : n);
      final ok = await nativeCall('setTimer', {'seconds': secs});
      return speak(ok == true ? 'Timer set for $n $u${n == 1 ? '' : 's'}' : 'Sorry $title, I could not set the timer.');
    }
    // Parse search commands before generic app launch commands.
    final yt = RegExp(r'(?:youtube|you tube).*?(?:search|find|dhundo|dhoondo|khojo|talash karo)\s+(.+)$|(?:search|dhundo|dhoondo|khojo|talash karo)\s+(.+?)\s+(?:on|in)\s+youtube$').firstMatch(t);
    if (yt != null) {
      final q = (yt.group(1) ?? yt.group(2) ?? '').trim();
      if (q.isNotEmpty) {
        if (!allowed('c_search')) return speak('Search is off, $title. Turn it on in settings.');
        if (!await online()) return speak(offlineMsg);
        final ok = await launchUrl(Uri.parse('https://www.youtube.com/results?search_query=${Uri.encodeComponent(q)}'), mode: LaunchMode.externalApplication);
        return speak(ok ? 'Searching YouTube for $q' : 'Sorry $title, YouTube search could not be opened.');
      }
    }
    if (RegExp(r'\b(open|kholo|khol)\s+(youtube|you tube)\b').hasMatch(t)) {
      final ok = await launchUrl(Uri.parse('https://www.youtube.com'), mode: LaunchMode.externalApplication);
      return speak(ok ? 'Opening YouTube, $title' : 'Sorry $title, YouTube could not be opened.');
    }
    final google = RegExp(r'^google\s+(?:pe|par)\s+(.+?)\s+(?:search|search karo|dhundo|dhoondo|khojo|talash karo)$|^(.+?)\s+google\s+(?:pe|par)\s+(?:search|search karo|dhundo|dhoondo|khojo|talash karo)$|^(?:search|search karo|google|look up|find|dhundo|dhoondo|khojo|talash karo)\s+(?:for\s+)?(.+)$').firstMatch(t);
    if (google != null) {
      final q = (google.group(1) ?? google.group(2) ?? google.group(3) ?? '').trim();
      if (q.isNotEmpty) {
        if (!allowed('c_search')) return speak('Search is off, $title. Turn it on in settings.');
        if (!await online()) return speak(offlineMsg);
        final ok = await launchUrl(Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent(q)}'), mode: LaunchMode.externalApplication);
        return speak(ok ? 'Searching Google for $q' : 'Sorry $title, Google search could not be opened.');
      }
    }
    final op = RegExp(r'^(?:please\s+)?(?:open|launch|start|kholo|khol)\s+(?:the\s+)?(.+?)(?:\s+app)?$').firstMatch(t);
    if (op != null) {
      if (!allowed('c_open')) return speak('App control is off, $title. Turn it on in settings.');
      final name = op.group(1)!.trim();
      final label = await nativeCall('openApp', {'name': name});
      return speak(label != null ? 'Opening $label' : 'I could not find $name on your phone');
    }
    if (!await online()) return speak(offlineMsg);
    return speak(await ask(t));
  }

  Future<String> ask(String q) async {
    if (mounted) setState(() => err = '');
    if (groqKey.isEmpty) {
      if (mounted) setState(() => err = 'Groq key missing. Add GROQ_KEY in GitHub Secrets.');
      return '$title, AI key setup is incomplete. Please check the app configuration.';
    }
    try {
      final style = friendMode
          ? 'Talk like a warm, natural close friend: casual, friendly and lightly humorous when appropriate. Do not force Sir into every sentence in friend mode.'
          : 'Use a respectful, helpful assistant tone. Address the user as Sir consistently and naturally by default.';
      final languageRule = 'Always answer in $responseLanguage. Be conversational, natural and genuinely helpful. '
          'Answer the actual question directly and completely; use enough detail for the question instead of forcing every reply to be short. '
          'For simple questions be brief; for explanations, comparisons or how-to questions give clear step-by-step detail when useful. '
          'If you are unsure, say so rather than inventing facts. You do not have live web access in this app, so do not pretend to know breaking or current information. '
          'Use plain text suitable for speech; avoid markdown tables and excessive formatting.';
      final system = {
        'role': 'system',
        'content': 'You are ZYFER, created by Krishna. Your wake words are Krish and Krishna. You are the user\'s capable personal phone assistant. $style $languageRule '
            'Never claim you opened an app, searched, set an alarm, or performed an action unless the app actually did it. '
            'For unsupported actions, explain the limitation honestly. Address the user as ${prefs.getString('title') ?? 'Sir'} unless the user explicitly changes it.'
      };
      final messages = <Map<String, String>>[system];
      messages.addAll(chatHistory.take(12));
      messages.add({'role': 'user', 'content': q});
      final r = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {'Authorization': 'Bearer $groqKey', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': model,
          'messages': messages,
          'max_completion_tokens': 900,
        }),
      ).timeout(const Duration(seconds: 25));
      if (r.statusCode != 200) {
        final detail = _shortError(utf8.decode(r.bodyBytes, allowMalformed: true));
        if (mounted) setState(() => err = 'Groq API ${r.statusCode}: $detail');
        if (r.statusCode == 401) return '$title, Groq API key is invalid or not accepted.';
        if (r.statusCode == 429) return '$title, AI service is busy or usage limit reached. Please try again shortly.';
        if (r.statusCode >= 500) return '$title, AI service is temporarily unavailable. Please try again.';
        return '$title, AI request failed (${r.statusCode}). Please check the error shown on screen.';
      }
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      final answer = (decoded['choices']?[0]?['message']?['content'] ?? '').toString().trim();
      if (answer.isEmpty) return '$title, I received an empty answer. Please ask once more.';
      chatHistory.add({'role': 'user', 'content': q});
      chatHistory.add({'role': 'assistant', 'content': answer});
      if (chatHistory.length > 12) chatHistory.removeRange(0, chatHistory.length - 12);
      return answer;
    } on http.ClientException catch (e) {
      if (mounted) setState(() => err = 'Network error: $e');
      return '$title, network problem aa rahi hai. Please check your internet.';
    } on FormatException catch (e) {
      if (mounted) setState(() => err = 'Invalid API response: $e');
      return '$title, AI response samajh nahi aaya. Please try again.';
    } catch (e) {
      if (mounted) setState(() => err = 'Groq request error: $e');
      return '$title, AI abhi respond nahi kar pa raha. Thodi der baad try kijiye.';
    }
  }

  @override
  Widget build(BuildContext c) => Shell(Column(children: [
        Align(alignment: Alignment.topRight, child: IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () => Navigator.pushReplacement(c, MaterialPageRoute(builder: (_) => const Setup())))),
        const Spacer(),
        const ZyferOrb(size: 116), const SizedBox(height: 12),
        Text('Welcome $title to Zyfer${friendMode ? ' · Friend mode' : ''}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(heard.isEmpty ? '' : '🎤 $heard', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70))),
        const SizedBox(height: 8),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(reply, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18))),
        const SizedBox(height: 8),
        Text(err, textAlign: TextAlign.center, style: const TextStyle(color: Colors.amber)),
        const Spacer(),
        GestureDetector(
            onTap: () async {
              if (on) {
                on = false;
                await stt.stop();
                await nativeCall('stopBackgroundListening');
                await beepMute(false);
                setState(() => status = 'Paused. Tap the mic to resume');
              } else {
                setState(() => on = true);
                await beepMute(true);
                listenOnce();
              }
            },
            child: CircleAvatar(radius: 40, backgroundColor: Colors.white,
                child: Icon(on ? Icons.mic : Icons.mic_off, size: 40, color: on ? bg : Colors.grey))),
        const SizedBox(height: 8),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(status, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70))),
        const SizedBox(height: 32)]));
}
