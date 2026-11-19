import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'question_packs.dart';

class QuizQuestion {
  QuizQuestion(Map<String, dynamic> m)
      : category = m['category'] as String,
        kind = m['kind'] as String,
        prompt = m['question'] as String,
        answer = m['answer'] as String,
        difficulty = (m['difficulty'] ?? 'medium') as String,
        options = List<String>.from(m['options'] as List);
  final String category, kind, prompt, answer, difficulty;
  final List<String> options;
}

class QuizTeam {
  QuizTeam(this.id, this.name);
  final String id, name;
  int points = 0, bet = 1;
  bool betReady = false, answered = false, qualified = false;
  String answer = '';
  DateTime? answeredAt;
  int? place;
  final Set<String> badges = {};
  String verdict = '';
  int change = 0;
}

class DuellenGame extends ChangeNotifier {
  final Random random = Random.secure();
  final Map<String, QuizTeam> teams = {};
  // Frågehistoriken lagras på spelledarens telefon även mellan matcher.
  final Set<String> usedQuestionKeys = {};
  final Set<String> usedRelationQuestions = {};
  bool historyLoaded = false;
  Future<void> _loadHistory() async {
    if (historyLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    usedQuestionKeys.addAll(prefs.getStringList('duellen_seen_questions_v1') ?? const []);
    usedRelationQuestions.addAll(prefs.getStringList('duellen_seen_relations_v1') ?? const []);
    historyLoaded = true;
  }
  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('duellen_seen_questions_v1', usedQuestionKeys.toList());
    await prefs.setStringList('duellen_seen_relations_v1', usedRelationQuestions.toList());
  }
  String questionKey(QuizQuestion q) => '${q.kind}|${q.prompt.trim().toLowerCase()}';
  List<QuizQuestion> questions = [];
  int get badgeGoal => min(3, max(1, questions.map((q)=>q.category).toSet().length));
  QuestionPack? selectedPack;
  void setQuestionPack(QuestionPack pack) {
    if (phase != 'lobby') return;
    selectedPack=pack;
    notifyListeners();
  }
  List<Map<String,dynamic>> newPlacements = [];
  int celebrationEnds = 0;
  Timer? celebrationTimer;
  void _announcePlacements(List<QuizTeam> newly) {
    if(newly.isEmpty)return;
    newPlacements=newly.map((t)=>{'name':t.name,'place':t.place,'points':t.points,'badges':t.badges.length}).toList();
    celebrationEnds=DateTime.now().millisecondsSinceEpoch+6500;
    celebrationTimer?.cancel();
    celebrationTimer=Timer(const Duration(milliseconds:6500),(){newPlacements=[];celebrationEnds=0;notifyListeners();});
    notifyListeners();
  }
  HttpServer? server;
  Timer? timer;
  String hostIp = '', error = '', phase = 'lobby', roundMode = 'normal';
  int round = 0, questionStarted = 0;
  int countdownStarted = 0;
  static const int countdownSeconds = 10;
  bool earlyEnded = false;
  String winnersText = '';
  Timer? resultTimer;
  int questionSeconds = 30;
  QuizQuestion? current;
  List<String> presentedOptions = [];
  List<String> duelIds = [];
  String difficulty = 'mix'; // easy, medium, hard, mix
  void setDifficulty(String value) { if (phase=='lobby' && ['mix','easy','medium','hard'].contains(value)) { difficulty=value; notifyListeners(); } }
  String flowMode = 'auto'; // auto eller manual
  String lastMode = '';
  String chosenMode = 'normal';
  void setFlowMode(String value) { if(phase=='lobby' && ['auto','manual'].contains(value)){flowMode=value;notifyListeners();} }
  String pickNextMode() {
    // Balanserad slump: färre relations- och närmast-rundor än kunskapsfrågor.
    const bag=['normal','normal','normal','risk','risk','duel','duel','closest','surprise','relation','relation'];
    final hasNumbers=questions.any((q)=>q.kind=='number' && (difficulty=='mix'||q.difficulty==difficulty));
    final choices=bag.where((m)=>m!=lastMode && (m!='closest'||hasNumbers) && (m!='relation' || relationsMode!='manual' || (selectedFirst.isNotEmpty && selectedSecond.isNotEmpty && selectedFirst!=selectedSecond))).toList();
    return choices[random.nextInt(choices.length)];
  }
  void nextRound() {
    if(phase=='bet') { beginAfterBets(); return; }
    if(phase!='ready' && phase!='reveal') return;
    final next=flowMode=='auto' ? pickNextMode() : chosenMode;
    prepareRound(next);
  }
  String relationsMode = 'random'; // random eller manual
  String relationsRule = 'match'; // match eller trap
  String selectedFirst = '', selectedSecond = '';
  List<String> lastRelationPair = [];
  final List<String> relationQuestions = [
    'Vem av er är mest kvällssur?',
    'Vem av er är mest morgontrött?',
    'Vem av er har svårast att erkänna ett misstag?',
    'Vem av er skulle klara sig bäst på en öde ö?',
    'Vem av er tappar oftast bort sina saker?',
    'Vem av er skrattar lättast vid fel tillfälle?',
    'Vem av er skulle köpa något helt onödigt?',
    'Vem av er är mest envis?',
    'Vem av er har bäst lokalsinne?',
    'Vem av er är mest tävlingsinriktad?',
    'Vem av er blir hungrig och grinig först?',
    'Vem av er är bäst på att hålla en hemlighet?',

    'Vem av er skulle glömma ett viktigt datum?',
    'Vem av er har bäst tålamod i en kö?',
    'Vem av er packar för mycket inför en resa?',
    'Vem av er är mest spontan?',
    'Vem av er kan hålla masken bäst?',
    'Vem av er tar längst tid på sig att välja mat?',
    'Vem av er vill alltid ha sista ordet?',
    'Vem av er är bäst på att hitta borttappade saker?',
    'Vem av er är mest morgonpigg?',
    'Vem av er är snabbast att säga förlåt?',
    'Vem av er skulle vinna en frågesport?',
    'Vem av er är mest lättskrämd?',
    'Vem av er skulle våga sjunga karaoke först?',
    'Vem av er somnar först framför en film?',
    'Vem av er är bäst på att planera en semester?',
    'Vem av er skulle glömma passet hemma?',
    'Vem av er är mest pratsam på en fest?',
    'Vem av er är mest ordningsam?',
    'Vem av er har lättast att hålla en överraskning hemlig?',
    'Vem av er har bäst humor enligt den andra?',
    'Vem av er är mest envis om vägbeskrivningar?',
    'Vem av er skulle överleva längst utan internet?',
    'Vem av er är mest rastlös?',
    'Vem av er skulle klara sig bäst som programledare?',
    'Vem av er är mest tidsoptimist?',
    'Vem av er är bäst på att pruta?',
    'Vem av er skulle vinna i charader?',
    'Vem av er blir mest irriterad av dålig musik?',
    'Vem av er är mest nyfiken?',
    'Vem av er är mest kreativ i köket?',
    'Vem av er är bäst på att ta hand om krukväxter?',
    'Vem av er får oftast sista ordet i diskussioner?',
    'Vem av er skulle lättast hitta en ursäkt för att slippa städa?',
    'Vem av er är bäst på att läsa kartor?',
    'Vem av er skulle bjuda hem flest gäster på kort varsel?',
    'Vem av er är mest glömsk?',
    'Vem av er skulle klara en vecka i tält bäst?',
    'Vem av er är mest morgonsur?',
    'Vem av er skulle ta täten på ett dansgolv?',
    'Vem av er är mest tävlingsnervös?',
    'Vem av er är bäst på att välja presenter?',
    'Vem av er är mest sentimental?',
    'Vem av er skulle först börja prata med en främling?',
    'Vem av er är mest petig med detaljer?',
    'Vem av er är mest beslutsam när ni ska välja restaurang?',
    'Vem av er är mest envis när ni spelar spel?',
    'Vem av er skulle våga åka berg- och dalbana först?',
    'Vem av er tar oftast initiativ till en utflykt?',
    'Vem av er hittar lättast på nya smeknamn?',
    'Vem av er har svårast att låta bli att skratta?',
    'Vem av er skulle bli bäst hemlig agent?',
    'Vem av er är bäst på att improvisera en middag?',
    'Vem av er har flest konstiga vanor?',
    'Vem av er är mest hjälpsam när någon flyttar?',
    'Vem av er skulle klara en hel dag utan mobilen bäst?',
    'Vem av er skulle oftast säga ”jag sa ju det”?',
    'Vem av er är bäst på att minnas födelsedagar?',
    'Vem av er skulle snabbast tappa bort sig i en ny stad?',
    'Vem av er är mest benägen att köpa en pryl bara för att den är på rea?',
    'Vem av er är bäst på att trösta någon?',
    'Vem av er gillar mest att överraska andra?',
    'Vem av er skulle vinna ett matlagningstävlingsprogram?',
    'Vem av er skulle vara mest bekväm med att tala inför publik?',
    'Vem av er håller oftast koll på tiden?',
    'Vem av er är bäst på att hitta på roliga aktiviteter?',
    'Vem av er skulle bli mest nervös inför ett överraskningsprov?',
    'Vem av er är mest påhittig?',
    'Vem av er brukar skratta åt sina egna skämt?',
    'Vem av er kan flest låttexter utantill?',
    'Vem av er tar flest bilder på semestern?',
  ];
  String relationPrompt = '';
  String relationStage = 'setter';
  String relationSecret = '';
  String relationStrategy = 'match';
  String? relationSetter;
  String? relationReader;
  String lastRelationQuestion = '';
  String relationSummary = '';
  List<String> get relationChoices => [...duelIds.map((id)=>teams[id]?.name??''), 'Båda lika mycket'];
  String get relationSetterName => teams[relationSetter]?.name??'';
  String get relationReaderName => teams[relationReader]?.name??'';
  void setRelationsMode(String m) { if(phase=='lobby' && ['random','manual'].contains(m)){relationsMode=m;notifyListeners();} }
  void setRelationsRule(String m) { if(phase=='lobby' && ['match','trap'].contains(m)){relationsRule=m;notifyListeners();} }

  String get address => hostIp.isEmpty ? '' : 'http://$hostIp:8765';
  int get countdownRemaining => max(0, countdownSeconds - ((DateTime.now().millisecondsSinceEpoch - countdownStarted) ~/ 1000));
  int get remaining => phase == 'question'
      ? max(0, questionSeconds - ((DateTime.now().millisecondsSinceEpoch - questionStarted) ~/ 1000)) : questionSeconds;
  List<QuizTeam> get eligible => teams.values.where((t) => !t.qualified).toList();

  Future<void> startServer() async {
    try {
      server = await HttpServer.bind(InternetAddress.anyIPv4, 8765);
      server!.listen(_handle);
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      final ips = interfaces.expand((i) => i.addresses).where((a) => !a.isLoopback).toList();
      final local = ips.where((a) => a.address.startsWith('192.168.') || a.address.startsWith('10.') ||
          RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(a.address)).toList();
      hostIp = (local.isNotEmpty ? local.first : (ips.isNotEmpty ? ips.first : InternetAddress.loopbackIPv4)).address;
    } catch (e) { error = 'Kunde inte öppna spelserver: $e'; }
    notifyListeners();
  }

  void setIp(String value) { hostIp = value.trim().replaceAll('http://', '').split(':').first; notifyListeners(); }

  Future<void> startGame() async {
    if (teams.length < 2) { error = 'Minst två lag behövs.'; notifyListeners(); return; }
    try {
      final pack = selectedPack;
      final entries = pack == null
        ? (jsonDecode(await rootBundle.loadString('assets/data/questions.json')) as List)
            .map((x)=>Map<String,dynamic>.from(x as Map)).toList()
        : pack.questions;
      questions = entries.map((x)=>QuizQuestion(x)).toList();
      if (questions.length < 5) throw StateError('Frågepaketet behöver minst fem frågor.');
      await _loadHistory();
      round = 0; phase = 'ready'; error = ''; earlyEnded=false; winnersText=''; resultTimer?.cancel();
      celebrationTimer?.cancel();newPlacements=[];celebrationEnds=0;
      current=null; lastMode=''; lastRelationPair.clear(); lastRelationQuestion='';
      for (final t in teams.values) {
        t.points = 0; t.bet = 1; t.betReady = false; t.answered = false;
        t.answer = ''; t.place = null; t.qualified = false; t.badges.clear(); t.verdict = ''; t.change = 0;
      }
    } catch (e) { error = 'Frågorna kunde inte laddas: $e'; }
    notifyListeners();
  }

  void prepareRound(String mode) {
    if (phase != 'ready' && phase != 'reveal') return;
    if (eligible.length <= 1) { phase = 'finished'; notifyListeners(); return; }
    if (!['normal','risk','duel','closest','surprise','relation'].contains(mode)) return;
    error='';
    resultTimer?.cancel();
    roundMode = mode;
    lastMode=mode;
    for (final t in teams.values) {
      t.bet = 1; t.betReady = false; t.answered = false; t.answer = ''; t.answeredAt = null;
      t.verdict = ''; t.change = 0;
    }
    duelIds = [];
    if (mode == 'duel' || mode == 'relation') {
      final options = List<QuizTeam>.of(eligible)..shuffle(random);
      if(mode=='relation' && relationsMode=='manual') {
        if(selectedFirst.isEmpty || selectedSecond.isEmpty || selectedFirst==selectedSecond ||
          !eligible.any((t)=>t.id==selectedFirst) || !eligible.any((t)=>t.id==selectedSecond)) {
          error='Välj två olika aktiva deltagare för Relationsduellen.';notifyListeners();return;
        }
        duelIds=[selectedFirst,selectedSecond];
      } else {
        if(mode=='relation' && options.length>2 && lastRelationPair.length==2) {
          for(var i=0;i<12;i++){
            options.shuffle(random);
            final ids=options.take(2).map((t)=>t.id).toSet();
            if(!ids.containsAll(lastRelationPair))break;
          }
        }
        duelIds = options.take(2).map((t) => t.id).toList();
      }
      if(mode=='relation'){
        lastRelationPair=List.of(duelIds);
        relationSetter=duelIds[0];relationReader=duelIds[1];
        relationStage='setter';relationSecret='';relationStrategy='match';relationSummary='';
        var options=relationQuestions.where((q)=>q!=lastRelationQuestion && !usedRelationQuestions.contains(q)).toList();
        if(options.isEmpty){
          usedRelationQuestions.clear();
          options=relationQuestions.where((q)=>q!=lastRelationQuestion).toList();
        }
        relationPrompt=options[random.nextInt(options.length)];lastRelationQuestion=relationPrompt;
        usedRelationQuestions.add(relationPrompt);
        _saveHistory();
        _startCountdown(); return;
      }
    }
    if (mode == 'risk') { phase = 'bet'; notifyListeners(); }
    else { _startCountdown(); }
  }

  void beginAfterBets() {
    if (phase != 'bet') return;
    if (eligible.any((t) => !t.betReady)) {
      error = 'Alla aktiva lag måste låsa sin satsning.'; notifyListeners(); return;
    }
    _startCountdown();
  }

  void _startCountdown() {
    phase='countdown';
    countdownStarted=DateTime.now().millisecondsSinceEpoch;
    timer?.cancel();
    timer=Timer.periodic(const Duration(milliseconds: 200), (_) {
      if(phase!='countdown'){timer?.cancel();return;}
      if(countdownRemaining<=0){
        timer?.cancel();
        if(roundMode=='relation'){
          round++;phase='question';questionStarted=DateTime.now().millisecondsSinceEpoch;notifyListeners();
        } else { _showQuestion(); }
      } else { notifyListeners(); }
    });
    notifyListeners();
  }

  void _showQuestion() {
    final kind = roundMode == 'closest' ? 'number' : 'choice';
    List<int> candidates = [];
    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      if (q.kind == kind && (difficulty == 'mix' || q.difficulty == difficulty) &&
          !usedQuestionKeys.contains(questionKey(q))) candidates.add(i);
    }
    // Först när hela relevant frågepoolen är slut tillåts frågorna återkomma.
    if (candidates.isEmpty) {
      for (final q in questions.where((q) => q.kind == kind &&
          (difficulty == 'mix' || q.difficulty == difficulty))) {
        usedQuestionKeys.remove(questionKey(q));
      }
      for (var i=0; i<questions.length; i++) {
        final q=questions[i];
        if(q.kind==kind && (difficulty=='mix' || q.difficulty==difficulty)) candidates.add(i);
      }
    }
    if (candidates.isEmpty) {
      error = 'Det saknas frågor för detta spelläge och svårighetsgrad.';
      phase='ready'; notifyListeners(); return;
    }
    final index = candidates[random.nextInt(candidates.length)];
    current = questions[index];
    usedQuestionKeys.add(questionKey(current!));
    _saveHistory();
    presentedOptions = List.of(current!.options)..shuffle(random);
    round++;
    error = '';
    phase = 'question';
    questionStarted = DateTime.now().millisecondsSinceEpoch;
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (remaining == 0) reveal(); else notifyListeners();
    });
    notifyListeners();
  }

  bool _correct(QuizTeam t) => t.answered && t.answer.trim().toLowerCase() == current!.answer.trim().toLowerCase();
  double? _distance(QuizTeam t) {
    if (!t.answered) return null;
    final value = double.tryParse(t.answer.trim().replaceAll(',', '.'));
    final target = double.tryParse(current!.answer);
    return value == null || target == null ? null : (value - target).abs();
  }

  void reveal() {
    if (phase != 'question' || current == null) return;
    timer?.cancel();
    if(roundMode=='relation'){if(relationStage=='reader' && teams[relationReader]?.answered==true)_revealRelation();return;}
    final actors = eligible.where((t) => roundMode != 'duel' || duelIds.contains(t.id)).toList();
    final winners = <QuizTeam>{};
    if (roundMode == 'closest') {
      final valid = actors.where((t)=>_distance(t)!=null).toList();
      if (valid.isNotEmpty) {
        final best = valid.map((t)=>_distance(t)!).reduce(min);
        winners.addAll(valid.where((t)=>_distance(t)==best));
      }
    } else if (roundMode == 'duel') {
      final good = actors.where(_correct).toList();
      good.sort((a,b)=>(a.answeredAt ?? DateTime(2100)).compareTo(b.answeredAt ?? DateTime(2100)));
      if (good.isNotEmpty) winners.add(good.first);
    } else { winners.addAll(actors.where(_correct)); }
    for (final t in teams.values) {
      t.change = 0;
      if (t.qualified || !actors.contains(t)) { t.verdict = 'Åskådare'; continue; }
      if (winners.contains(t)) {
        final award = roundMode=='risk' ? t.bet : (roundMode=='normal' ? 1 : 2);
        t.points += award; t.change = award; t.badges.add(current!.category); t.verdict = roundMode=='closest' ? 'Närmast!' : 'Rätt!';
      } else {
        final deduction = roundMode=='risk' ? min(t.bet,t.points) : 0;
        t.points -= deduction; t.change = -deduction;
        t.verdict = t.answered ? 'Fel' : 'Inget svar';
        if (roundMode=='duel' && _correct(t)) t.verdict = 'Rätt, men motståndaren var snabbare';
      }
      if (t.points >= 10 && t.badges.length >= badgeGoal) t.qualified = true;
    }
    final newlyQualified = teams.values.where((t)=>t.qualified && t.place==null).toList()
      ..sort((a,b)=>b.points.compareTo(a.points));
    final placedBefore = teams.values.where((t)=>t.place!=null).length;
    var previousScore = -1;
    var sharedRank = placedBefore+1;
    for (var i=0;i<newlyQualified.length;i++) {
      final t = newlyQualified[i];
      if (t.points != previousScore) sharedRank = placedBefore+i+1;
      t.place = sharedRank;
      previousScore = t.points;
    }
    if (eligible.length <= 1) {
      if (eligible.isNotEmpty) eligible.first.place = teams.length;
      phase = 'finished';
    } else { phase = 'reveal'; }
    _announcePlacements(newlyQualified);
    _scheduleNext();
    notifyListeners();
  }

  void _awardRelation(QuizTeam winner, int points, String explanation) {
    winner.points+=points; winner.change=points; winner.verdict=explanation;
    winner.badges.add('Relation');
  }

  void _revealRelation() {
    final a=teams[relationSetter], b=teams[relationReader];
    if(a==null||b==null)return;
    a.change=0;b.change=0;
    final matching=a.answer==b.answer;
    if(relationsRule=='match'){
      if(matching){
        _awardRelation(a,2,'Ni tänkte lika!');
        _awardRelation(b,2,'Ni tänkte lika!');
        relationSummary='Matchning! Båda får +2 poäng.';
      }else{
        a.verdict='Olika svar';b.verdict='Olika svar';
        relationSummary='Ni tänkte olika. Ingen får poäng.';
      }
    }else{
      if(relationStrategy=='steal'){
        if(matching){_awardRelation(b,2,'Du genomskådade tankefällan!');relationSummary='Poängen stals av ${b.name}!';}
        else{_awardRelation(a,2,'Du lurade motspelaren!');relationSummary='Tankefällan lyckades för ${a.name}!';}
      }else if(matching){
        _awardRelation(a,2,'Du fick motspelaren att tänka lika!');
        relationSummary='${a.name} får +2 poäng för matchande svar.';
      }else{
        a.verdict='Olika svar';b.verdict='Olika svar';
        relationSummary='Inget matchande svar. Inga poäng.';
      }
    }
    for(final t in [a,b]){if(t.points>=10 && t.badges.length>=badgeGoal)t.qualified=true;}
    _placeTeams();
    _scheduleNext();
    notifyListeners();
  }

  void _placeTeams() {
    final newlyQualified=teams.values.where((t)=>t.qualified&&t.place==null).toList()
      ..sort((a,b)=>b.points.compareTo(a.points));
    final before=teams.values.where((t)=>t.place!=null).length;
    int? lastScore;var rank=before+1;
    for(var i=0;i<newlyQualified.length;i++){
      final t=newlyQualified[i];if(t.points!=lastScore)rank=before+i+1;
      t.place=rank;lastScore=t.points;
    }
    final active=eligible;
    if(active.length<=1){if(active.isNotEmpty)active.first.place=teams.length;phase='finished';}
    else phase='reveal';
    _announcePlacements(newlyQualified);
  }

  void _scheduleNext() {
    resultTimer?.cancel();
    if(flowMode=='auto' && phase=='reveal') {
      resultTimer=Timer(const Duration(seconds: 9), () {
        if(phase=='reveal') nextRound();
      });
    }
  }

  // Ny match utan att avsluta appen. Behåller lag och den sparade frågehistoriken.
  void newMatch() {
    if(phase!='finished') return;
    timer?.cancel(); resultTimer?.cancel();celebrationTimer?.cancel();newPlacements=[];celebrationEnds=0;
    phase='lobby'; round=0; current=null; roundMode='normal';
    countdownStarted=0; questionStarted=0;
    earlyEnded=false; winnersText=''; error=''; lastMode='';
    duelIds.clear(); selectedFirst=''; selectedSecond='';
    relationSetter=null; relationReader=null; relationStage='setter';
    relationPrompt=''; relationSummary=''; lastRelationPair.clear();
    for(final t in teams.values){
      t.points=0; t.bet=1; t.betReady=false; t.answered=false; t.qualified=false;
      t.answer=''; t.answeredAt=null; t.place=null;
      t.badges.clear(); t.verdict=''; t.change=0;
    }
    notifyListeners();
  }

  // Avslut i förtid: pågående fråga avbryts utan rättning; poängen från
  // redan avslutade rundor ligger kvar. Lika hög poäng ger delad seger.
  void endEarly() {
    if(phase=='lobby' || phase=='finished') return;
    timer?.cancel();resultTimer?.cancel();
    earlyEnded=true;
    final sorted=teams.values.toList()..sort((a,b)=>b.points.compareTo(a.points));
    if(sorted.isEmpty)return;
    final best=sorted.first.points;
    winnersText=sorted.where((t)=>t.points==best).map((t)=>t.name).join(' & ');
    int rank=0;int? old;
    for(var i=0;i<sorted.length;i++){
      if(sorted[i].points!=old)rank=i+1;
      sorted[i].place=rank;
      old=sorted[i].points;
    }
    phase='finished';notifyListeners();
  }

  Map<String,dynamic> state(String? teamId) {
    final you = teams[teamId];
    final revealNow = phase=='reveal' || phase=='finished';
    return {
      'phase': phase, 'round': round, 'mode': roundMode, 'flowMode':flowMode, 'difficulty':difficulty,
      'earlyEnded':earlyEnded,'winnersText':winnersText,
      'newPlacements':newPlacements,'celebrationEnds':celebrationEnds,
      'packName':selectedPack?.title??'Blandade ämnen','badgeGoal':badgeGoal,
      'countdownStarted':countdownStarted,'countdownSeconds':countdownSeconds,
      'now': DateTime.now().millisecondsSinceEpoch, 'started': questionStarted, 'seconds': questionSeconds,
      'category': (phase=='question'||revealNow) ? current?.category : null,
      'question': (phase=='question'||revealNow) ? current?.prompt : null,
      'roundHint':roundMode=='closest' ? 'NÄRMAST FÅR POÄNG – exakt svar krävs inte' : (roundMode=='duel' ? 'SNABBAST RÄTT SVAR VINNER' : ''),
      'kind': current?.kind, 'options': phase=='question'?presentedOptions:[],
      'correct': revealNow ? current?.answer : null,
      'duelNames': duelIds.map((id)=>teams[id]?.name??'').toList(),
      'relationsRule': relationsRule,
      'relationStage': relationStage,
      'relationPrompt': relationPrompt,
      'relationSetter': relationSetterName,
      'relationReader': relationReaderName,
      'relationChoices': relationChoices,
      if(revealNow && roundMode=='relation') 'relationSummary':relationSummary,
      if(revealNow && roundMode=='relation') 'relationAnswers': duelIds.map((id)=>{'name':teams[id]?.name,'answer':teams[id]?.answer}).toList(),
      'teams': teams.values.map((t)=>{
        'name':t.name, 'points':t.points, 'badges':t.badges.toList(), 'qualified':t.qualified,
        'place':t.place, 'answered':t.answered, 'betReady':t.betReady,
        if(revealNow) 'answer':t.answered?t.answer:'—',
        if(revealNow) 'verdict':t.verdict,
        if(revealNow) 'change':t.change,
      }).toList(),
      'you': you==null?null:{'id':you.id,'name':you.name,'points':you.points,'badges':you.badges.toList(),
        'qualified':you.qualified,'betReady':you.betReady,'bet':you.bet,
        'answered':you.answered, 'canAnswer': !you.qualified && (roundMode!='duel'&&roundMode!='relation'||duelIds.contains(you.id)),
        'relationTurn':roundMode=='relation' && phase=='question' &&
           ((relationStage=='setter' && you.id==relationSetter) ||
            (relationStage=='reader' && you.id==relationReader)),
        if(revealNow) 'answer':you.answered?you.answer:'—',
        if(revealNow) 'verdict':you.verdict,
        if(revealNow) 'change':you.change,
      },
    };
  }

  void _json(HttpResponse res, Map<String,dynamic> data) {
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(data));
  }
  void _bad(HttpResponse res, String errorText) {
    res.statusCode = 400; _json(res, {'error':errorText});
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers.set('Cache-Control','no-store');
    try {
      final path = req.uri.path;
      if (req.method=='GET' && path=='/') {
        res.headers.contentType=ContentType.html;
        res.write(await rootBundle.loadString('assets/web/player.html'));
      } else if (req.method=='GET' && path=='/music') {
        res.headers.set('Content-Type', 'audio/wav');
        res.add((await rootBundle.load('assets/audio/answer_music.wav')).buffer.asUint8List());
      } else if (req.method=='GET' && path=='/state') {
        _json(res, state(req.uri.queryParameters['id']));
      } else if (req.method=='POST' && (path=='/join'||path=='/bet'||path=='/answer'||path=='/relation')) {
        final payload = Map<String,dynamic>.from(jsonDecode(await utf8.decoder.bind(req).join()) as Map);
        final id = (payload['id']??'').toString();
        if (path=='/join') {
          final name = (payload['name']??'').toString().trim();
          if (phase!='lobby') _bad(res,'Spelet har redan startat.');
          else if (name.isEmpty || name.length>25) _bad(res,'Ange ett namn på 1–25 tecken.');
          else if (teams.values.any((t)=>t.name.toLowerCase()==name.toLowerCase())) _bad(res,'Namnet används redan.');
          else {
            final newId = '${DateTime.now().microsecondsSinceEpoch}${random.nextInt(999999)}';
            teams[newId] = QuizTeam(newId,name); _json(res,{'id':newId}); notifyListeners();
          }
        } else if (!teams.containsKey(id)) _bad(res,'Okänt lag. Gå med på nytt.');
        else if (teams[id]!.qualified) _bad(res,'Laget är redan i mål.');
        else if (path=='/bet') {
          final value = int.tryParse('${payload['bet']}');
          if (phase!='bet') _bad(res,'Ingen satsning pågår.');
          else if (teams[id]!.betReady) _bad(res,'Satsningen är redan låst.');
          else if (value==null||value<1||value>3) _bad(res,'Välj 1–3 poäng.');
          else { teams[id]!..bet=value..betReady=true; _json(res,{'ok':true}); notifyListeners();
            if(flowMode=='auto' && eligible.every((t)=>t.betReady)) {
              Future.delayed(const Duration(seconds:1), () { if(phase=='bet') beginAfterBets(); });
            }
          }
        } else if (path=='/relation') {
          final t=teams[id]!;
          final choice=(payload['answer']??'').toString();
          final strategy=(payload['strategy']??'match').toString();
          if(phase!='question'||roundMode!='relation') _bad(res,'Ingen Relationsduell pågår.');
          else if(relationStage=='setter' && id!=relationSetter || relationStage=='reader' && id!=relationReader) _bad(res,'Det är inte din tur.');
          else if(t.answered) _bad(res,'Du har redan svarat.');
          else if(!relationChoices.contains(choice)) _bad(res,'Välj ett av alternativen.');
          else if(relationStage=='reader' && !['match','steal'].contains(strategy)) _bad(res,'Ogiltig strategi.');
          else {
            t.answer=choice;t.answered=true;
            if(relationStage=='setter') {relationSecret=choice;relationStage='reader';}
            else {relationStrategy=strategy;_revealRelation();}
            _json(res,{'ok':true});notifyListeners();
          }
        } else {
          final t = teams[id]!;
          final answer = (payload['answer']??'').toString().trim();
          if (phase!='question' || remaining<=0) _bad(res,'Svarstiden är slut.');
          else if (roundMode=='duel'&&!duelIds.contains(id)) _bad(res,'Du tittar på denna duell.');
          else if (t.answered) _bad(res,'Laget har redan lämnat svar.');
          else if (answer.isEmpty||answer.length>80) _bad(res,'Skriv ett svar.');
          else if (current!.kind=='choice'&&!presentedOptions.contains(answer)) _bad(res,'Välj ett av alternativen.');
          else if (current!.kind=='number'&&double.tryParse(answer.replaceAll(',','.'))==null) _bad(res,'Ange ett tal.');
          else {
            t.answer=answer; t.answered=true; t.answeredAt=DateTime.now();
            _json(res,{'ok':true}); notifyListeners();
          }
        }
      } else { res.statusCode=404; res.write('Hittades inte'); }
    } catch(e) { res.statusCode=500; _json(res,{'error':'Serverfel: $e'}); }
    try {await res.close();} catch(_) {}
  }

  @override void dispose() {
    timer?.cancel();resultTimer?.cancel(); server?.close(force:true); super.dispose();
  }
}
