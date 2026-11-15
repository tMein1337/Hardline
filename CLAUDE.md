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
# Echte Windows-App-Tests (integration_test/). Alle Suiten im Debug-Build,
# danach die Overlay-Suite noch einmal mit --profile: das ist ein AOT-Build wie
# das Release, und der Overlay-Fehler aus TODO 13 trat nur dort auf.
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/all_test.dart -d windows
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/overlay_window_flow.dart -d windows --profile
dart format --output=none --set-exit-if-changed lib test integration_test test_driver
```

Bei Fehlern: Ursache beheben und erneut ausführen, bis alles grün ist. Nicht
erst fragen, ob getestet werden soll.

## Integrationstests (`integration_test/`)

- Sie öffnen ein **echtes Fenster**, drücken **echte Tasten**, ziehen die
  **echte Maus** und legen das Overlay über den ganzen Hauptmonitor. Während
  des Laufs nicht den Rechner sperren und das Fenster nicht verdecken.
- **Nicht starten, wenn am Rechner gerade jemand etwas anderes tut** — vor
  allem kein Spiel im Vordergrund. Die Tastendrücke landen sonst dort. Vorher
  prüfen, welches Fenster vorn ist; die Suiten brechen zur Sicherheit selbst
  ab, wenn es nicht ihr eigenes ist (`requireOwnDesktop`).
- Sie dürfen **nie** die echten Nutzerdaten anfassen (`%APPDATA%`, echter
  Account, echte Datenbank). Wie in `test/`: `SharedPreferences.setMockInitialValues`,
  temporäre Verzeichnisse und Fake-Controller statt eines echten Homeservers.
- **`flutter drive`, nicht `flutter test`.** `flutter test` übersetzt nicht die
  Testdatei als Programm, sondern einen generierten Bootstrap, der sie
  importiert. Die zweite Flutter-Engine des Overlays sucht `overlayMain` aber
  in der Bibliothek, die `main` enthält, findet dort nichts und startet nie —
  übrig bleibt ein schwarzes Fenster über dem Monitor.
- Es gibt genau **einen** Einstieg, `integration_test/all_test.dart`, der alle
  Suiten aufruft. Eine App pro Lauf: ein Build, ein Fenster. (`flutter test`
  könnte auf einem Desktop-Gerät ohnehin keine zweite Testdatei starten —
  „The log reader stopped unexpectedly“.)
- Eine neue Suite ist eine Datei `integration_test/<name>_flow.dart` mit
  eigenem `main()`, die in `all_test.dart` eingetragen wird. Vorlage:
  `integration_test/login_flow.dart`. Einzeln ausführen: dieselbe
  `flutter drive`-Zeile mit `--target=integration_test/<name>_flow.dart`.
- **`--profile` nur für die Overlay-Suite.** Im Profile-Build funktionieren
  `tester.enterText` und `tester.sendKeyDownEvent` nicht (der Text kommt
  leer an), deshalb scheitern dort Login- und Hotkey-Suite, ohne dass an der App
  etwas falsch wäre. Die Overlay-Suite benutzt beides nicht.
- Die Overlay-Suite steht in `all_test.dart` an erster Stelle und muss dort
  bleiben: ihr erster Test prüft das allererste Einblenden im Prozess.
- Die Suiten teilen sich einen Prozess. Was ein Test vom Betriebssystem nimmt
  (registrierte Tastenkürzel, Fenster), gibt er vor dem Ende wieder zurück.
- **Zwei echte Nutzer:** `integration_test/two_users_flow.dart` läuft gegen einen
  echten Homeserver mit zwei Testkonten und nur, wenn sie per
  `--dart-define=HARDLINE_LIVE_ACCOUNTS=.claude/test-accounts.json` angegeben
  werden (die Datei liegt im git-ignorierten `.claude/`). Ohne die Angabe wird
  sie übersprungen. Sie räumt hinterher auf: Raum verlassen, Sitzungen abgemeldet.
- Bildschirmfotos zum Ansehen: `--dart-define=HARDLINE_TEST_SHOTS=<Ordner>`.
  Ohne die Angabe schreibt kein Test etwas auf die Platte.
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
