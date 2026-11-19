import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

class QuestionPack {
  const QuestionPack(this.id, this.title, this.topic, this.questions, {this.builtin = false});
  final String id, title, topic;
  final bool builtin;
  final List<Map<String, dynamic>> questions;
  int get count => questions.length;
}

class QuestionPackStore {
  static const builtinId = 'standard';
  static String _slug(String input) => input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9åäö]+'), '-');
  static Future<Directory> _folder() async {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/duellen_packs');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
  static Future<List<QuestionPack>> all() async {
    final builtInRaw = await rootBundle.loadString('assets/data/questions.json');
    final builtIn = QuestionPack(builtinId, 'Blandade ämnen', 'Blandat',
      _parseQuestions(jsonDecode(builtInRaw)), builtin: true);
    final result = <QuestionPack>[builtIn];
    final folder = await _folder();
    await for (final item in folder.list()) {
      if (item is! File || !item.path.endsWith('.json')) continue;
      try { result.add(_fromJson(jsonDecode(await item.readAsString()))); } catch (_) { /* Ignore broken files, don't crash game */ }
    }
    result.sort((a,b) => a.builtin ? -1 : b.builtin ? 1 : a.title.compareTo(b.title));
    return result;
  }
  static QuestionPack _fromJson(dynamic decoded) {
    if (decoded is! Map) throw const FormatException('Frågefilen behöver ett objekt med id, title och questions.');
    final map = Map<String,dynamic>.from(decoded);
    final title = (map['title'] ?? '').toString().trim();
    final topic = (map['topic'] ?? title).toString().trim();
    final id = (map['id'] ?? _slug(title)).toString().trim();
    if (title.isEmpty || id.isEmpty || !RegExp(r'^[a-zA-Z0-9_-]{2,70}$').hasMatch(id)) {
      throw const FormatException('Paketet saknar giltig titel eller id (2–70 tecken, bokstäver/siffror/-/_).');
    }
    if (id == builtinId) throw const FormatException('Det paket-ID:t är reserverat.');
    final questions = _parseQuestions(map['questions']);
    if (questions.isEmpty) throw const FormatException('Frågepaketet är tomt.');
    return QuestionPack(id,title,topic,questions);
  }
  static List<Map<String,dynamic>> _parseQuestions(dynamic data) {
    if (data is! List) throw const FormatException('questions måste vara en lista.');
    if (data.length > 3000) throw const FormatException('Max 3000 frågor per fil.');
    final result = <Map<String,dynamic>>[];
    final seen = <String>{};
    for (final item in data) {
      if (item is! Map) throw const FormatException('Ogiltig fråga.');
      final q = Map<String,dynamic>.from(item);
      final category = (q['category'] ?? '').toString().trim();
      final question = (q['question'] ?? '').toString().trim();
      final answer = (q['answer'] ?? '').toString().trim();
      final kind = (q['kind'] ?? 'choice').toString();
      final difficulty = (q['difficulty'] ?? 'medium').toString();
      if (category.isEmpty || question.isEmpty || answer.isEmpty || question.length>500 || answer.length>180) {
        throw const FormatException('En fråga saknar kategori, text eller facit.');
      }
      if (!['choice','number'].contains(kind) || !['easy','medium','hard','expert'].contains(difficulty)) {
        throw const FormatException('En fråga har ogiltig typ eller svårighetsgrad.');
      }
      final options = q['options'];
      if (options is! List) throw const FormatException('Varje fråga måste ha options-lista.');
      if (kind == 'choice' && (options.length != 4 || !options.map((e)=>e.toString()).contains(answer) || options.toSet().length!=4)) {
        throw const FormatException('Flervalsfrågor måste ha fyra unika alternativ inklusive rätt svar.');
      }
      if(kind == 'number' && double.tryParse(answer.replaceAll(',','.'))==null) {
        throw const FormatException('Sifferfrågor behöver ett numeriskt facit.');
      }
      final key = '$category|$question'.toLowerCase();
      if(!seen.add(key)) continue;
      q['category']=category; q['question']=question; q['answer']=answer;
      q['kind']=kind; q['difficulty']=difficulty;
      q['options']=options.map((e)=>e.toString()).toList();
      result.add(q);
    }
    return result;
  }
  static Future<QuestionPack> importUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('Ange en giltig HTTPS-länk direkt till en JSON-frågefil.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      client.autoUncompress = true;
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) throw FormatException('Kunde inte hämta filen: HTTP ${response.statusCode}.');
      final chunks = <int>[];
      await for (final chunk in response) {
        chunks.addAll(chunk);
        if (chunks.length > 1500000) throw const FormatException('Frågefilen är för stor (max 1,5 MB).');
      }
      final pack = _fromJson(jsonDecode(utf8.decode(chunks)));
      await _savePack(pack);
      return pack;
    } finally { client.close(force:true); }
  }
  static Future<void> _savePack(QuestionPack pack) async {
    final dir=await _folder();
    await File('${dir.path}/${pack.id}.json').writeAsString(jsonEncode({
      'id':pack.id,'title':pack.title,'topic':pack.topic,'questions':pack.questions,
    }),flush:true);
  }
  static Future<QuestionPack?> importFile() async {
    final result = await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['json'],withData:true);
    if (result==null || result.files.isEmpty) return null;
    final picked=result.files.single;
    if (picked.size>1500000) throw const FormatException('Filstorlek får vara högst 1,5 MB.');
    final bytes = picked.bytes ?? (picked.path==null ? null : await File(picked.path!).readAsBytes());
    if(bytes==null) throw const FormatException('Kunde inte läsa filen.');
    final decoded=jsonDecode(utf8.decode(bytes));
    final pack=_fromJson(decoded);
    await _savePack(pack);
    return pack;
  }
}
