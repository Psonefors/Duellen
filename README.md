# DUELLEN – första spelbara prototypen

Ett nytt, lokalt familjequiz med Flutter på spelledartelefonen och webbläsare på de andra telefonerna. **Ingen musiklicens, ingen databas, ingen internetanslutning krävs under spelet.** Alla deltagare ansluter till samma Wi-Fi/hotspot; QR-koden leder till huvudtelefonens lokala HTTP-server på port 8765.

## Lägen
- Kunskapsfråga: +1 poäng för rätt.
- Riskrunda: välj 1–3 poäng **innan frågan syns**; rätt ger plus, fel ger minus (lägst noll).
- Duell: två aktiva lag väljs slumpmässigt; rätt svar vinner +2, vid två rätt vinner snabbast; övriga tittar på.
- Närmast vinner: alla anger ett tal, närmast rätt värde får +2 (delad vinst vid lika avstånd).
- Överraskning: frågan ger +2 poäng för rätt, 0 för fel.

Lagen samlar kategorimärken för rätt svar. **För att gå i mål krävs 10 poäng och minst 3 olika kategorimärken.** Spelet fortsätter tills alla utom det sista laget har kvalificerat sig. Vid lika poäng i samma omgång delas placeringen. Inga avgörande utslagsfrågor ännu.

## Bygg APK med GitHub
1. Skapa ett **nytt** GitHub-repository, gärna privat, till exempel `duellen` (inte ditt befintliga `musikduellen`).
2. Packa upp ZIP-filen och ladda upp mapparna `lib`, `assets`, `.github` samt `pubspec.yaml` och `README.md` **med katalogstrukturen bevarad**. Ladda inte upp ZIP-filen som enda fil.
3. Under Actions kör workflow `Bygg Duellen APK` automatiskt. När den är grön: öppna körningens Summary → Artifacts → Duellen-APK. Packa upp ZIP-filen och installera `app-release.apk`.
4. Huvudtelefonen startar appen, ansluter till Wi-Fi eller startar hotspot. Alla andra ansluter till samma nät och skannar QR-koden. Ändra IP i appen om Android valt fel nätverksadress. Minst två lag krävs.

## Observera
Detta är v0.1 och är **inte testkompilerad på Android** i denna miljö. Vi bör först provspela med 2–3 telefoner. Ingen inloggning eller säkerhet mot fusk finns. Klienterna kan läsa egen historik men aldrig facit före rättning. Nätverket är lokalt och okrypterat HTTP; använd bara på betrodda nät. Ännu ingen persistent sparning, uppspelningsljud eller permanenta inställningar. Frågorna ligger i `assets/data/questions.json` och kan ändras senare.

## Nytt i v0.2 – Relationsduellen
- Före spelstart väljer spelledaren om relationer ska lottas eller väljas manuellt samt **Tänker lika** eller **Tankefällan**.
- Vid manuellt val väljs de två deltagarna under *Välj nästa utmaning*, före knappen ❤️ Relationsduellen. Vid slumpning försöker spelet undvika samma par två gånger i rad.
- **Tänker lika:** båda svarar utan att se varandras svar. Matchande svar ger **+2 poäng var**, annars 0.
- **Tankefällan:** den första deltagaren lämnar ett hemligt svar. Den andra väljer att antingen spela med, vilket ger den första +2 vid matchning, eller försöka stjäla, vilket ger den andra +2 om hen gissar rätt; om stöldförsöket misslyckas får den första +2. Om man spelar med men inte matchar blir det 0.
- Alternativen använder de båda deltagarnas *namn* samt "Båda lika mycket", inte "Jag"/"Du".
- Resultatet visar bådas svar och poängfördelningen både på mobiltelefonerna och hos spelledaren.
- Relationsrundan är **turordningsbaserad utan tidspress** för att undvika att den andra hinner se svaret före sin tur.
- I den här prototypen är varje ansluten telefon en deltagare (eller ett lag som väljer gemensamt svar). Registrering av enskilda personer inom lag är en möjlig nästa version.

## Tekniskt
Projektet har en riktig Flutter-katalogstruktur (`lib/`, `assets/`, `.github/`). GitHub Actions kör `flutter create`, `flutter pub get`, kodanalys och release-APK-bygge. APK:n är **inte kompilerad eller provspelad i den här arbetsmiljön**. Testa med minst två anslutna telefoner, gärna tre för att se slumpningen.
