# CHAKOTAY

**Cross-platform Hymn Audio Kiosk for Offline Track Access and PlaYback**

CHAKOTAY ist der native Offline-Wiedergabeclient für [CHAPEL](https://github.com/JannisRoesner/CHAPEL)
(Church Hymn Audio Playlist Engine for Liturgy) – eine App für **iOS und Android** aus einer
gemeinsamen Codebasis. Gottesdienste werden einmal vom CHAPEL-Server geladen, geprüft und dauerhaft
auf dem Gerät gespeichert. Danach spielt CHAKOTAY sie **ohne Internet und ohne Anmeldung** ab –
mit demselben Bedienkonzept wie der CHAPEL-Player: *Play → Stopp nach jedem Titel → nächster Titel
erst auf Knopfdruck*.

| | |
|---|---|
| Plattformen | Android 7.0+ (API 24), iOS 13+ |
| Technologie | Flutter 3.41 / Dart 3.11 |
| Server | CHAPEL mit Paket-API (`/api/packages`) |
| Lizenz | GNU AGPL v3.0 oder später (wie CHAPEL) |

---

## Inhalt

1. [Funktionen](#funktionen)
2. [Das Akronym](#das-akronym)
3. [Technologie-Stack und Begründung](#technologie-stack-und-begründung)
4. [Architektur](#architektur)
5. [Projektstruktur](#projektstruktur)
6. [Entwicklungsumgebung einrichten](#entwicklungsumgebung-einrichten)
7. [Android-App starten](#android-app-starten)
8. [iOS-App starten](#ios-app-starten)
9. [Release-Builds](#release-builds)
10. [CHAPEL-Server verbinden](#chapel-server-verbinden)
11. [Offline-Pakete herunterladen](#offline-pakete-herunterladen)
12. [Wiedergabebedienung](#wiedergabebedienung)
13. [Tests](#tests)
14. [Continuous Integration](#continuous-integration)
15. [Design](#design)
16. [Sicherheit](#sicherheit)
17. [Bekannte Einschränkungen](#bekannte-einschränkungen)
18. [Lizenz](#lizenz)

---

## Funktionen

- **Offline-Bibliothek** (Startansicht): alle geladenen Gottesdienste mit Datum, Schrittzahl, Größe,
  Status („Offline verfügbar“, „Update verfügbar“, „Wird aktualisiert“, „Aktualisierung
  fehlgeschlagen“); sortierbar (nächste zuerst, neueste zuerst, älteste zuerst); Aktionen
  *Aktualisieren/Erneut herunterladen*, *Paketinformationen*, *Löschen*. Funktioniert vollständig
  offline.
- **Laden**: Serveradresse eingeben (Erreichbarkeit wird geprüft), mit E-Mail und Passwort anmelden,
  Gottesdienste des Servers anzeigen, einen oder mehrere auswählen und laden – mit Fortschritt,
  Abbruch, Warteschlange und den Zuständen *Nicht geladen · Aktuell · Update verfügbar · Wird geladen ·
  Fehlgeschlagen*.
- **Robuste Paketverwaltung**: Download in eine temporäre Datei, defensiver ZIP-Leser, Manifest-
  Validierung, CRC32- und SHA-256-Prüfung jeder Audiodatei, atomarer Austausch, deduplizierte
  Audiobibliothek mit Referenzprüfung beim Löschen, Aufräumen nach Abbruch oder App-Beendigung.
- **Wiedergabe** (Herzstück): kompletter Ablauf mit Liturgie/Lied-Unterscheidung, hervorgehobener
  aktueller Schritt, Titel/Komponist/Dauer/Tempo, Fortschrittsbalken, große Bedienelemente (Abspielen/
  Pause, Nächster, Vorheriger, Stopp), deutliche Statusanzeige, automatischer Stopp am Titelende,
  leere Schritte sichtbar und übersprungen, Tempo tonhöhenerhaltend, Fortschritt gespeichert.
- **Einstellungen**: Serveradresse, Verbindungsstatus, Benutzer, An-/Abmelden, Hell/Dunkel/System,
  „Bildschirm aktiv halten“, belegter Speicher, Version, Quellcode, Lizenzen.
- Hell- und Dunkelmodus, dynamische Schriftgrößen, Screenreader-Beschriftungen, Hoch- und Querformat,
  Telefon und Tablet (Navigation Rail und zweispaltige Wiedergabe ab 720/840 pt Breite).

## Das Akronym

**C**ross-platform **H**ymn **A**udio **K**iosk for **O**ffline **T**rack **A**ccess and Pla**Y**back –
eine plattformübergreifende „Kiosk“-App für Kirchenlieder: Sie macht Gottesdienst-Audiodateien offline
zugänglich und spielt sie kontrolliert ab. Wie CHAPEL, RIKER, PICARD und SPOCK trägt das Projekt den
Namen einer Star-Trek-Figur.

## Technologie-Stack und Begründung

Geprüft wurden Flutter (Dart), Kotlin Multiplatform mit Compose Multiplatform, React Native
(TypeScript) und native Einzel-Apps.

| Kriterium | Flutter | KMP + Compose MP | React Native |
|---|---|---|---|
| Lokale MP3-Wiedergabe | `just_audio` → ExoPlayer/Media3 bzw. AVPlayer | eigene `expect/actual`-Implementierung je Plattform | `react-native-track-player` (Playlist-zentriert) |
| Tempo ohne Tonhöhenänderung | `setSpeed` (ExoPlayer `PlaybackParameters`, AVPlayer Time-Domain-Pitch) | nativ möglich, aber selbst zu bauen | abhängig von der Bibliothek |
| Audio-Unterbrechungen | `audio_session` (AVAudioSession/AudioFocus) einheitlich | selbst zu bauen | teilweise |
| Große ZIP-Dateien, Streaming, SHA-256 | `dart:io` + `crypto`, vollständig gemeinsam | `okio` gemeinsam | native Module nötig |
| Sichere Cookie-Ablage | `flutter_secure_storage` (Keychain/Keystore) | selbst je Plattform | `react-native-keychain` |
| Gemeinsamer UI-Code | 100 % | Compose MP auf iOS jünger | 100 %, Bridge-Overhead |
| Reife/Wartbarkeit für Audio | sehr hoch, stabile Plugins | iOS-UI noch jünger | gut |

**Entscheidung: Flutter mit Dart.** Ausschlaggebend waren (1) eine bewährte, gut gepflegte
Audiobibliothek, die genau eine Datei abspielt und tonhöhenerhaltendes Tempo auf beiden Plattformen
über native Player umsetzt, (2) ein einheitliches Interruption-Handling über `audio_session`,
(3) `dart:io`, mit dem Download, ZIP-Prüfung und Hashing komplett im gemeinsamen Code und
ohne Plattformbrücken testbar sind, und (4) eine UI, die auf beiden Plattformen identisch funktioniert
und sich dennoch plattformtypisch verhält (Cupertino-Übergänge und -Dialoge auf iOS, Material auf
Android). Der Anteil plattformspezifischen Codes beschränkt sich auf Manifest/Info.plist.

Abhängigkeiten (bewusst wenige):

| Paket | Zweck |
|---|---|
| `just_audio` | Audiowiedergabe (ExoPlayer/AVPlayer), Tempo |
| `audio_session` | Audio-Kategorie, Unterbrechungen, „Becoming noisy“ |
| `flutter_secure_storage` | Session-Cookie in Keychain/Keystore |
| `crypto` | SHA-256 |
| `path_provider` | App-Support-Verzeichnis |
| `shared_preferences` | nicht-geheime Einstellungen |
| `wakelock_plus` | Bildschirm während der Wiedergabeansicht aktiv halten |
| `url_launcher` | CHAPEL-Weboberfläche für Passwortwechsel öffnen |
| `package_info_plus` | Versionsanzeige |
| `intl`, `flutter_localizations` | deutsche Datums-/Zahlenformate, Material-Texte |

## Architektur

```
┌──────────────────────── UI (lib/ui) ────────────────────────┐
│ HomeShell (Tabs/Rail) · LibraryScreen · DownloadsScreen ·    │
│ SettingsScreen · PlayerScreen · PackageInfoSheet · Theme     │
└──────────────┬───────────────────────────────┬──────────────┘
               │ ListenableBuilder              │
┌──────────────▼─────────┐   ┌────────────────▼──────────────┐
│ App-State               │   │ PlayerController (playback/)   │
│ AccountController (auth)│   │ Zustandsautomat wie CHAPEL     │
│ LibraryController       │   │  ├─ AudioEngine (Interface)    │
│ SettingsStore           │   │  │   └─ JustAudioEngine        │
└───┬──────────┬──────────┘   │  └─ ProgressStore              │
    │          │              └────────────────────────────────┘
┌───▼───────┐ ┌▼──────────────────────────────────────────────┐
│ API        │ │ Paketverwaltung (packages/)                    │
│ ChapelApi- │ │ SafeZipReader → PackageInstaller →             │
│ Client     │ │ PackageRepository (audio/, packages/, tmp/)    │
│ SessionStore│ │ PackageManifest (Parsing + Validierung)       │
└────────────┘ └───────────────────────────────────────────────┘
```

- **Präsentation/Navigation** (`lib/ui`, `lib/app`): drei Tabs mit `IndexedStack` (Zustand bleibt
  erhalten), ab 840 pt eine `NavigationRail`; die Wiedergabe ist eine eigene Route.
- **App-State**: `ChangeNotifier`-Controller, bereitgestellt über ein `InheritedWidget` (`AppScope`) –
  ohne zusätzliches State-Management-Framework.
- **API** (`lib/api`): `ChapelApiClient` auf `dart:io`-`HttpClient`. Statuscodes werden auf fachliche
  Fehler abgebildet (`401` → Sitzung abgelaufen, `403` → Passwortwechsel, …). `GET /api/auth/me`
  dient zusätzlich als Erreichbarkeitsprüfung („ist das ein CHAPEL-Server?“).
- **Authentifizierung** (`lib/auth`): Das Cookie `nuxt-session` wird aus `Set-Cookie` gelesen und
  ausschließlich im `SessionStore` (Keychain/Keystore) gehalten; Löschungen (`Max-Age=0`) werden
  übernommen. Passwörter werden nie gespeichert.
- **Paketverwaltung** (`lib/packages`): siehe [Offline-Pakete](#offline-pakete-herunterladen).
- **Lokale Datenhaltung**: Dateisystem unter *Application Support*/`chakotay/` (Pakete, Audio,
  Fortschritt), `shared_preferences` für Einstellungen.
- **Audio-Engine** (`lib/playback`): `AudioEngine` ist eine schmale Schnittstelle, die genau **eine**
  Datei lädt. Es gibt keine Warteschlange – ein automatischer Übergang zum nächsten Titel ist dadurch
  schon technisch ausgeschlossen. `PlayerController` enthält die gesamte Bedienlogik und ist mit einer
  Fake-Engine vollständig testbar.
- **Einstellungen** (`lib/settings`): `SettingsStore` über eine `KeyValueStore`-Abstraktion.

### Abgleich mit CHAPEL

Die Implementierung folgt dem CHAPEL-Quellcode, nicht nur der README:

| CHAPEL | CHAKOTAY |
|---|---|
| `shared/types/chapel.ts` (`PackageManifestDto`, `PackageStepDto`, `PackageSummaryDto`, `SessionUser`) | `lib/packages/manifest.dart`, `lib/api/models.dart` |
| `server/utils/servicePackage.ts` (ZIP STORE, Dateiname `audio/<storageKey>`, `sha256` = Hash vor `@`, Tempo-Varianten teilen Dateien, `version` = Inhalts-Hash) | `SafeZipReader`, `PackageInstaller`, Deduplizierung über `sha256` |
| `server/middleware/auth.ts` (403 bei `mustChangePassword` vor 401) | `AccountState.passwordChangeRequired`, Hinweis + Link zur Weboberfläche |
| `app/composables/useChapelPlayer.ts` (`idle/playing/paused/pausedAfterTrack`, `ended` → Auswahl weiter ohne Start, „Nächster“ startet) | `PlayerController` (`PlaybackStatus`) |
| `app/composables/usePlaybackProgress.ts` (Index + gespielte Schritte, 24 h TTL, Reset bei Ablaufänderung) | `ProgressStore` mit Paket-`version` als Fingerabdruck |
| `shared/constants/audio.ts` (Tempo 0,5–1,5, Endungen mp3/wav/flac/ogg) | Validierung im Manifest-Parser |

Bewusste, dokumentierte Abweichungen vom Webplayer:

- **Leere Schritte** (`audio: null`) werden beim Weiterschalten übersprungen (Auftrag + README der
  Paket-API). Der Webplayer wählt nach Titelende den direkt folgenden Schritt, auch wenn er leer ist.
- **„Vorheriger“** und **„Stopp“** sind zusätzliche Bedienelemente; „Vorheriger“ wählt nur aus und
  startet nichts.
- **Zeitanzeige in Echtzeit**: Position und Dauer werden durch das Tempo geteilt, damit sie zu
  `durationMs` aus dem Manifest passen (der Webplayer zeigt Medienzeit).
- **Unterbrechungen**: nach Anruf/fremdem Audio wird nie automatisch fortgesetzt.

**Notwendige API-Anpassungen an CHAPEL: keine.** Alle benötigten Endpunkte existieren. Optional
nützlich wäre künftig ein `Range`-Support für `/api/packages/:id/download`, um abgebrochene Downloads
fortsetzen zu können (derzeit wird neu begonnen).

## Projektstruktur

```
lib/
  main.dart                   Einstiegspunkt, Verdrahtung der Dienste
  app/                        App-Widget, Navigation (HomeShell), AppScope
  api/                        ChapelApiClient, ServerAddress, DTOs
  auth/                       AccountController, SessionStore (Keychain/Keystore)
  core/                       AppFailure (Fehlerarten + Texte), CancelToken
  library/                    LibraryController (Bibliothek, Downloads, Status)
  packages/                   Manifest, SafeZipReader, PackageInstaller, PackageRepository
  playback/                   AudioEngine, JustAudioEngine, PlayerController, ProgressStore
  settings/                   SettingsStore, KeyValueStore
  ui/                         Theme/Tokens, Formatierung, Screens, Widgets
test/
  api/ packages/ playback/ ui/   Unit- und Widget-Tests
  integration/                Ende-zu-Ende-Ablauf gegen simulierten CHAPEL-Server
  support/                    Fake-CHAPEL-Server (echter HTTP-Server), ZIP-Builder, Fake-Engine
assets/icon/                  App-Icon (Quelle für flutter_launcher_icons)
android/ ios/                 Plattformprojekte
.github/workflows/ci.yml      CI: Format, Analyse, Tests, Android-APK, iOS-Build
```

## Entwicklungsumgebung einrichten

Voraussetzungen:

- Flutter **3.41.x** (stable) mit Dart 3.11 – `flutter --version`
- Android: Android Studio oder Android SDK (Platform 35/36, Build-Tools), JDK 17+,
  Lizenzen akzeptiert: `flutter doctor --android-licenses`
- iOS: macOS mit Xcode 16+ und CocoaPods (`sudo gem install cocoapods` oder Homebrew)

```bash
git clone https://github.com/JannisRoesner/CHAKOTAY.git
```

```bash
cd CHAKOTAY && flutter pub get
```

```bash
flutter doctor
```

## Android-App starten

Gerät per USB (Entwickleroptionen + USB-Debugging) oder Emulator starten, dann:

```bash
flutter run
```

## iOS-App starten

Auf einem Mac:

```bash
cd ios && pod install && cd ..
```

```bash
open ios/Runner.xcworkspace
```

In Xcode unter *Runner → Signing & Capabilities* ein Team wählen (kostenloses Apple-ID-Team reicht
für eigene Geräte) und ggf. den Bundle Identifier `family.roesner.chakotay` anpassen. Danach:

```bash
flutter run
```

Im Simulator ist keine Signierung nötig (`open -a Simulator`, dann `flutter run`).
Die Capability **Background Modes → Audio** ist bereits in `Info.plist` (`UIBackgroundModes: audio`)
eingetragen, damit die Wiedergabe bei gesperrtem Gerät weiterläuft.

## Release-Builds

### Android

```bash
flutter build apk --release
```

```bash
flutter build appbundle --release
```

Ohne eigene Signatur wird mit dem Debug-Schlüssel signiert (zum Testen installierbar, nicht für den
Play Store). Für eine echte Release-Signatur:

```bash
keytool -genkey -v -keystore ~/chakotay-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias chakotay
```

und `android/key.properties` anlegen (ist in `.gitignore`, **nie committen**):

```properties
storeFile=/Users/<name>/chakotay-release.jks
storePassword=…
keyAlias=chakotay
keyPassword=…
```

### iOS

```bash
flutter build ipa --release
```

Voraussetzungen: Apple-Developer-Mitgliedschaft, App-ID `family.roesner.chakotay`, ein
Distribution-Zertifikat und ein Provisioning-Profil (App Store oder Ad Hoc), in Xcode beim Target
*Runner* ausgewählt. Das IPA liegt danach unter `build/ios/ipa/` und kann per Xcode Organizer oder
Transporter hochgeladen werden. `ITSAppUsesNonExemptEncryption` ist auf `false` gesetzt (nur
Standard-HTTPS).

### App-Icons neu erzeugen

```bash
dart run flutter_launcher_icons
```

## CHAPEL-Server verbinden

1. Tab **Laden** öffnen.
2. Serveradresse eingeben – dieselbe wie im Browser, z. B. `chapel.gemeinde.de`. Ohne Schema wird
   automatisch `https://` verwendet. CHAKOTAY prüft über `GET /api/auth/me`, ob dort ein
   CHAPEL-Server antwortet.
3. Mit E-Mail und Passwort des CHAPEL-Kontos anmelden (Rolle egal).

Hinweise:

- **HTTP** (z. B. `http://192.168.1.20:3001` für einen lokalen Entwicklungsserver) ist nur nach einer
  ausdrücklichen Warnung und Bestätigung möglich. TLS-Zertifikate werden immer vollständig geprüft;
  es gibt keine Option, ungültige Zertifikate zu akzeptieren.
- Verlangt CHAPEL einen **Passwortwechsel** (`mustChangePassword`), zeigt CHAKOTAY einen Hinweis und
  öffnet auf Wunsch die CHAPEL-Weboberfläche (`/settings`).
- Läuft die Sitzung ab (`401`), wird erneut zur Anmeldung aufgefordert. Bereits geladene Gottesdienste
  bleiben jederzeit abspielbar – auch nach dem Abmelden.

## Offline-Pakete herunterladen

Im Tab **Laden** erscheinen alle Gottesdienste des Servers (`GET /api/packages`) mit Status. Einen oder
mehrere antippen und **„Gottesdienste laden“** wählen; Updates können gesammelt geladen werden.

Ablauf je Paket:

1. `GET /api/packages/:id/download` wird gestreamt in `tmp/` geschrieben (Fortschritt über
   `Content-Length`, abbrechbar, Leerlauf-Timeout 30 s).
2. **Container prüfen**: End-of-Central-Directory, keine ZIP64-/Mehrteil-/verschlüsselten Archive,
   nur STORE/DEFLATE, keine doppelten Namen, keine überlappenden Einträge, lokale Header stimmen mit dem
   Verzeichnis überein, alle Daten liegen innerhalb der Datei.
3. **Pfade prüfen**: keine absoluten Pfade, kein `..`, keine Backslashes/Laufwerksbuchstaben;
   erlaubt sind nur `manifest.json` und genau die im Manifest referenzierten `audio/<name>.<mp3|wav|flac|ogg>`.
4. **Manifest validieren**: `formatVersion` (unbekannt → „Bitte App aktualisieren“), Pflichtfelder,
   Typen, Prüfsummenformat, konsistente Angaben bei mehrfach verwendeten Dateien, Tempo-Grenzen.
5. **Dateien prüfen**: Größe laut Manifest, Größenbegrenzung beim Entpacken (Schutz vor Zip-Bomben),
   CRC32 und **SHA-256** jeder Audiodatei.
6. Geprüfte Dateien wandern in die gemeinsame Bibliothek `audio/<sha256>.<ext>`; bereits vorhandene
   identische Dateien werden nicht erneut abgelegt (**Deduplizierung**, auch für Tempo-Varianten).
7. Erst dann wird der Paketdatensatz **atomar** geschrieben (Temp-Datei + `rename`) und ersetzt einen
   alten Stand.
8. Nicht mehr referenzierte Audiodateien werden entfernt; eine Datei bleibt erhalten, solange irgendein
   Paket sie benötigt.
9. Temporäre Dateien werden in jedem Fall gelöscht; Reste nach einem App-Abbruch beim nächsten Start.

Schlägt ein Schritt fehl oder wird abgebrochen, bleibt ein vorhandenes, funktionsfähiges Paket
unverändert. Der Hinweis „Update verfügbar“ wird anhand der zuletzt abgefragten Serverversionen auch
offline angezeigt.

Speicherort: *Application Support*/`chakotay/library/` (iOS: nicht für Benutzer sichtbar; Android:
app-privater Speicher). Android-Backups sind deaktiviert, damit keine großen Audiodaten oder
Sitzungsdaten in Cloud-Backups landen.

## Wiedergabebedienung

Gottesdienst in der Bibliothek antippen. Die Ansicht zeigt oben den Ablauf und unten (im Querformat
bzw. auf Tablets rechts) das Bedienfeld.

| Element | Wirkung |
|---|---|
| **Abspielen / Pause** | spielt den ausgewählten Schritt bzw. pausiert/setzt fort |
| **Nächster** | wechselt zum nächsten Schritt mit Audio **und startet ihn** |
| **Vorheriger** | wählt den vorherigen Schritt mit Audio aus (ohne Start) |
| **Stopp** | hält an und setzt den Titel auf den Anfang |
| Schritt antippen | wählt ihn aus und stoppt eine laufende Wiedergabe |

Verhalten:

- Am **Titelende stoppt** die Wiedergabe immer. Die Auswahl springt auf den nächsten Schritt mit Audio
  (Status „Titel beendet – bereit“), **gestartet wird nichts**. Nach dem letzten Titel erscheint
  „Letzter Titel beendet“.
- Liturgie und Lieder sind farblich **und** textlich unterschieden („LITURGIE · Kyrie“,
  „LIED · Eingangslied“); gespielte Schritte sind abgehakt.
- **Leere Schritte** bleiben an ihrer Position sichtbar („Kein Audio – wird übersprungen“), sind keine
  Fehler und werden beim Weiterschalten übersprungen.
- **Tempo-Varianten** laufen mit dem `playbackRate` aus dem Manifest, tonhöhenerhaltend; ein Badge
  („92 %“) zeigt abweichendes Tempo. Zeiten werden in Echtzeit angezeigt.
- Der **Fortschritt** (aktueller Schritt, gespielte Schritte) wird lokal gespeichert und beim erneuten
  Öffnen wiederhergestellt – wie in CHAPEL für 24 Stunden und nur, solange sich die Paketversion nicht
  geändert hat.
- **Unterbrechungen**: Anruf, Siri, Alarm oder eine andere Audio-App pausieren die Wiedergabe; nach
  dem Ende der Unterbrechung wird **nicht** automatisch fortgesetzt (Hinweis im Bedienfeld). Werden
  Kopfhörer/Bluetooth getrennt, wird pausiert. Kurze „Ducking“-Unterbrechungen (z. B.
  Navigationsansagen) senken nur die Lautstärke.
- **Hintergrund/Sperre**: Ein laufender Titel spielt bei gesperrtem Gerät bzw. im Hintergrund weiter
  und stoppt am Ende ebenso. Optional bleibt der Bildschirm in der Wiedergabeansicht an
  (Einstellungen → „Bildschirm aktiv halten“, standardmäßig an).
- Die Wiedergabe nutzt ausschließlich lokale Dateien – kein Netzwerkzugriff, keine Anmeldung.

## Tests

```bash
flutter test
```

```bash
flutter analyze
```

```bash
dart format --output=none --set-exit-if-changed lib test
```

Abgedeckt (82 Tests):

| Bereich | Datei |
|---|---|
| CHAPEL-API-Antworten, Login/Cookie, 401/403, Logout, ETag/304, Download-Fortschritt, Abbruch, Verbindungsabbruch, `ServerAddress`, `Set-Cookie` | `test/api/chapel_api_client_test.dart` |
| Manifest-Parsing, leere Schritte, Formatversion, Pfad- und Prüfsummenvalidierung, Tempo | `test/packages/manifest_test.dart` |
| Sichere ZIP-Extraktion: Path Traversal, Duplikate, Verschlüsselung, ZIP64, Abschneiden, Offsets, CRC, Zip-Bombe | `test/packages/safe_zip_reader_test.dart` |
| Installation, SHA-256-Fehler, atomare Updates, Deduplizierung, Löschen mit geteilten Dateien, Abbruch, Wiederherstellung | `test/packages/package_installer_test.dart` |
| Fortschritt speichern/laden, Reset bei Versionswechsel, 24-h-Ablauf | `test/playback/progress_store_test.dart` |
| Playback-State-Machine: Auto-Stopp, kein Autoplay, Nächster/Vorheriger, leere Schritte, Unterbrechung, Fehler, Tempo | `test/playback/player_controller_test.dart` |
| Widget-Tests: Empty State, Wiedergabeansicht mit Titelende | `test/ui/player_screen_test.dart` |
| **Integration**: Anmeldung am simulierten CHAPEL-Server → Download → Validierung → Netzwerk aus → Öffnen → Abspielen → Stopp am Titelende → nächster Titel nur per Aktion; fehlgeschlagene/abgebrochene Updates; abgelaufene Sitzung | `test/integration/offline_flow_test.dart` |

Der simulierte CHAPEL-Server (`test/support/fake_chapel_server.dart`) ist ein echter lokaler
HTTP-Server mit CHAPELs Statuscodes, Fehlerformat und `nuxt-session`-Cookie; die Test-ZIPs werden
byte-genau wie `createPackageZip` erzeugt. Im Integrationstest wird nach dem Download jeder
HTTP-Verbindungsversuch über `HttpOverrides` blockiert und gezählt.

Die native Audioausgabe (`JustAudioEngine`) wird in den Tests durch eine Fake-Engine ersetzt; sie ist
nur auf einem Gerät/Simulator prüfbar.

## Continuous Integration

`.github/workflows/ci.yml` läuft bei Pushes auf `main`, bei Pull Requests und manuell:

1. **check** (Ubuntu): `dart format`-Prüfung, `flutter analyze`, `flutter test`
2. **android** (Ubuntu): `flutter build apk --release` → Artefakt `chakotay-android-apk`
3. **ios** (macOS): `flutter build ios --release --no-codesign` → Artefakt `chakotay-ios-unsigned`

Die Artefakte sind im jeweiligen Workflow-Lauf unter *Artifacts* herunterladbar. Es werden keine
Secrets benötigt oder gespeichert; signierte Store-Builds sind bewusst nicht Teil der CI.

## Design

Gestaltet nach dem [`apple-design`-Skill](https://skills.sh/dickwu/apple-design-skill)
(Apple Human Interface Guidelines, installiert mit `npx skills add dickwu/apple-design-skill`;
Version siehe `skills-lock.json`):

- **Purpose/Simplicity**: Die Wiedergabe ist auf Ablauf + zwei große Primäraktionen (72 pt hoch)
  reduziert; kein Scrubbing, damit nichts versehentlich verstellt wird.
- **Tokens** (`lib/ui/theme.dart`): CHAPEL-Grün, für Text kontrastgeprüft – Akzent `#007F45` auf
  Weiß 5,4:1, `#2BD98A` auf `#0E1311` 10,1:1; Liturgie-Grau `#5B6B64` 5,6:1; Warnung `#9A5B00` 5,3:1.
- **Typografie**: Systemschrift (SF auf iOS, Roboto auf Android), Fließtext 17 pt, nichts unter 13 pt
  außer den Tab-Beschriftungen (12 pt, wie System-Tab-Bars); alles skaliert mit der Systemschriftgröße.
- **Touch-Ziele** ≥ 44 pt (Listen ≥ 52 pt, Schritte ≥ 72 pt).
- **Status nie nur über Farbe**: jedes Status-Badge hat Symbol und Text; Screenreader erhalten
  zusammengefasste Beschriftungen und Live-Regionen für Statuswechsel.
- **Plattformnähe**: Tab-Leiste bzw. Navigation Rail, große Titel, gruppierte Einstellungslisten,
  Cupertino-Seitenübergänge und -Dialoge auf iOS, Material-Verhalten auf Android.
- **Bewegung**: nur kurze Übergänge (≤ 280 ms) und automatisches Scrollen zum aktuellen Schritt;
  „Bewegung reduzieren“ wird respektiert.
- **Signatur**: das „Kalenderblatt“ – eine Datumskachel, die jeden Gottesdienst wie im Kirchenkalender
  verortet; das App-Icon zeigt ein gotisches Kirchenfenster mit Note.

## Sicherheit

- Session-Cookie nur in Keychain (`first_unlock_this_device`) bzw. Keystore-gestützter
  verschlüsselter Ablage; nie in Logs, Einstellungen oder Dateien. Passwörter werden nicht gespeichert.
- HTTPS als Standard; HTTP nur nach ausdrücklicher Bestätigung; keine Abschaltung der
  Zertifikatsprüfung; Android vertraut nur System-Zertifikaten.
- Redirects werden nicht automatisch verfolgt (Cookie kann nicht an fremde Hosts gelangen).
- Pakete werden vollständig validiert, bevor sie verfügbar werden (siehe oben).

## Bekannte Einschränkungen

- **iOS-Build lokal nicht verifiziert**: Die Entwicklung erfolgte unter Windows ohne Xcode. Der
  iOS-Build wird in GitHub Actions (`macos-latest`, ohne Signierung) geprüft; für Geräte- und
  Store-Builds sind ein Apple-Developer-Team, Signing und Provisioning nötig (siehe oben).
- **Native Audioausgabe nur manuell testbar**: Tonhöhenerhaltendes Tempo, Unterbrechungen und
  Hintergrundwiedergabe hängen von ExoPlayer/AVPlayer ab und sind nicht Teil der automatisierten Tests.
- **Formate**: CHAPEL erlaubt neben MP3 auch WAV, FLAC und OGG. MP3/WAV laufen überall; FLAC ab
  iOS 11; **OGG/Vorbis wird von iOS (AVPlayer) nicht unterstützt** und schlägt dort mit einer
  verständlichen Meldung fehl.
- **Kein Fortsetzen abgebrochener Downloads**: Ein abgebrochener Download beginnt neu (CHAPEL bietet
  für den ZIP-Endpunkt keine `Range`-Anfragen). Die Einzeldatei-Aktualisierung über
  `/api/tracks/:id/stream` ist vorbereitet (`audio.url` wird gespeichert), aber nicht aktiv, da der
  ZIP-Weg atomar und einfacher zu prüfen ist.
- **Freier Speicher** wird nicht vorab ermittelt (keine plattformübergreifende API in `dart:io`);
  ein voller Speicher wird beim Schreiben erkannt (`ENOSPC`) und verständlich gemeldet, das alte Paket
  bleibt erhalten.
- **Android-Hintergrundwiedergabe** ohne Foreground-Service: Ein einzelner Titel läuft bei gesperrtem
  Bildschirm weiter; sehr aggressive Energiesparmodi einzelner Hersteller können den Prozess dennoch
  beenden. Daher ist „Bildschirm aktiv halten“ standardmäßig eingeschaltet. Bewusst gibt es keine
  Sperrbildschirm-/Mediensteuerung, damit niemand versehentlich über Kopfhörertasten Titel startet.
- **Fortschritt verfällt nach 24 Stunden** – identisch zu CHAPEL.
- Die App ist auf Deutsch lokalisiert.

## Lizenz

[GNU Affero General Public License v3.0 oder später](LICENSE) — © Jannis Rösner.
CHAKOTAY enthält keinen Quellcode aus CHAPEL; es implementiert dessen dokumentiertes Paketformat und
die API eigenständig und steht – wie CHAPEL – unter der AGPL-3.0. Lizenzen der verwendeten Bibliotheken
sind in der App unter *Einstellungen → Lizenzen* einsehbar.
