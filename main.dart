import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
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
const audioCh = MethodChannel('zyfer/audio');
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
  String lang = 'en-IN', title = 'Sir', voice = 'Male';

  Widget chips(List<String> o, String cur, void Function(String) on) => Wrap(spacing: 8, children: [
        for (final x in o) ChoiceChip(label: Text(x), selected: cur == x, onSelected: (_) => setState(() => on(x)))]);

  @override
  Widget build(BuildContext c) => Shell(ListView(padding: const EdgeInsets.all(24), children: [
        Center(child: logo(80)), const SizedBox(height: 20),
        TextField(controller: name, style: white, decoration: deco('Your name')),
        const SizedBox(height: 14),
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

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeS();
}

class _HomeS extends State<Home> with WidgetsBindingObserver {
  static const model = 'llama-3.3-70b-versatile';
  static final wake = RegExp(
      r'(krishna|krishn|krisna|krsna|kishna|kreshna|krishnaa|christina|crishna|\u0915\u0943\u0937\u094d\u0923|\u0915\u094d\u0930\u093f\u0936\u094d\u0928|\u0915\u0943\u0937\u0928|\u0915\u093f\u0937\u094d\u0928)');
  Timer? restartT, debT;
  String latest = '';

  void scheduleListen([int ms = 900]) {
    restartT?.cancel();
    restartT = Timer(Duration(milliseconds: ms), listenOnce);
  }
  final stt = SpeechToText();
  final tts = FlutterTts();
  String status = 'Starting...', heard = '', reply = '', err = '';
  bool on = true, busy = false, starting = false;
  DateTime activeUntil = DateTime.fromMillisecondsSinceEpoch(0);
  String get title => prefs.getString('title') ?? 'Sir';
  String get lang => 'en-IN';
  String get offlineMsg => 'Hi buddy $title, your internet is off, I cannot do that.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      if (on) beepMute(true);
    } else if (st == AppLifecycleState.paused) {
      beepMute(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    restartT?.cancel();
    debT?.cancel();
    beepMute(false);
    stt.stop();
    tts.stop();
    super.dispose();
  }

  Future<void> speak(String s) async {
    reply = s;
    if (mounted) setState(() {});
    await tts.setLanguage(lang);
    await tts.setPitch((prefs.getBool('male') ?? true) ? 0.8 : 1.3);
    await tts.speak(s);
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
    if (t.contains('youtube')) {
      final s = RegExp(r'search\s+(.+)').firstMatch(t);
      if (s != null) {
        if (!await online()) return speak(offlineMsg);
        await launchUrl(Uri.parse('https://www.youtube.com/results?search_query=${Uri.encodeComponent(s.group(1)!)}'),
            mode: LaunchMode.externalApplication);
        return speak('Searching YouTube for ${s.group(1)}');
      }
      await launchUrl(Uri.parse('https://www.youtube.com'), mode: LaunchMode.externalApplication);
      return speak('Opening YouTube, $title');
    }
    final op = RegExp(r'^(?:please\s+)?(?:open|launch|start)\s+(?:the\s+)?(.+?)(?:\s+app)?$').firstMatch(t);
    if (op != null) {
      if (!allowed('c_open')) return speak('App control is off, $title. Turn it on in settings.');
      final name = op.group(1)!.trim();
      final label = await nativeCall('openApp', {'name': name});
      return speak(label != null ? 'Opening $label' : 'I could not find $name on your phone');
    }
    final sr = RegExp(r'^(?:search|google|look up|find)\s+(?:for\s+)?(.+)$').firstMatch(t);
    if (sr != null) {
      if (!allowed('c_search')) return speak('Search is off, $title. Turn it on in settings.');
      if (!await online()) return speak(offlineMsg);
      await launchUrl(Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent(sr.group(1)!)}'),
          mode: LaunchMode.externalApplication);
      return speak('Searching for ${sr.group(1)}');
    }
    if (!await online()) return speak(offlineMsg);
    return speak(await ask(t));
  }

  Future<String> ask(String q) async {
    try {
      final r = await http.post(
          Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $groqKey',
            'content-type': 'application/json'
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {
                'role': 'system',
                'content': 'You are Zyfer, a voice assistant. The user calls you Krishna. Address the user as $title (name: ${prefs.getString('name')}). '
                    'Reply short (1-3 sentences), ALWAYS in simple English only (never Hindi or Hinglish), plain text only, no markdown.'
              },
              {'role': 'user', 'content': q}
            ]
          }));
      if (r.statusCode != 200) {
        if (mounted) setState(() => err = 'API ${r.statusCode}: ${utf8.decode(r.bodyBytes)}');
        return 'API error ${r.statusCode}. $title, please check the key.';
      }
      return jsonDecode(utf8.decode(r.bodyBytes))['choices'][0]['message']['content'];
    } catch (e) {
      if (mounted) setState(() => err = '$e');
      return 'Something went wrong, $title.';
    }
  }

  @override
  Widget build(BuildContext c) => Shell(Column(children: [
        Align(alignment: Alignment.topRight, child: IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () => Navigator.pushReplacement(c, MaterialPageRoute(builder: (_) => const Setup())))),
        const Spacer(),
        logo(110), const SizedBox(height: 12),
        Text('Welcome $title to Zyfer', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
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
