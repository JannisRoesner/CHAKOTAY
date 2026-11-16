# CHAKOTAY

**Cross-platform Hymn Audio Kiosk for Offline Track Access and PlaYback**

Offline-Wiedergabe-App für Android und iOS zu [CHAPEL](https://github.com/JannisRoesner/CHAPEL).
Gottesdienste werden einmal vom CHAPEL-Server geladen und danach ohne Internet abgespielt –
mit dem Bedienkonzept von CHAPEL: *Play → Stopp nach jedem Titel → nächster Titel per Knopf*.

## Funktionen

- Offline-Bibliothek aller geladenen Gottesdienste, inklusive Update-Hinweis
- Anmeldung am CHAPEL-Server, Auswahl und Download mehrerer Gottesdienste
- Geprüfte Pakete (SHA-256), atomare Updates, gemeinsame Audiodateien werden nur einmal gespeichert
- Wiedergabe mit automatischem Stopp am Titelende, Tempo laut CHAPEL (tonhöhenerhaltend),
  übersprungenen leeren Schritten und gespeichertem Fortschritt
- Pause bei Anrufen oder anderen Unterbrechungen, ohne automatisches Fortsetzen
- Hell-/Dunkelmodus und fünf Farbschemata

## Installation

Die fertige Android-APK liegt unter [Releases](https://github.com/JannisRoesner/CHAKOTAY/releases).

## Entwicklung

Voraussetzung: Flutter 3.41 (stable), für iOS zusätzlich macOS mit Xcode und CocoaPods.

```bash
flutter pub get
flutter run
```

```bash
flutter test
```

Release-Builds:

```bash
flutter build apk --release
flutter build ipa --release
```

Für eine eigene Android-Signatur `android/key.properties` mit `storeFile`, `storePassword`,
`keyAlias` und `keyPassword` anlegen (nicht committen). Ohne diese Datei wird mit dem
Debug-Schlüssel signiert. Für iOS in Xcode beim Target *Runner* ein Signing-Team wählen.

## Verwendung

1. Tab **Laden**: Adresse des CHAPEL-Servers eingeben und anmelden.
2. Gottesdienste auswählen und laden.
3. Tab **Gottesdienste**: Gottesdienst öffnen und mit **Abspielen** bzw. **Nächster** bedienen.

## Lizenz

[GNU AGPL v3.0](LICENSE)
