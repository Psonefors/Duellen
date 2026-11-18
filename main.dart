import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'game.dart';

const ink = Color(0xff101426);
const panel = Color(0xff1b233d);
const lime = Color(0xffd6ff61);
const muted = Color(0xffaeb9d3);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DuellenApp());
}

class DuellenApp extends StatelessWidget {
  const DuellenApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'DUELLEN',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          scaffoldBackgroundColor: ink,
          colorScheme: ColorScheme.fromSeed(seedColor: lime, brightness: Brightness.dark),
          cardTheme: const CardThemeData(color: panel, elevation: 0),
          inputDecorationTheme: InputDecorationTheme(
            filled: true, fillColor: const Color(0xff121a31),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          ),
        ),
        home: const HostPage(),
      );
}

class HostPage extends StatefulWidget {
  const HostPage({super.key});
  @override
  State<HostPage> createState() => _HostPageState();
}

class _HostPageState extends State<HostPage> {
  final game = DuellenGame();
  final ipController = TextEditingController();
  final sound = AudioPlayer();
  final answerMusic = AudioPlayer();
  final tickSound = AudioPlayer();
  bool loading = false, soundOn = true, showPlayer = false;
  WebViewController? localPlayer;
  String previousPhase = 'lobby';
  int previousSecond = 100, previousQualified = 0;

  static const modes = <String, String>{
    'normal': '🧠 Kunskapsfråga',
    'risk': '🎲 Riskrunda',
    'duel': '⚔️ Duell',
    'closest': '🎯 Närmast vinner',
    'surprise': '🎁 Överraskning',
    'relation': '❤️ Relationsduellen',
  };

  @override
  void initState() {
    super.initState();
    game.addListener(_update);
    game.startServer().then((_) {
      if (!mounted) return;
      localPlayer = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(Uri.parse('http://127.0.0.1:8765/'));
      setState(() {});
    });
  }

  void _play(String file) {
    if (!soundOn) return;
    // UI-ljud får aldrig blockera en spelomgång.
    sound.stop().then((_) => sound.play(AssetSource('audio/$file'))).catchError((Object _) {});
  }

  void _update() {
    if (!mounted) return;
    final phase = game.phase;
    if (phase != previousPhase) {
      if (phase == 'countdown') _play('next.wav');
      if (phase == 'question') {
        if (game.roundMode != 'relation' && soundOn) {
          answerMusic.setReleaseMode(ReleaseMode.loop).then((_) => answerMusic.play(AssetSource('audio/answer_music.wav'))).catchError((Object _) {});
        }
      } else { answerMusic.stop(); }
      if (phase == 'reveal' || phase == 'finished') {
        final qualified = game.teams.values.where((t) => t.qualified).length;
        _play(qualified > previousQualified ? 'win.wav' : 'reveal.wav');
        previousQualified = qualified;
      }
      if (phase != 'question') answerMusic.setVolume(1.0);
      previousPhase = phase;
      previousSecond = 100;
    }
    if (phase == 'countdown') {
      final sec=game.countdownRemaining;
      if(sec<=5 && sec>0 && sec!=previousSecond && soundOn) tickSound.play(AssetSource('audio/tick.wav')).catchError((Object _) {});
      previousSecond=sec;
    }
    if (phase == 'question' && game.roundMode != 'relation') {
      final sec = game.remaining;
      if (sec <= 5 && sec > 0 && sec != previousSecond && soundOn) {
        answerMusic.setVolume(0.23);
        tickSound.stop().then((_) => tickSound.play(AssetSource('audio/tick.wav'))).catchError((Object _) {});
      }
      previousSecond = sec;
    }
    setState(() {});
  }

  @override
  void dispose() {
    game.removeListener(_update);
    game.dispose();
    ipController.dispose();
    sound.dispose();
    answerMusic.dispose();
    tickSound.dispose();
    super.dispose();
  }

  Future<void> start() async {
    setState(() => loading = true);
    await game.startGame();
    if (mounted) setState(() => loading = false);
  }

  Future<void> confirmEnd() async {
    final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:const Text('Avsluta matchen?'),
      content:const Text('Pågående omgång avbryts utan nya poäng. Högst poäng vinner, och lika poäng ger delad seger.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Fortsätt spela')),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Avsluta matchen'))]));
    if(yes==true) {game.endEarly();setState(()=>showPlayer=false);}
  }

  Widget panelCard(String title, Widget body, {IconData? icon}) => Card(
        margin: const EdgeInsets.only(bottom: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              if (icon != null) ...[Icon(icon, color: lime, size: 21), const SizedBox(width: 9)],
              Expanded(child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 14),
            body,
          ]),
        ),
      );

  Widget rowText(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [Expanded(child: Text(k, style: const TextStyle(color: muted))), Text(v, style: const TextStyle(fontWeight: FontWeight.bold))]),
      );

  Widget largeButton(String label, VoidCallback? onPressed, {IconData icon = Icons.arrow_forward_rounded}) =>
      Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SizedBox(width: double.infinity, height: 84,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: lime, foregroundColor: ink,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              elevation: 2,
            ),
            onPressed: onPressed,
            icon: Icon(icon, size: 30),
            label: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          )),
      ));

  Widget badges(Set<String> earned) => Row(children: List.generate(3, (i) {
        final completed = i < earned.length;
        return Padding(padding: const EdgeInsets.only(right: 7), child: Container(
          width: 35, height: 35,
          decoration: BoxDecoration(
            color: completed ? [const Color(0xffa584ff), const Color(0xff47d9c2), const Color(0xffffbd72)][i] : const Color(0xff303952),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: completed ? Colors.white30 : Colors.white10),
          ),
          child: Icon(completed ? Icons.verified_rounded : Icons.lock_outline_rounded,
              size: 20, color: completed ? ink : muted),
        ));
      }));

  Widget teamScore(QuizTeam t) {
    final proportion = (t.points / 10).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: const Color(0xff121a31), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${t.place != null ? '🏆 ${t.place}. ' : ''}${t.name}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16), overflow: TextOverflow.ellipsis)),
          Text('${t.points} / 10', style: const TextStyle(fontWeight: FontWeight.w900, color: lime, fontSize: 20)),
        ]),
        const SizedBox(height: 9),
        ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(
          value: proportion, minHeight: 9,
          color: t.qualified ? const Color(0xff47d9c2) : lime,
          backgroundColor: const Color(0xff303952),
        )),
        const SizedBox(height: 10),
        Row(children: [badges(t.badges), const SizedBox(width: 8), Text('${t.badges.length.clamp(0, 3)} av 3 kategorier',
          style: const TextStyle(color: muted, fontSize: 12))]),
        if (t.badges.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: Text(t.badges.join(' · '),
          style: const TextStyle(color: muted, fontSize: 11))),
      ]),
    );
  }

  Widget relationSelectors(List<QuizTeam> actors) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Förutbestämt par (används i Relationsduellen):', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 7),
        DropdownButtonFormField<String>(
          value: actors.any((t) => t.id == game.selectedFirst) ? game.selectedFirst : null,
          decoration: const InputDecoration(labelText: 'Person 1'),
          items: actors.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
          onChanged: (v) => setState(() => game.selectedFirst = v ?? ''),
        ),
        const SizedBox(height: 9),
        DropdownButtonFormField<String>(
          value: actors.any((t) => t.id == game.selectedSecond) ? game.selectedSecond : null,
          decoration: const InputDecoration(labelText: 'Person 2'),
          items: actors.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
          onChanged: (v) => setState(() => game.selectedSecond = v ?? ''),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final lobby = game.phase == 'lobby';
    final reveal = game.phase == 'reveal' || game.phase == 'finished';
    final ready = game.phase == 'ready' || game.phase == 'reveal';
    final actors = game.eligible;
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚔️ DUELLEN', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        backgroundColor: ink,
        actions: [if(!lobby && game.phase!='finished') IconButton(
          tooltip:'Avsluta matchen',onPressed:confirmEnd,
          icon:const Icon(Icons.flag_rounded,color:Color(0xffff9292))),IconButton(
          tooltip: soundOn ? 'Stäng av ljud' : 'Slå på ljud',
          onPressed: () { setState(() => soundOn = !soundOn); if (!soundOn) {answerMusic.stop();tickSound.stop();sound.stop();} },
          icon: Icon(soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded, color: lime),
        ), const SizedBox(width: 8)],
      ),
      body: Column(children:[
        if(localPlayer!=null) Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),
          child:SegmentedButton<bool>(segments:const [
            ButtonSegment(value:false,label:Text('🎤 Spelledare'),icon:Icon(Icons.settings_rounded)),
            ButtonSegment(value:true,label:Text('🎮 Mina svar'),icon:Icon(Icons.sports_esports_rounded))
          ],selected:{showPlayer},onSelectionChanged:(s)=>setState(()=>showPlayer=s.first))),
        Expanded(child: IndexedStack(index:showPlayer && localPlayer!=null ? 1 : 0,children:[
          ListView(padding: const EdgeInsets.fromLTRB(13, 8, 13, 30), children: [
        Container(
          padding: const EdgeInsets.all(18),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xff343065), Color(0xff1b2a46)]),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('FAMILJ • VÄNNER • TAKTIK', style: TextStyle(color: lime, letterSpacing: 2, fontWeight: FontWeight.w700, fontSize: 11)),
            const SizedBox(height: 9),
            Text(lobby ? 'Redo för spelkväll?' : game.phase == 'finished' ? '🏆 Matchen är klar!' : 'Runda ${game.round}',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text(lobby ? 'Anslut, välj läge och sätt igång.' :
              '10 poäng + 3 kategorier för att gå i mål', style: const TextStyle(color: muted)),
          ]),
        ),
        if (game.error.isNotEmpty) Card(color: const Color(0xff693339), child: Padding(
          padding: const EdgeInsets.all(14), child: Text(game.error))),
        if (lobby) ...[
          panelCard('1. Välj spelupplägg', Column(children: [
            DropdownButtonFormField<String>(
              value: game.flowMode,
              decoration: const InputDecoration(labelText: 'Hur väljs nästa runda?'),
              items: const [
                DropdownMenuItem(value: 'auto', child: Text('🎲 Automatiskt – spelet överraskar')),
                DropdownMenuItem(value: 'manual', child: Text('🎤 Manuellt – spelledaren väljer')),
              ],
              onChanged: (v) { if (v != null) game.setFlowMode(v); },
            ),
            const SizedBox(height: 11),
            DropdownButtonFormField<String>(
              value: game.difficulty,
              decoration: const InputDecoration(labelText: 'Svårighetsgrad'),
              items: const [
                DropdownMenuItem(value: 'easy', child: Text('🟢 Lätt')),
                DropdownMenuItem(value: 'medium', child: Text('🟡 Medel')),
                DropdownMenuItem(value: 'hard', child: Text('🔴 Svår')),
                DropdownMenuItem(value: 'mix', child: Text('🎲 Blandad (standard)')),
              ],
              onChanged: (v) { if(v!=null) game.setDifficulty(v); },
            ),
            const SizedBox(height: 11),
            DropdownButtonFormField<String>(
              value: game.relationsMode,
              decoration: const InputDecoration(labelText: 'Relationspar'),
              items: const [
                DropdownMenuItem(value: 'random', child: Text('Slumpa två deltagare')),
                DropdownMenuItem(value: 'manual', child: Text('Välj deltagare manuellt')),
              ],
              onChanged: (v) { if (v != null) game.setRelationsMode(v); },
            ),
            const SizedBox(height: 11),
            DropdownButtonFormField<String>(
              value: game.relationsRule,
              decoration: const InputDecoration(labelText: 'Relationsregler'),
              items: const [
                DropdownMenuItem(value: 'match', child: Text('❤️ Tänker lika')),
                DropdownMenuItem(value: 'trap', child: Text('🧠 Tankefällan')),
              ],
              onChanged: (v) { if (v != null) game.setRelationsRule(v); },
            ),
            if (game.flowMode == 'auto' && game.relationsMode == 'manual')
              const Padding(padding: EdgeInsets.only(top: 11), child: Text(
                'Relationsrundor väljs automatiskt först när två personer är valda.',
                style: TextStyle(color: muted, fontSize: 12),
              )),
          ]), icon: Icons.tune_rounded),
          panelCard('2. QR-kod och anslutning', Column(children: [
            const Text('Alla använder samma Wi-Fi eller huvudtelefonens hotspot.'),
            const SizedBox(height: 12),
            if (game.address.isNotEmpty) ...[
              Center(child: Container(color: Colors.white, padding: const EdgeInsets.all(12),
                child: QrImageView(data: game.address, size: 212))),
              const SizedBox(height: 8),
              SelectableText(game.address, textAlign: TextAlign.center),
            ] else const Text('Startar lokal server …'),
            ExpansionTile(title: const Text('Ändra IP-adress vid behov'), children: [
              TextField(controller: ipController, decoration: const InputDecoration(hintText: '192.168.43.1')),
              TextButton(onPressed: () => game.setIp(ipController.text), child: const Text('Använd adressen')),
            ]),
          ]), icon: Icons.qr_code_2_rounded),
          panelCard('3. Anslutna deltagare', Column(children: [
            for (final t in game.teams.values) rowText(t.name, '✓ Ansluten'),
            if (game.teams.isEmpty) const Text('Väntar på deltagare …', style: TextStyle(color: muted)),
            const SizedBox(height: 13),
            largeButton(loading ? 'LADDAR …' : 'STARTA SPELET',
              loading || game.teams.length < 2 ? null : start, icon: Icons.play_arrow_rounded),
          ]), icon: Icons.groups_rounded),
        ] else ...[
          if (ready) panelCard(
            reveal ? 'Resultatet är klart' : 'Nästa utmaning',
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (reveal) ...[
                if (game.roundMode == 'relation') ...[
                  Text(game.relationPrompt, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(game.relationSummary, style: const TextStyle(fontSize: 19, color: lime, fontWeight: FontWeight.w800)),
                ] else Text('Rätt svar: ${game.current?.answer ?? ''}',
                    style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: lime)),
                const SizedBox(height: 12),
                for (final t in game.teams.values) rowText('${t.name}: ${t.answered ? t.answer : '—'}',
                  '${t.change > 0 ? '+' : ''}${t.change} p'),
                const Divider(height: 28),
              ],
              if (game.phase != 'finished') ...[
                if (game.relationsMode == 'manual' && actors.length >= 2) ...[
                  relationSelectors(actors), const SizedBox(height: 14),
                ],
                if (game.flowMode == 'manual') ...[
                  const Text('Välj rundtyp:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: game.chosenMode,
                    items: modes.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (v) { if (v != null) setState(() => game.chosenMode = v); },
                  ),
                ] else const Padding(padding: EdgeInsets.symmetric(vertical: 10),
                  child: Center(child: Text('🎲 Nästa utmaning lottas automatiskt',
                  style: TextStyle(color: muted, fontSize: 15)))),
                const SizedBox(height: 16),
                largeButton('NÄSTA FRÅGA', game.nextRound, icon: Icons.arrow_forward_rounded),
              ],
            ]), icon: reveal ? Icons.fact_check_rounded : Icons.auto_awesome_rounded,
          ),
          if(game.phase=='countdown') panelCard('⚡ Gör er redo!', Column(children:[
            Text(modes[game.roundMode]??'Nästa utmaning',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold,color:lime)),
            const SizedBox(height:16),
            Container(height:160,width:160,alignment:Alignment.center,
              decoration:BoxDecoration(shape:BoxShape.circle,border:Border.all(color:lime,width:6)),
              child:Text('${game.countdownRemaining}',style:const TextStyle(fontSize:90,fontWeight:FontWeight.w900,color:lime))),
            const SizedBox(height:14),const Text('Frågan avslöjas när nedräkningen är klar',textAlign:TextAlign.center),
          ]),icon:Icons.hourglass_top_rounded),
          if (game.phase == 'bet') panelCard('🎲 Riskrunda – satsning', Column(children: [
            rowText('Låsta satsningar', '${actors.where((t) => t.betReady).length} / ${actors.length}'),
            const Text('Lagen väljer 1–3 poäng innan frågan visas.'),
            const SizedBox(height: 18),
            largeButton('VISA FRÅGAN', game.beginAfterBets, icon: Icons.visibility_rounded),
          ])),
          if (game.phase == 'question') panelCard(
            game.roundMode == 'relation' ? '❤️ Relationsduellen' : modes[game.roundMode] ?? 'Fråga',
            Column(children: [
              if (game.roundMode != 'relation') ...[
                Text('${game.remaining}', style: TextStyle(fontSize: 78, fontWeight: FontWeight.w900,
                  color: game.remaining <= 5 ? const Color(0xffff9f87) : lime)),
                ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(
                  value: game.remaining / game.questionSeconds, minHeight: 9,
                  backgroundColor: const Color(0xff303952), color: lime,
                )),
                const SizedBox(height: 14),
                Text(game.current?.category ?? '', style: const TextStyle(color: lime)),
                const SizedBox(height: 7),
                Text(game.current?.prompt ?? '', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
                if (game.roundMode == 'closest') const Text('🎯 NÄRMAST FÅR POÄNG!', style: TextStyle(color: lime, fontSize: 21, fontWeight: FontWeight.w900)),
              if (game.roundMode == 'duel') Text('⚔️ ${game.duelIds.map((id) => game.teams[id]?.name ?? '').join(' mot ')}'),
                const SizedBox(height: 12),
                rowText('Svar inkomna', '${game.teams.values.where((t) => t.answered).length}'),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: game.reveal, child: const Text('Avsluta frågan och visa facit')),
              ] else ...[
                Text(game.relationPrompt, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Text('${game.relationSetterName}  ❤️  ${game.relationReaderName}',
                  style: const TextStyle(color: lime, fontSize: 18)),
                const SizedBox(height: 12),
                Text(game.relationStage == 'setter' ? 'Väntar på hemligt svar…' : 'Väntar på motspelarens svar…',
                  style: const TextStyle(color: muted)),
              ],
            ]), icon: Icons.timer_outlined,
          ),
          panelCard('Poäng & kategorier', Column(children: [
            for (final t in game.teams.values) teamScore(t),
          ]), icon: Icons.leaderboard_rounded),
          if (game.phase == 'finished') panelCard('🏆 Slutresultat', Column(children:[
            if(game.earlyEnded) Text('Vinnare: ${game.winnersText}',style:const TextStyle(fontSize:23,color:lime,fontWeight:FontWeight.w900)),
            const SizedBox(height:7),
            Text(game.earlyEnded?'Matchen avslutades i förtid. Poängen avgjorde.':'Matchen är klar! Alla placeringar är fastställda.',style:const TextStyle(fontSize:17)),
          ])),
        ],
        const SizedBox(height: 10),
        const Text('DUELLEN v0.4 • 10 poäng + 3 kategorier', textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 12)),
      ]),
      if(localPlayer!=null) WebViewWidget(controller:localPlayer!) else const Center(child:CircularProgressIndicator()),
      ]))]),
    );
  }
}
