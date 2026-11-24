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
const audioCh = MethodChannel('zyfer/audio');
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
  final name = TextEditingController(), key = TextEditingController();
  String lang = 'en-IN', title = 'Sir', voice = 'Male';

  Widget chips(List<String> o, String cur, void Function(String) on) => Wrap(spacing: 8, children: [
        for (final x in o) ChoiceChip(label: Text(x), selected: cur == x, onSelected: (_) => setState(() => on(x)))]);

  @override
  Widget build(BuildContext c) => Shell(ListView(padding: const EdgeInsets.all(24), children: [
        Center(child: logo(80)), const SizedBox(height: 20),
        TextField(controller: name, style: white, decoration: deco('Your name')),
        const SizedBox(height: 14),
        TextField(controller: key, style: white, obscureText: true, decoration: deco('API key')),
        const SizedBox(height: 18),
        const Text('Voice language', style: white),
        chips(['en-IN', 'hi-IN'], lang, (x) => lang = x),
        const SizedBox(height: 10),
        const Text('Voice type', style: white),
        chips(['Male', 'Female'], voice, (x) => voice = x),
        const SizedBox(height: 10),
        const Text('Mujhe bulao', style: white),
        chips(['Sir', 'Madam'], title, (x) => title = x),
        const SizedBox(height: 24),
        ElevatedButton(
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
            onPressed: () async {
              await prefs.setString('name', name.text.trim());
              await prefs.setString('key', key.text.trim());
              await prefs.setString('lang', lang);
              await prefs.setString('title', title);
              await prefs.setBool('male', voice == 'Male');
              if (!mounted) return;
              Navigator.push(context, MaterialPageRoute(builder: (_) => const Perms()));
            },
            child: const Text('GO', style: TextStyle(fontSize: 18)))]));
}

class Perms extends StatelessWidget {
  const Perms({super.key});
  @override
  Widget build(BuildContext c) => Shell(Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.lock_open, color: Colors.white, size: 70), const SizedBox(height: 16),
        const Text('Permissions chahiye:\nMicrophone, Notifications,\nDisplay over other apps (app control)',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 18)),
        const SizedBox(height: 24),
        ElevatedButton(
            onPressed: () async {
              await [Permission.microphone, Permission.notification, Permission.systemAlertWindow].request();
              await prefs.setBool('setup', true);
              if (!c.mounted) return;
              Navigator.pushAndRemoveUntil(c, MaterialPageRoute(builder: (_) => const Home()), (_) => false);
            },
            child: const Text('Allow permissions'))])));
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeS();
}

class _HomeS extends State<Home> with WidgetsBindingObserver {
  static const model = 'llama-3.3-70b-versatile';
  static final wake = RegExp(r'(zyfer|zypher|zaifer|zaiphar|cipher|saifer|jaifer|zifer|zifar|zyfar|zayfer|sifer|jarvis|zaifar|jaiphar|saiphar)');
  final stt = SpeechToText();
  final tts = FlutterTts();
  String status = 'Shuru ho raha hai...', heard = '', reply = '', err = '';
  bool on = true, busy = false, starting = false;
  DateTime activeUntil = DateTime.fromMillisecondsSinceEpoch(0);
  String get title => prefs.getString('title') ?? 'Sir';
  String get lang => prefs.getString('lang') ?? 'en-IN';
  String get offlineMsg => 'Hi buddy $title, aapka internet off hai, main ye nahi kar sakta.';

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
        onError: (e) {
          final quiet = e.errorMsg == 'error_speech_timeout' || e.errorMsg == 'error_no_match';
          if (mounted) setState(() => err = quiet ? '' : 'Error: ${e.errorMsg}');
          if (on && !busy) Future.delayed(const Duration(milliseconds: 1200), listenOnce);
        },
        onStatus: (s) {
          if ((s == 'done' || s == 'notListening') && on && !busy) {
            Future.delayed(const Duration(milliseconds: 700), listenOnce);
          }
        });
    if (!ok) {
      if (mounted) setState(() => status = 'Speech service nahi mili. Google app / Speech services check karo');
      return;
    }
    listenOnce();
  }

  Future<void> listenOnce() async {
    if (!mounted || !on || busy || starting || stt.isListening) return;
    starting = true;
    try {
      if (mounted) setState(() => status = 'Zyfer bolo... main sun raha hu');
      await stt.listen(
          localeId: lang.replaceAll('-', '_'),
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
          onResult: (r) {
            if (mounted) setState(() => heard = r.recognizedWords);
            if (!r.finalResult) return;
            final w = r.recognizedWords.toLowerCase();
            final follow = DateTime.now().isBefore(activeUntil);
            if (w.trim().isNotEmpty && (wake.hasMatch(w) || follow)) run(r.recognizedWords);
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
    final m = RegExp(r'(madam|sir)\s*(bulao|bolo|bulana)|call me (madam|sir)').firstMatch(t);
    if (m != null) {
      final v = (m.group(1) ?? m.group(3)) == 'madam' ? 'Madam' : 'Sir';
      await prefs.setString('title', v);
      return speak('Theek hai $v');
    }
    if (t.length < 40 && RegExp(r'\b(time|samay|kitne baje|baje)\b').hasMatch(t)) {
      final n = DateTime.now();
      final h = n.hour % 12 == 0 ? 12 : n.hour % 12;
      final m = n.minute.toString().padLeft(2, '0');
      final ap = n.hour >= 12 ? 'PM' : 'AM';
      return speak('$title abhi $h:$m $ap ho rahe hain');
    }
    if (t.length < 40 && RegExp(r'\b(date|tarikh|aaj kaun sa din|today)\b').hasMatch(t)) {
      const d = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      final n = DateTime.now();
      return speak('$title aaj ${d[n.weekday - 1]} hai, ${n.day}/${n.month}/${n.year}');
    }
    if (t.contains('youtube')) {
      final s = RegExp(r'search\s+(.+)').firstMatch(t);
      if (s != null) {
        if (!await online()) return speak(offlineMsg);
        await launchUrl(Uri.parse('https://www.youtube.com/results?search_query=${Uri.encodeComponent(s.group(1)!)}'),
            mode: LaunchMode.externalApplication);
        return speak('YouTube pe ${s.group(1)} search kar raha hu');
      }
      await launchUrl(Uri.parse('https://www.youtube.com'), mode: LaunchMode.externalApplication);
      return speak('YouTube khol raha hu $title');
    }
    if (!await online()) return speak(offlineMsg);
    return speak(await ask(t));
  }

  Future<String> ask(String q) async {
    try {
      final r = await http.post(
          Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer ${prefs.getString('key') ?? ''}',
            'content-type': 'application/json'
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {
                'role': 'system',
                'content': 'You are Zyfer, a voice assistant. Address the user as $title (name: ${prefs.getString('name')}). '
                    'Reply short (1-3 sentences), in the same language the user spoke, plain text only, no markdown.'
              },
              {'role': 'user', 'content': q}
            ]
          }));
      if (r.statusCode != 200) {
        if (mounted) setState(() => err = 'API ${r.statusCode}: ${utf8.decode(r.bodyBytes)}');
        return 'API error ${r.statusCode}. $title, key check karo.';
      }
      return jsonDecode(utf8.decode(r.bodyBytes))['choices'][0]['message']['content'];
    } catch (e) {
      if (mounted) setState(() => err = '$e');
      return 'Kuch gadbad ho gayi $title.';
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
                setState(() => status = 'Pause. Mic dabao dobara shuru karne ke liye');
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
