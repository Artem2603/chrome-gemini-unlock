# Chrome Gemini Unlock

[![test](https://github.com/artem2603/chrome-gemini-unlock/actions/workflows/test.yml/badge.svg)](https://github.com/artem2603/chrome-gemini-unlock/actions/workflows/test.yml)

[English](README.md) · [Русский](README.ru.md) · [Français](README.fr.md) · **Deutsch**

Ein Windows-Skript, das in Google Chrome die Gemini-Seitenleiste (interner Name „Glic“) und optional ihre Agent-Funktionen aktiviert, wenn Chrome sie wegen der Profilsprache oder der Region ausblendet.

> Inoffizielles Projekt, nicht mit Google verbunden. Die Flags sind experimentell: Google kann sie in jeder Chrome-Version umbenennen oder entfernen und den Zugang trotzdem je nach Konto einschränken. Nutzung auf eigenes Risiko.

## Was das Skript macht

0. Sucht Google Chrome: in der Registrierung, unter laufenden Programmen und in den Standardordnern. Ist Chrome nicht installiert oder wurde es in diesem Windows-Konto noch nie gestartet, bricht das Skript ab, ohne etwas zu ändern.
1. Schließt Google Chrome. Läuft Chrome, fragt das Skript vorher nach (`-Force` überspringt die Frage). In einer nicht interaktiven Sitzung, in der es nicht nachfragen kann, bricht es ab, ohne etwas zu ändern, und bittet Sie, es mit `-Force` zu starten. Dann wird jedes Fenster gebeten, sich zu schließen, als hätten Sie es selbst geschlossen; was danach noch läuft, wird einige Sekunden später beendet. In diesem Fall bietet Chrome beim nächsten Start eventuell an, die Seiten wiederherzustellen: Klicken Sie auf **Wiederherstellen** (Restore). Text in nicht abgeschickten Formularen geht in jedem Fall verloren.
2. Aktiviert 5 Glic-Flags in Chromes Datei `Local State`, für die Seitenleiste, ihre Schaltfläche in der Symbolleiste und ihren Eintrag im Kontextmenü:
   `glic`, `glic-toolbar-height-side-panel`, `glic-horizontal-tab-toolbar-button`, `glic-toolbar-button-location`, `glic-context-menu-below-search`.

   Die 6 Agent-Flags werden nur mit `-Agent` aktiviert; ein Lauf ohne `-Agent` setzt sie auf Default zurück:
   `glic-actor`, `enable-browser-actuator-for-glic-experimental-triggering`, `glic-background-actuation`, `glic-actor-autofill`, `glic-actor-cursor`, `glic-actor-script-tools`.

   Ist das installierte Chrome neuer als die Version, nach der ein aktiviertes Flag ausläuft, warnt das Skript, dass Chrome dieses Flag eventuell ignoriert.
3. Stellt die Chrome-Oberfläche auf Englisch (en-US) um und setzt die Sprachen aller Profile auf `en-US,en`.
4. Lässt Chrome die USA als Region für seine Experimente verwenden:
   - fügt `--variations-override-country=us --lang=en-US` zu den Chrome-Verknüpfungen hinzu: Desktop, Startmenü, Taskleiste und Verknüpfungen für alle Benutzer (dafür sind Administratorrechte nötig, Windows fragt per UAC). Ein bereits vorhandenes `--lang=` oder `--variations-override-country=` in einer Verknüpfung wird ersetzt;
   - fügt dieselben Argumente dem Autostart-Eintrag von Chrome hinzu, falls vorhanden;
   - fügt sie dem Link-Handler hinzu, damit auch ein Chrome, das über einen Link aus einem anderen Programm geöffnet wird, sie bekommt;
   - speichert das Land in `Local State` (`variations_permanent_overridden_country`).
5. Startet Chrome neu und prüft, dass es mit dem Override läuft. Läuft das Skript mit Administratorrechten, startet es Chrome nicht, weil Chrome diese Rechte sonst ebenfalls hätte: Starten Sie Chrome dann über eine Verknüpfung.

Vor jeder Änderung sichert das Skript den ursprünglichen Zustand in `%LOCALAPPDATA%\chrome-gemini-unlock\backup`: Dateien werden dorthin kopiert, Registrierungswerte in `manifest.txt` notiert. Spätere Läufe überschreiben diese Sicherung nie. `-Restore` macht die Änderungen damit rückgängig.

## Voraussetzungen

- Windows 10 oder 11 mit Windows PowerShell 5.1 (vorinstalliert). Aus PowerShell 7 aufgerufen, startet sich das Skript selbst in Windows PowerShell 5.1 neu.
- Google Chrome, Stable-Kanal, mindestens einmal in Ihrem Windows-Konto gestartet. Beta, Dev und Canary werden nicht unterstützt.

## Verwendung

1. Repository herunterladen: **Code → Download ZIP**, dann das Archiv entpacken.
2. Doppelklick auf `chrome-gemini-unlock.bat`.
3. Läuft Chrome, fragt das Skript, ob es geschlossen werden soll: **J** eingeben und die Eingabetaste drücken. Jede andere Antwort bricht ab, ohne etwas zu ändern.
4. Wenn Windows nach Administratorrechten fragt, bestätigen. Sie werden nur für die Verknüpfungen aller Benutzer gebraucht; wenn Sie ablehnen, funktioniert alles andere trotzdem.
5. Chrome startet neu. In der Symbolleiste sollte die Gemini-Schaltfläche erscheinen.

Optionen lassen sich angeben, wenn das Skript aus einer Eingabeaufforderung im entpackten Ordner gestartet wird, zum Beispiel:

```bat
chrome-gemini-unlock.bat -NoAdmin
```

| Option | Bedeutung |
|---|---|
| `-Country us` | Region für Experimente, zwei Buchstaben. Standard: `us`. |
| `-Agent` | Zusätzlich die Agent-Funktionen aktivieren (siehe „Gut zu wissen“). Ohne diese Option werden die Agent-Flags auf Default zurückgesetzt. |
| `-Force` | Chrome ohne Nachfrage schließen. Nötig in einer nicht interaktiven Sitzung, in der das Skript nicht nachfragen kann. |
| `-Restore` | Die Änderungen mithilfe der Sicherung rückgängig machen (siehe „Rückgängig machen“). |
| `-NoAdmin` | Niemals nach Administratorrechten fragen; Verknüpfungen für alle Benutzer bleiben unverändert. |
| `-NoLaunch` | Chrome am Ende nicht starten. |

Das Skript kann gefahrlos erneut ausgeführt werden: Bereits eingerichtete Verknüpfungen und Link-Handler werden als „bereits eingerichtet“ gemeldet, ein Autostart-Eintrag, der die Argumente schon enthält, bleibt unverändert, und die Sicherung behält den Zustand vor dem ersten Lauf. Trotzdem schließt jeder Lauf Chrome, startet es neu und schreibt die Flags und Spracheinstellungen erneut.

## Gut zu wissen

- **Starten Sie Chrome über die Verknüpfungen.** Wenn ein Programm `chrome.exe` direkt startet, läuft dieses Chrome ohne den Befehlszeilen-Override. Das in `Local State` gespeicherte Land gilt dann nur für einen Teil der Experimente.
- **Override prüfen:** `chrome://version` öffnen. Die Zeile „Command Line“ muss `--variations-override-country=us` enthalten.
- **Autostart.** Chrome verwaltet seinen Autostart-Eintrag selbst und kann ihn ohne den Override neu anlegen. Wenn Gemini nach einem Neustart verschwindet, schalten Sie „Continue running background apps when Google Chrome is closed“ in `chrome://settings/system` aus oder führen Sie das Skript erneut aus.
- **Chrome-Updates** können die Verknüpfungen für alle Benutzer neu anlegen. Wenn Gemini nach einem Update verschwindet, führen Sie das Skript erneut aus.
- **Gemeinsam genutzter PC.** Die Verknüpfungen für alle Benutzer gelten für jedes Windows-Konto auf dem PC. Um nur Ihre eigenen Verknüpfungen zu ändern, starten Sie das Skript mit `-NoAdmin`. Chrome in den Windows-Sitzungen anderer Benutzer wird nie geschlossen; ein Chrome, das auf Ihrem eigenen Desktop mit „Als anderer Benutzer ausführen“ gestartet wurde, wird wie Ihr eigenes geschlossen.
- **Sprachen und Synchronisierung.** Die Profile bekommen die Sprachen `en-US,en`, Websites bevorzugen daher Englisch. Bei aktivierter Chrome-Synchronisierung landet die Sprachliste auch in Ihrem Chrome auf anderen Computern.
- **Link-Handler.** Das Skript legt eine benutzereigene Kopie von Chromes Link-Registrierung in `HKCU\Software\Classes` an (`ChromeHTML`, `ChromePDF`). Wenn Sie Chrome deinstallieren, löschen Sie diese Schlüssel (siehe „Rückgängig machen“).
- **Agent-Funktionen** sind standardmäßig aus. Mit `-Agent` kann Gemini in Ihrem Browser, in dem Sie bei Ihren Konten angemeldet sind, für Sie klicken, tippen und Formulare ausfüllen. Eine Webseite kann in ihrem Inhalt Anweisungen für die KI verstecken (Prompt Injection) und Gemini so gegen Sie handeln lassen. Aktivieren Sie sie nur, wenn Sie dieses Risiko in Kauf nehmen, und behalten Sie im Blick, was Gemini tut.
- **Flags laufen aus.** Laut den Flag-Metadaten von Chromium laufen die meisten dieser Flags nach Chrome 160 aus; `glic-actor` nach Chrome 172, `enable-browser-actuator-for-glic-experimental-triggering` und `glic-actor-script-tools` nach Chrome 170. Danach ignoriert Chrome ein Flag, sofern Google es nicht verlängert. Das Skript warnt, wenn das installierte Chrome neuer ist als die Version, nach der ein Flag ausläuft. `glic-actor-cursor` war in Chrome 155 bereits abgelaufen und wurde erst ab Chrome 156 bis 160 verlängert: Mit Chrome 155 warnt das Skript und nennt `chrome://flags/#temporary-unexpire-flags-m154`, das es vorerst wieder einschaltet.
- **Administrator-Kopie.** Für die gemeinsamen Verknüpfungen schreibt das Skript eine Kopie von sich selbst in den Sicherungsordner und führt sie mit Administratorrechten aus. Die Kopie wird vor dem Start per SHA-256 geprüft: Hat ein Programm sie verändert, während die Windows-Abfrage offen war, wird sie nicht ausgeführt, und die gemeinsamen Verknüpfungen bleiben unverändert. Vor jedem Schreibvorgang im Sicherungsordner prüft das Skript, ob dort eine Verzweigung (Junction) oder symbolische Verknüpfung liegt, und schreibt nicht darüber.

## Rückgängig machen

In einer Eingabeaufforderung im entpackten Ordner ausführen:

```bat
chrome-gemini-unlock.bat -Restore
```

Wie bei einem normalen Lauf fragt das Skript vor dem Schließen von Chrome nach und startet Chrome am Ende neu. Mithilfe der Sicherung stellt es nur das wieder her, was es geändert hat:

- die Glic-Flags (andere Flags bleiben, wie sie sind);
- die Oberflächensprache und die Sprachen der Profile, die das Skript geändert hat;
- das gespeicherte Land;
- die Argumente der Chrome-Verknüpfungen (Symbol, Anheftung und Name bleiben, wie sie jetzt sind);
- den Autostart-Eintrag, falls Chrome ihn noch hat;
- den Link-Handler: Die benutzereigene Kopie wird gelöscht, oder der Schlüssel, der vor dem Skript existierte, wird wieder importiert.

Alles andere, was Chrome seit dem ersten Lauf gespeichert hat, etwa andere Einstellungen oder neue Profile, bleibt erhalten. Gemeinsame Verknüpfungen erfordern erneut Administratorrechte: Bestätigen Sie die Windows-Abfrage, sonst bleiben sie unverändert.

**Manuell rückgängig machen** (falls sich das Skript nicht ausführen lässt):

1. In Chrome: `chrome://flags` → **Reset all** (oder die `glic`-Flags und `enable-browser-actuator-for-glic-experimental-triggering` einzeln auf Default setzen), dann in `chrome://settings/languages` Ihre Sprachen und die Anzeigesprache wählen.
2. `--variations-override-country=us --lang=en-US` aus dem Feld „Ziel“ in den Eigenschaften jeder Chrome-Verknüpfung entfernen. Hatte eine Verknüpfung vorher ein eigenes `--lang=`, dieses wieder eintragen; die ursprüngliche Verknüpfung liegt in der Sicherung (`shortcuts\<Code>\<Name>.lnk`).
3. `%LOCALAPPDATA%\chrome-gemini-unlock\backup\manifest.txt` öffnen und die Registrierungsschlüssel löschen, die dort als `created` aufgeführt sind:
   ```bat
   reg delete "HKCU\Software\Classes\ChromeHTML" /f
   reg delete "HKCU\Software\Classes\ChromePDF" /f
   ```
   Enthält die Sicherung `registry\handler-*.reg`, doppelklicken Sie stattdessen darauf: Die Datei stellt einen Schlüssel wieder her, der vor dem Skript existierte.
4. Enthält das Manifest eine Zeile `...\Run  GoogleChromeAutoLaunch_<Code> = ...`, löschen Sie diesen Autostart-Wert; Chrome legt ihn bei Bedarf selbst wieder an:
   ```bat
   reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v GoogleChromeAutoLaunch_<Code> /f
   ```
5. Chrome vollständig schließen: alle Fenster schließen und, falls im Infobereich ein Chrome-Symbol ist, mit der rechten Maustaste darauf klicken und **Exit** (Beenden) wählen. Im Task-Manager (Registerkarte Details) prüfen, dass kein `chrome.exe` mehr läuft, sonst überschreibt Chrome die Änderung wieder mit seinen Einstellungen. Dann das gespeicherte Land mit PowerShell aus `Local State` entfernen:
   ```powershell
   $f = "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"
   [IO.File]::WriteAllText($f, ([IO.File]::ReadAllText($f) -replace ',"variations_permanent_overridden_country":"[a-z]*"', ''))
   ```

## Dateien

| Datei | Zweck |
|---|---|
| `chrome-gemini-unlock.bat` | Starter für Doppelklick: führt das PowerShell-Skript aus und reicht Optionen durch. |
| `chrome-gemini-unlock.ps1` | Das eigentliche Skript. Meldungen auf Englisch, Russisch, Französisch und Deutsch, je nach Windows-Sprache. |
| `tests/` | Unit-Tests, eine Prüfung der Flags in einem echten Chrome und ein End-to-End-Test unter Windows. |
| `.github/workflows/test.yml` | Führt die Tests auf GitHub Actions aus. |

Getestet unter Windows 11 mit Chrome 154. `tests/chrome-flags.ps1` startet ein echtes Chrome und prüft, dass es jedes Flag anwendet, außer denen, die laut Ablauftabelle des Skripts in dieser Version abgelaufen sind (mit Chrome 155: alle außer `glic-actor-cursor`).

## Lizenz

[MIT](LICENSE)
