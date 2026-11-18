import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'game.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DuellenApp());
}

class DuellenApp extends StatelessWidget {
  const DuellenApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DUELLEN', debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true, brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xff101325),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xffd6ff61), brightness: Brightness.dark),
    ), home: const HostPage(),
  );
}

class HostPage extends StatefulWidget {
  const HostPage({super.key});
  @override State<HostPage> createState() => _HostPageState();
}

class _HostPageState extends State<HostPage> {
  final DuellenGame game = DuellenGame();
  final TextEditingController ipController = TextEditingController();
  bool loading = false;
  @override void initState() {
    super.initState(); game.addListener(_update); game.startServer();
  }
  void _update() { if (mounted) setState(() {}); }
  @override void dispose() {
    game.removeListener(_update); game.dispose(); ipController.dispose(); super.dispose();
  }
  Widget card(String name, Widget body) => Card(
    color: const Color(0xff1e2440),
    child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [Text(name,style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:12),body],
    )),
  );
  Widget line(String label,String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical:5),
    child: Row(children:[Expanded(child:Text(label)),Flexible(child:Text(value,
      textAlign:TextAlign.right,style:const TextStyle(fontWeight:FontWeight.bold)))]),
  );
  Future<void> start() async {
    setState(()=>loading=true);
    await game.startGame();
    if (mounted) setState(()=>loading=false);
  }
  @override Widget build(BuildContext context) {
    final waiting = game.phase=='lobby';
    final inQuestion = game.phase=='question';
    final reveal = game.phase=='reveal'||game.phase=='finished';
    final actors = game.eligible;
    return Scaffold(
      appBar: AppBar(title: const Text('⚔️ DUELLEN'),backgroundColor:const Color(0xff101325)),
      body: ListView(padding:const EdgeInsets.fromLTRB(12,8,12,32),children:[
        if(game.error.isNotEmpty)Card(color:const Color(0xff6d3030),child:Padding(
          padding:const EdgeInsets.all(14),child:Text(game.error))),
        if(waiting) ...[
          card('1. Anslut lag',Column(children:[
            const Text('Alla ansluter till samma Wi-Fi eller till huvudtelefonens hotspot. Skanna QR-koden med kameraappen.'),
            const SizedBox(height:14),
            if(game.address.isNotEmpty) ...[
              Center(child:Container(color:Colors.white,padding:const EdgeInsets.all(12),
                child:QrImageView(data:game.address,size:210))),
              const SizedBox(height:8),SelectableText(game.address,textAlign:TextAlign.center),
            ] else const Text('Startar lokal server …'),
            ExpansionTile(title:const Text('Ändra IP om QR-koden inte fungerar'),children:[
              TextField(controller:ipController,decoration:const InputDecoration(labelText:'Lokal IP-adress',hintText:'192.168.43.1')),
              TextButton(onPressed:()=>game.setIp(ipController.text),child:const Text('Använd adressen')),
            ]),
          ])),
          card('Relationsduellen',Column(children:[
            DropdownButtonFormField<String>(initialValue:game.relationsMode,
              decoration:const InputDecoration(labelText:'Välj par'),
              items:const [DropdownMenuItem(value:'random',child:Text('Slumpa två deltagare')),DropdownMenuItem(value:'manual',child:Text('Spelledaren väljer par'))],
              onChanged:(v){if(v!=null)game.setRelationsMode(v);}),
            const SizedBox(height:10),
            DropdownButtonFormField<String>(initialValue:game.relationsRule,
              decoration:const InputDecoration(labelText:'Relationsregler'),
              items:const [DropdownMenuItem(value:'match',child:Text('Tänker lika – båda får poäng')),DropdownMenuItem(value:'trap',child:Text('Tankefällan – stjäl poäng'))],
              onChanged:(v){if(v!=null)game.setRelationsRule(v);}),
          ])),
          card('2. Lag i lobbyn',Column(children:[
            for(final t in game.teams.values)line('✅ ${t.name}','Ansluten'),
            if(game.teams.isEmpty)const Text('Inga lag ännu.'),
            const SizedBox(height:12),
            SizedBox(width:double.infinity,child:FilledButton.icon(
              onPressed:loading||game.teams.length<2?null:start,
              icon:const Icon(Icons.play_arrow),label:Text(loading?'Laddar…':'Starta spel (${game.teams.length} lag)'),
            )),
          ])),
        ] else ...[
          card('Matchen',Column(children:[
            line('Runda','${game.round}'),
            line('Fas',{'ready':'Välj utmaning','bet':'Lagen satsar','question':'Svara nu','reveal':'Resultat','finished':'Slutresultat'}[game.phase]??game.phase),
            if(game.phase=='ready'||reveal) ...[
              if(reveal) ...[
                if(game.roundMode=='relation') ...[
                  Text(game.relationPrompt,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800)),
                  Text(game.relationSummary,style:const TextStyle(fontSize:20,color:Color(0xffd6ff61))),
                ] else
                  Text('Rätt svar: ${game.current?.answer??''}',style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800)),
                const SizedBox(height:8),
                for(final t in game.teams.values)
                  line('${t.name}: ${t.answered?t.answer:'—'}', '${t.verdict} ${t.change>0?'+':''}${t.change} p'),
                const Divider(),
              ],
              if(game.phase!='finished') ...[
                if(game.relationsMode=='manual' && actors.length>=2) ...[
                  const Text('Förutbestämt par till Relationsduellen:',style:TextStyle(fontWeight:FontWeight.bold)),
                  DropdownButtonFormField<String>(value:actors.any((t)=>t.id==game.selectedFirst)?game.selectedFirst:null,
                    decoration:const InputDecoration(labelText:'Person 1 – lägger svaret'),
                    items:actors.map((t)=>DropdownMenuItem(value:t.id,child:Text(t.name))).toList(),
                    onChanged:(v)=>setState(()=>game.selectedFirst=v??'')),
                  DropdownButtonFormField<String>(value:actors.any((t)=>t.id==game.selectedSecond)?game.selectedSecond:null,
                    decoration:const InputDecoration(labelText:'Person 2 – svarar'),
                    items:actors.map((t)=>DropdownMenuItem(value:t.id,child:Text(t.name))).toList(),
                    onChanged:(v)=>setState(()=>game.selectedSecond=v??'')),
                ],
                const Text('Välj nästa utmaning:',style:TextStyle(fontWeight:FontWeight.bold)),
                const SizedBox(height:8),
                _roundButton('🧠 Kunskapsfråga (+1)','normal'),
                _roundButton('🎲 Riskrunda (satsa 1–3)','risk'),
                _roundButton('⚔️ Duell (två lag)','duel'),
                _roundButton('🎯 Närmast vinner (+2)','closest'),
                _roundButton('🎁 Överraskning (+2)','surprise'),
                _roundButton('❤️ Relationsduellen','relation'),
              ],
            ],
            if(game.phase=='bet') ...[
              line('Låsta satsningar','${actors.where((t)=>t.betReady).length} / ${actors.length}'),
              const Text('Lagen satsar innan de får se frågan.'),
              const SizedBox(height:10),
              FilledButton(onPressed:game.beginAfterBets,child:const Text('Visa frågan')),
            ],
            if(inQuestion) ...[
              if(game.roundMode!='relation') ...[
                Text('${game.remaining}',style:const TextStyle(fontSize:76,fontWeight:FontWeight.w900)),
                Text(game.current?.category??'',style:const TextStyle(color:Color(0xffd6ff61))),
                Text(game.current?.prompt??'',style:const TextStyle(fontSize:23,fontWeight:FontWeight.bold),textAlign:TextAlign.center),
              ],
              if(game.roundMode=='duel')Text('Duell: ${game.duelIds.map((id)=>game.teams[id]?.name??'').join(' mot ')}'),
              if(game.roundMode=='relation') ...[
                Text(game.relationPrompt,style:const TextStyle(fontSize:24,fontWeight:FontWeight.bold),textAlign:TextAlign.center),
                Text('❤️ ${game.relationSetterName} mot ${game.relationReaderName}'),
                Text(game.relationStage=='setter'?'Väntar på första hemliga svaret':'Väntar på motspelarens svar'),
                const Text('Svar och strategi är dolda tills båda svarat.'),
              ],
              const SizedBox(height:10),
              line('Svar inkomna', '${game.teams.values.where((t)=>t.answered).length}'),
              if(game.roundMode!='relation')
                OutlinedButton(onPressed:game.reveal,child:const Text('Avsluta nu och visa facit')),

            ],
            if(game.phase=='finished') const Text('🏆 Matchen är klar! Starta om appen för en ny match.'),
          ])),
          card('Poängställning',Column(children:[
            for(final t in game.teams.values) ...[
              line('${t.place==null?'':'🏆 ${t.place}. '}${t.name}${t.qualified?' ✅':''}','${t.points} p'),
              Text('${t.badges.length}/3 kategorier: ${t.badges.join(', ')}',style:const TextStyle(color:Colors.white70,fontSize:12)),
              const Divider(),
            ],
          ])),
        ],
        const SizedBox(height:14),
        const Text('DUELLEN v0.2 • Relationsduellen • 10 poäng + 3 kategorier',
            textAlign:TextAlign.center,style:TextStyle(color:Colors.white54,fontSize:12)),
      ]),
    );
  }
  Widget _roundButton(String text,String mode) => Padding(
    padding:const EdgeInsets.only(bottom:7),
    child:SizedBox(width:double.infinity,child:FilledButton.tonal(
      onPressed:()=>game.prepareRound(mode),child:Text(text),
    )),
  );
}
