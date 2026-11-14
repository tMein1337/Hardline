# Hardline — Hinweise für Claude Code

Hardline ist ein Matrix-Desktop-Client in Flutter. Zielplattform: **Windows**.
Shell auf diesem Rechner ist PowerShell.

## Umgebung

Flutter und Cargo (für die nativen Plugins) liegen nicht im globalen PATH. Vor
Flutter-Befehlen in PowerShell:

```powershell
$env:Path = "$env:USERPROFILE\.cargo\bin;C:\Users\Mein1337\Flutter\flutter\flutter\bin;$env:Path"
```

## Prüfen — nach jeder Code-Änderung ausführen

```powershell
flutter analyze
flutter test                                       # Unit- und Widget-Tests (test/)
flutter test integration_test -d windows           # echte Windows-App-Tests (integration_test/)
dart format --output=none --set-exit-if-changed lib test integration_test
```

Bei Fehlern: Ursache beheben und erneut ausführen, bis alles grün ist. Nicht
erst fragen, ob getestet werden soll.

## Integrationstests (`integration_test/`)

- Sie öffnen ein **echtes Fenster** und klicken/tippen dort. Während des Laufs
  nicht den Rechner sperren und das Fenster nicht verdecken.
- Sie dürfen **nie** die echten Nutzerdaten anfassen (`%APPDATA%`, echter
  Account, echte Datenbank). Wie in `test/`: `SharedPreferences.setMockInitialValues`,
  temporäre Verzeichnisse und Fake-Controller statt eines echten Homeservers.
- Es gibt genau **eine** Datei mit der Endung `_test.dart`:
  `integration_test/all_test.dart`. Sie ruft alle Suiten auf. Grund: auf einem
  Desktop-Gerät startet `flutter test` die App pro Testdatei neu, und der zweite
  Start schlägt immer fehl („The log reader stopped unexpectedly“) — auch bei
  zwei Dateien mit je einem leeren Test.
- Eine neue Suite ist deshalb eine Datei `integration_test/<name>_flow.dart`
  mit eigenem `main()`, die in `all_test.dart` eingetragen wird. Vorlage:
  `integration_test/login_flow.dart`. Einzeln ausführen geht weiterhin:
  `flutter test integration_test/<name>_flow.dart -d windows`.
- Die Suiten teilen sich dadurch einen Prozess. Was ein Test vom
  Betriebssystem nimmt (registrierte Tastenkürzel, Fenster), gibt er vor dem
  Ende wieder zurück.
- Hilfen liegen in `integration_test/support/`: Fakes (`fakes.dart`) und die
  Win32-Aufrufe, mit denen ein Test Windows selbst befragt statt die App
  (`win32.dart`).
- Widgets, die ein Test ansteuern muss, bekommen einen stabilen `Key`
  (z. B. `Key('login_submit')`). Bisher gibt es fast keine; bei Bedarf ergänzen.

## Live ausprobieren

`flutter run -d windows` startet die App. Das Fenster kann Claude Code nicht
selbst bedienen; für Klick-Abläufe deshalb einen Integrationstest schreiben.
Konsolenausgabe und Fehler aus dem Lauf auswerten.

## Konventionen

- Jede Dart-Datei beginnt mit dem SPDX-Header (siehe vorhandene Dateien).
- Lizenz: AGPL-3.0-or-later. Neue Abhängigkeiten mit `CONTRIBUTING.md`,
  `THIRD_PARTY_NOTICES.md` und `NIX-PACKAGING.md` abgleichen.
- Der Plan und offene Punkte stehen in `TODOs.md`.
