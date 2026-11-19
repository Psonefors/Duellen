import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'question_packs.dart';

const _bg = Color(0xff101426);
const _panel = Color(0xff202944);
const _accent = Color(0xffd6ff61);

class RaceRecord {
  RaceRecord({required this.date, required this.correct, required this.answered,
    required this.mistakes, required this.seconds, required this.distance,
    required this.finished, required this.checkpoints});
  final String date;
  final int correct, answered, mistakes;
  final double seconds, distance;
  final bool finished;
  final List<List<double>> checkpoints; // [seconds elapsed, distance reached]
  Map<String,dynamic> toJson() => {'date':date,'correct':correct,'answered':answered,'mistakes':mistakes,
    'seconds':seconds,'distance':distance,'finished':finished,'checkpoints':checkpoints};
  factory RaceRecord.fromJson(Map<String,dynamic> j) => RaceRecord(
    date:j['date'] as String,correct:(j['correct'] as num).toInt(),answered:(j['answered'] as num).toInt(),
    mistakes:(j['mistakes'] as num).toInt(), seconds:(j['seconds'] as num).toDouble(),
    distance:(j['distance'] as num).toDouble(),finished:j['finished']==true,
    checkpoints:(j['checkpoints'] as List).map((x)=>(x as List).map((v)=>(v as num).toDouble()).toList()).toList());
  double positionAt(double seconds) {
    if (checkpoints.isEmpty) return 0;
    var prevT=0.0,prevD=0.0;
    for(final c in checkpoints){
      if(seconds<=c[0]){
        final delta=c[0]-prevT;
        return delta<=0 ? c[1] : prevD+(c[1]-prevD)*((seconds-prevT)/delta).clamp(0.0,1.0);
      }
      prevT=c[0];prevD=c[1];
    }
    return distance;
  }
}

class RacePage extends StatefulWidget {
  const RacePage({super.key, required this.packs});
  final List<QuestionPack> packs;
  @override State<RacePage> createState()=>_RacePageState();
}

class _RacePageState extends State<RacePage> {
  QuestionPack? selected;
  String level='mix';
  int questionCount=20;
  List<Map<String,dynamic>> deck=[];
  List<RaceRecord> ghosts=[];
  int index=0,correct=0,mistakes=0;
  double distance=0, totalResponse=0;
  List<List<double>> checkpoints=[];
  DateTime? started, questionStarted;
  bool running=false,done=false,showExplanation=false;
  String verdict='', explanation='';
  RaceRecord? currentRecord;
  final Random rng=Random();
  Timer? raceRefresh;
  @override void dispose(){raceRefresh?.cancel();super.dispose();}
  static const length=320.0;
  static const maxErrors=3;
  String get _key => 'duellen_race_v1_${selected?.id ?? 'standard'}_${level}_$questionCount';

  @override void initState(){super.initState();selected=widget.packs.first;_loadGhosts();
    raceRefresh=Timer.periodic(const Duration(milliseconds:200),(_){if(mounted&&running)setState((){});});}
  Future<void> _loadGhosts() async {
    final prefs=await SharedPreferences.getInstance();
    final all=(prefs.getStringList(_key)??[]).map((e)=>RaceRecord.fromJson(Map<String,dynamic>.from(jsonDecode(e) as Map))).toList();
    all.sort(_compareRecords); if(mounted)setState(()=>ghosts=all.take(4).toList());
  }
  static int _compareRecords(RaceRecord a,RaceRecord b){
    final d=b.distance.compareTo(a.distance); if(d!=0)return d;
    final c=b.correct.compareTo(a.correct); if(c!=0)return c;
    return a.seconds.compareTo(b.seconds);
  }
  void _start(){
    final filtered=selected!.questions.where((q)=>q['kind']=='choice' && (level=='mix'||q['difficulty']==level)).toList()..shuffle(rng);
    if(filtered.length<questionCount){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Bara ${filtered.length} frågor finns för valt ämne och nivå. Välj färre frågor eller blandad nivå.')));return;}
    final now=DateTime.now();
    setState(() {deck=filtered.take(questionCount).toList();index=0;correct=0;mistakes=0;distance=0;totalResponse=0;
      checkpoints=[];started=now;questionStarted=now;running=true;done=false;showExplanation=false;verdict='';currentRecord=null;});
  }
  Future<void> _answer(String choice) async {
    if(!running||showExplanation)return;
    final elapsed=DateTime.now().difference(questionStarted!).inMilliseconds/1000.0;
    final isCorrect=choice==deck[index]['answer'];
    final bonus=isCorrect? (elapsed<5?8.0:elapsed<10?5.0:elapsed<20?3.0:1.0):0.0;
    final gain=isCorrect?10.0+bonus:0.0;
    final now=DateTime.now();
    setState(() {
      index++;totalResponse+=elapsed;
      if(isCorrect){correct++;distance=min(length,distance+gain);}else{mistakes++;}
      checkpoints.add([now.difference(started!).inMilliseconds/1000.0,distance]);
      verdict=isCorrect?'RÄTT! +${gain.toStringAsFixed(0)} meter':'FEL! Rätt svar: ${deck[index-1]['answer']}';
      explanation=(deck[index-1]['explanation']??'').toString();
      showExplanation=true;
    });
    if (mistakes>=maxErrors || index>=questionCount || distance>=length) await _finish();
  }
  Future<void> _finish() async {
    final elapsed=DateTime.now().difference(started!).inMilliseconds/1000.0;
    final record=RaceRecord(date:DateTime.now().toIso8601String(),correct:correct,answered:index,mistakes:mistakes,
      seconds:elapsed,distance:distance,finished:mistakes<maxErrors,checkpoints:List.of(checkpoints));
    final prefs=await SharedPreferences.getInstance();
    final old=(prefs.getStringList(_key)??[]);
    old.add(jsonEncode(record.toJson()));
    final records=old.map((e)=>RaceRecord.fromJson(Map<String,dynamic>.from(jsonDecode(e) as Map))).toList();
    records.sort(_compareRecords);
    await prefs.setStringList(_key,records.take(30).map((e)=>jsonEncode(e.toJson())).toList());
    if(mounted)setState(() {currentRecord=record;running=false;done=true;ghosts=records.where((r)=>r.date!=record.date).take(4).toList();});
  }
  String _when(String raw){
    final t=DateTime.tryParse(raw);if(t==null)return raw;
    return '${t.day.toString().padLeft(2,'0')}/${t.month.toString().padLeft(2,'0')} ${t.year} kl ${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';
  }
  Widget _raceTrack(){
    final seconds=started==null?0.0:DateTime.now().difference(started!).inMilliseconds/1000.0;
    final entries=<({String name,double distance,Color color})>[(name:'DU NU',distance:distance,color:_accent)];
    const colors=[Color(0xff8cb6ff),Color(0xffeb9eff),Color(0xffffbd72),Color(0xff4ed9c0)];
    for(var i=0;i<ghosts.length;i++){
      entries.add((name:'REKORD ${i+1}',distance:ghosts[i].positionAt(seconds),color:colors[i]));
    }
    return Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:_panel,borderRadius:BorderRadius.circular(20)),
      child:Column(children:[
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('START'),Text('MÅL  ${length.toInt()} m',style:const TextStyle(color:_accent))]),
        ...entries.map((e)=>Padding(padding:const EdgeInsets.symmetric(vertical:9),child:Column(children:[
          Row(children:[SizedBox(width:86,child:Text(e.name,style:const TextStyle(fontSize:11,fontWeight:FontWeight.bold))),
            Expanded(child:LayoutBuilder(builder:(c,box)=>Stack(clipBehavior:Clip.none,children:[
              Container(height:20,decoration:BoxDecoration(color:const Color(0xff38435f),borderRadius:BorderRadius.circular(5))),
              Positioned(left:max(0,(box.maxWidth-25)*(e.distance/length).clamp(0,1)),top:-5,
                child:Icon(Icons.directions_car_filled_rounded,color:e.color,size:30)),
            ]))),
            SizedBox(width:48,child:Text('${e.distance.toInt()} m',textAlign:TextAlign.right,style:const TextStyle(fontSize:10))),
                    ])]))).toList(),
      ]));
  }
  Widget _podium(){
    final all=<RaceRecord>[...?ghosts,if(currentRecord!=null)currentRecord!];
    all.sort(_compareRecords);
    return Column(children:[const Text('🏆 PRISPALL',style:TextStyle(fontSize:27,fontWeight:FontWeight.w900,color:_accent)),
      ...all.take(3).toList().asMap().entries.map((e){final r=e.value;
        return Card(color:_panel,child:ListTile(leading:Text(['🥇','🥈','🥉'][e.key],style:const TextStyle(fontSize:30)),
          title:Text(_when(r.date)),subtitle:Text('${r.correct}/${r.answered} rätt • ${r.mistakes} fel • ${r.seconds.toStringAsFixed(1)} s'),
          trailing:Text('${r.distance.toInt()} m',style:const TextStyle(color:_accent,fontWeight:FontWeight.bold))));}),
      const SizedBox(height:12),Text(mistakes>=maxErrors?'💥 BILEN STANNADE – tre fel.':'🏁 LOPPET AVSLUTAT!',style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900)),
      const SizedBox(height:12),FilledButton.icon(onPressed:_start,icon:const Icon(Icons.refresh),label:const Text('REVANSCH – KÖR IGEN')),
    ]);
  }
  @override Widget build(BuildContext context){
    final q=running||done ? (index>0 && showExplanation ? deck[index-1] : index<deck.length ? deck[index]:null) : null;
    return Scaffold(backgroundColor:_bg,appBar:AppBar(title:const Text('🏎️ KUNSKAPSRACET'),backgroundColor:_bg),
      body:ListView(padding:const EdgeInsets.all(16),children:[
        const Text('Tävla mot dina fyra tidigare bästa lopp.',style:TextStyle(color:Colors.white70)),const SizedBox(height:16),
        if(!running&&!done)...[
          DropdownButtonFormField<String>(value:selected?.id,decoration:const InputDecoration(labelText:'Frågepaket'),
            items:widget.packs.map((p)=>DropdownMenuItem(value:p.id,child:Text('${p.title} (${p.count})',overflow:TextOverflow.ellipsis))).toList(),
            onChanged:(v){setState(()=>selected=widget.packs.firstWhere((p)=>p.id==v));_loadGhosts();}),
          const SizedBox(height:12),
          DropdownButtonFormField<String>(value:level,decoration:const InputDecoration(labelText:'Svårighet'),
            items:const [DropdownMenuItem(value:'mix',child:Text('Blandad')),DropdownMenuItem(value:'easy',child:Text('Lätt')),
              DropdownMenuItem(value:'medium',child:Text('Medel')),DropdownMenuItem(value:'hard',child:Text('Svår')),
              DropdownMenuItem(value:'expert',child:Text('Expert'))],onChanged:(v)=>setState(()=>level=v??'mix')),
          const SizedBox(height:12),
          DropdownButtonFormField<int>(value:questionCount,decoration:const InputDecoration(labelText:'Frågor i loppet'),
            items:[10,15,20].map((n)=>DropdownMenuItem(value:n,child:Text('$n frågor'))).toList(),onChanged:(v)=>setState(()=>questionCount=v??20)),
          const SizedBox(height:20),FilledButton.icon(onPressed:_start,icon:const Icon(Icons.flag),label:const Text('STARTA RACET')),
        ],
        if(running||done)...[
          _raceTrack(),const SizedBox(height:16),
          if(running)...[
            Text('Fråga ${min(index+1,questionCount)} av $questionCount • ${correct} rätt • $mistakes / $maxErrors fel',
              textAlign:TextAlign.center,style:const TextStyle(color:_accent,fontWeight:FontWeight.bold)),const SizedBox(height:16),
            if(q!=null)...[
              Text(q['question'] as String,textAlign:TextAlign.center,style:const TextStyle(fontSize:23,fontWeight:FontWeight.w800)),
              const SizedBox(height:14),
              if(!showExplanation) ...((q['options'] as List).map((a)=>Padding(padding:const EdgeInsets.only(bottom:9),
                child:FilledButton.tonal(onPressed:()=>_answer(a.toString()),child:Padding(padding:const EdgeInsets.all(11),child:Text(a.toString(),textAlign:TextAlign.center)))))),
              if(showExplanation)...[Text(verdict,style:const TextStyle(fontSize:19,color:_accent,fontWeight:FontWeight.bold)),
                if(explanation.isNotEmpty)Text(explanation),
                const SizedBox(height:14),FilledButton(onPressed:(){setState(() {showExplanation=false;questionStarted=DateTime.now();});},
                  child:const Text('NÄSTA FRÅGA'))],
            ],
          ]else _podium(),
        ],
      ]));
  }
}
