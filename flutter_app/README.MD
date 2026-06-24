# PROJEKT-SPEZIFIKATION: "Flight Crew Balance" (Event-Driven mit Supabase Broadcast)

## ARCHITEKTUR & FUNKTIONSWEISE
Das Spiel simuliert ein sinkendes Flugzeug. Es gibt zwei installierte App-Ansichten:
1. CONTROLLER (Smartphone der Spielleitung): Zwei Spielleiter tracken manuell via "+" und "-" Buttons die aktiven Personen. Der Controller sendet NUR BEI ÄNDERUNGEN (Event-driven) ein kleines Paket via Supabase Realtime Broadcast an das Tablet.
2. COCKPIT (Tablet für die Gruppe): Das Cockpit ist das Herzstück. Es empfängt die Counter und Wetter-Toggles. Eine INTERNE GAME-LOOP auf dem Tablet berechnet jede Sekunde die Flugphysik (Höhenverlust, Distanz zur Insel, Neigungswinkel) und visualisiert dies flüssig.

Es werden KEINE Daten in der Datenbank gespeichert. Alles läuft hocheffizient über flüchtige Supabase Broadcast Nachrichten.

---

## SCHRITT 1: PROJEKT-SETUP & DATEIEN
Erstelle ein neues Flutter-Projekt für iOS und Android. Erstelle die folgende Verzeichnisstruktur und leere Dateien:
- lib/models/flight_inputs.dart
- lib/services/supabase_service.dart
- lib/screens/home_screen.dart
- lib/screens/cockpit_screen.dart
- lib/screens/controller_screen.dart
- lib/main.dart

Füge diese Abhängigkeiten zur pubspec.yaml hinzu:
dependencies:
  flutter:
    sdk: flutter
  supabase_flutter: ^2.0.0 (oder aktuellste)
  provider: ^6.0.0

---

## SCHRITT 2: DAS EINGABE-MODELL (lib/models/flight_inputs.dart)
Erstelle die Klasse `FlightInputs`. Diese enthält NUR die reinen Steuerbefehle vom Handy:
- int counterLinks (Start: 0)
- int counterRechts (Start: 0)
- String aktivesWetter (Start: 'normal', Optionen: 'gewitter', 'wind_links', 'wind_rechts')
- bool spielGestartet (Start: false)

Implementiere `toJson()` und `fromJson(Map<String, dynamic> json)` für die Supabase-Übertragung.

---

## SCHRITT 3: SUPABASE BROADCAST SERVICE (lib/services/supabase_service.dart)
Erstelle einen `SupabaseService` mit `supabase_flutter`.
- Methode `init()`: Abonniere den Realtime-Channel "flight-stream".
- Methode `sendInputs(FlightInputs inputs)`: Sende die Inputs per `sendBroadcast(event: 'input_change', payload: inputs.toJson())`. Diese Methode wird vom Controller NUR aufgerufen, wenn ein Button gedrückt wird.
- Methode `listenToInputs(Function(FlightInputs) onMessage)`: Registriere einen Listener auf dem Channel für das Event 'input_change', damit das Cockpit die Änderungen sofort empfangen kann.

---

## SCHRITT 4: CONTROLLER-ANSICHT (lib/screens/controller_screen.dart)
Erstelle das UI für das Smartphone der Spielleitung:
1. Zwei riesige Buttons für LINKS und RECHTS mit großen "+" und "-" Symbolen, um `counterLinks` und `counterRechts` in einem lokalen `FlightInputs`-Objekt zu verändern.
2. Eine Sektion für Naturereignisse mit Toggle-Buttons: "Gewitter", "Böe Links", "Böe Rechts".
3. Einen großen "SPIEL STARTEN / RESET" Button.
4. **Logik:** Jedes Mal, wenn ein Plus/Minus/Wetter-Button gedrückt wird, aktualisiere den lokalen Zustand und rufe SOFORT einmalig `SupabaseService.sendInputs()` auf. Es läuft hier KEIN Hintergrund-Timer.

---

## SCHRITT 5: COCKPIT-ANSICHT MIT INTERNER PHYSIK (lib/screens/cockpit_screen.dart)
Erstelle das Cockpit-UI für das Tablet. Dieses enthält die eigentliche Spiele-Logik:
1. **Lokaler State auf dem Tablet:**
   - double aktuelleHoehe = 5000.0;
   - double aktuelleDistanz = 3000.0;
   - double neigungswinkel = 0.0;
   - int verbleibendeZeit = 180; // 3 Minuten
   - FlightInputs currentInputs = FlightInputs(); // Empfangen vom Server

2. **Die Game-Loop (Interner Timer):**
   Sobald `currentInputs.spielGestartet` auf true wechselt, starte einen `Timer.periodic(Duration(seconds: 1))`:
   - Verringere `verbleibendeZeit` um 1.
   - Berechne `windEinfluss`: Bei 'wind_links' -15 Grad, bei 'wind_rechts' +15 Grad.
   - Berechne `neigungswinkel`: `(currentInputs.counterLinks - currentInputs.counterRechts) * 4 + windEinfluss`.
   - Berechne `aktuelleHoehe`: Sinkt jede Sekunde standardmäßig um 15 Meter. Wenn `(currentInputs.counterLinks + currentInputs.counterRechts) >= 6`, sinkt es nur um 2 Meter. Wenn 'gewitter' aktiv ist, verliere zusätzlich 10 Meter pro Sekunde.
   - Berechne `aktuelleDistanz`: Sinkt jede Sekunde linear um 15 Meter.
   - Wenn `verbleibendeZeit <= 0` oder `aktuelleHoehe <= 0`, stoppe den Timer (Spiel vorbei).

3. **Visualisierung (UI):**
   - Künstlicher Horizont in der Mitte via `CustomPainter` (Kreis geteilt in Blau/Braun). Rotiere diesen Kreis über ein `AnimatedHorizontalIndicator` oder `Transform.rotate` flüssig basierend auf dem `neigungswinkel`.
   - Große digitale Neon-Anzeigen für Höhe, Distanz und die verbleibende Zeit.
   - Bei `aktivesWetter == 'gewitter'`: Aktiviere einen unregelmäßigen Flacker-Effekt (Hintergrund kurz weiß färben für Blitze) und lasse das gesamte Cockpit-Layout minimal zittern (Turbulenz-Simulation).

---

## SCHRITT 6: HOME SCREEN & MAIN (lib/screens/home_screen.dart & lib/main.dart)
Initialisiere Supabase in der `main()` mit den API-Credentials (URL und Anon-Key).
Erstelle im `HomeScreen` zwei große Schaltflächen für die Geräteauswahl:
1. "Als COCKPIT starten (Tablet)" -> Leitet weiter zum `CockpitScreen`.
2. "Als CONTROLLER starten (Smartphone)" -> Leitet weiter zum `ControllerScreen`.
