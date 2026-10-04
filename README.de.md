# Chrome Gemini Unlock

[English](README.md) · [Русский](README.ru.md) · [Français](README.fr.md) · **Deutsch**

Ein Windows-Skript, das in Google Chrome die Gemini-Seitenleiste (interner Name „Glic“) samt ihren Agent-Funktionen aktiviert, wenn Chrome sie wegen der Profilsprache oder der Region ausblendet.

> Inoffizielles Projekt, nicht mit Google verbunden. Die Flags sind experimentell: Google kann sie in jeder Chrome-Version umbenennen oder entfernen und den Zugang trotzdem je nach Konto einschränken. Nutzung auf eigenes Risiko.

## Was das Skript macht

0. Sucht Google Chrome: in der Registrierung, unter laufenden Programmen und in den Standardordnern. Ist Chrome nicht installiert oder wurde es in diesem Windows-Konto noch nie gestartet, bricht das Skript ab, ohne etwas zu ändern.
1. Schließt Google Chrome. Zuerst wird jedes Fenster gebeten, sich zu schließen, als hätten Sie es selbst geschlossen; was danach noch läuft, wird einige Sekunden später beendet. In diesem Fall bietet Chrome beim nächsten Start eventuell an, die Seiten wiederherzustellen: Klicken Sie auf **Wiederherstellen** (Restore). Text in nicht abgeschickten Formularen geht in jedem Fall verloren.
2. Aktiviert 11 Glic-Flags in Chromes Datei `Local State`:
   `glic`, `glic-actor`, `enable-browser-actuator-for-glic-experimental-triggering`, `glic-background-actuation`, `glic-actor-autofill`, `glic-actor-cursor`, `glic-actor-script-tools`, `glic-toolbar-height-side-panel`, `glic-horizontal-tab-toolbar-button`, `glic-toolbar-button-location`, `glic-context-menu-below-search`.
3. Stellt die Chrome-Oberfläche auf Englisch (en-US) um und setzt die Sprachen aller Profile auf `en-US,en`.
4. Lässt Chrome die USA als Region für seine Experimente verwenden:
   - fügt `--variations-override-country=us --lang=en-US` zu den Chrome-Verknüpfungen hinzu: Desktop, Startmenü, Taskleiste und Verknüpfungen für alle Benutzer (dafür sind Administratorrechte nötig, Windows fragt per UAC). Ein bereits vorhandenes `--lang=` oder `--variations-override-country=` in einer Verknüpfung wird ersetzt;
   - fügt dieselben Argumente dem Autostart-Eintrag von Chrome hinzu, falls vorhanden;
   - fügt sie dem Link-Handler hinzu, damit auch ein Chrome, das über einen Link aus einem anderen Programm geöffnet wird, sie bekommt;
   - speichert das Land in `Local State` (`variations_permanent_overridden_country`).
5. Startet Chrome neu und prüft, dass es mit dem Override läuft.

Vor jeder Änderung sichert das Skript den ursprünglichen Zustand in `%LOCALAPPDATA%\chrome-gemini-unlock\backup`: Dateien werden dorthin kopiert, Registrierungswerte in `manifest.txt` notiert. Spätere Läufe überschreiben diese Sicherung nie.

## Voraussetzungen

- Windows 10 oder 11 mit Windows PowerShell 5.1 (vorinstalliert).
- Google Chrome, Stable-Kanal, mindestens einmal in Ihrem Windows-Konto gestartet. Beta, Dev und Canary werden nicht unterstützt.

## Verwendung

1. Repository herunterladen: **Code → Download ZIP**, dann das Archiv entpacken.
2. Doppelklick auf `chrome-gemini-unlock.bat`.
3. Wenn Windows nach Administratorrechten fragt, bestätigen. Sie werden nur für die Verknüpfungen aller Benutzer gebraucht; wenn Sie ablehnen, funktioniert alles andere trotzdem.
4. Chrome startet neu. In der Symbolleiste sollte die Gemini-Schaltfläche erscheinen.

Optionen lassen sich angeben, wenn das Skript aus einer Eingabeaufforderung im entpackten Ordner gestartet wird, zum Beispiel:

```bat
chrome-gemini-unlock.bat -NoAdmin
```

| Option | Bedeutung |
|---|---|
| `-Country us` | Region für Experimente, zwei Buchstaben. Standard: `us`. |
| `-NoAdmin` | Niemals nach Administratorrechten fragen; Verknüpfungen für alle Benutzer bleiben unverändert. |
| `-NoLaunch` | Chrome am Ende nicht starten. |

Das Skript kann gefahrlos erneut ausgeführt werden: Bereits erledigte Schritte werden als „bereits eingerichtet“ gemeldet, und die Sicherung behält den Zustand vor dem ersten Lauf.

## Gut zu wissen

- **Starten Sie Chrome über die Verknüpfungen.** Wenn ein Programm `chrome.exe` direkt startet, läuft dieses Chrome ohne den Befehlszeilen-Override. Das in `Local State` gespeicherte Land gilt dann nur für einen Teil der Experimente.
- **Override prüfen:** `chrome://version` öffnen. Die Zeile „Command Line“ muss `--variations-override-country=us` enthalten.
- **Autostart.** Chrome verwaltet seinen Autostart-Eintrag selbst und kann ihn ohne den Override neu anlegen. Wenn Gemini nach einem Neustart verschwindet, schalten Sie „Continue running background apps when Google Chrome is closed“ in `chrome://settings/system` aus oder führen Sie das Skript erneut aus.
- **Chrome-Updates** können die Verknüpfungen für alle Benutzer neu anlegen. Wenn Gemini nach einem Update verschwindet, führen Sie das Skript erneut aus.
- **Gemeinsam genutzter PC.** Die Verknüpfungen für alle Benutzer gelten für jedes Windows-Konto auf dem PC. Um nur Ihre eigenen Verknüpfungen zu ändern, starten Sie das Skript mit `-NoAdmin`. Chrome in den Windows-Sitzungen anderer Benutzer wird nie geschlossen; ein Chrome, das auf Ihrem eigenen Desktop mit „Als anderer Benutzer ausführen“ gestartet wurde, wird wie Ihr eigenes geschlossen.
- **Sprachen und Synchronisierung.** Die Profile bekommen die Sprachen `en-US,en`, Websites bevorzugen daher Englisch. Bei aktivierter Chrome-Synchronisierung landet die Sprachliste auch in Ihrem Chrome auf anderen Computern.
- **Link-Handler.** Das Skript legt eine benutzereigene Kopie von Chromes Link-Registrierung in `HKCU\Software\Classes` an (`ChromeHTML`, `ChromePDF`). Wenn Sie Chrome deinstallieren, löschen Sie diese Schlüssel (siehe „Rückgängig machen“).
- **Agent-Funktionen.** Die Flags `glic-actor*` schalten den Modus ein, in dem Gemini auf Webseiten für Sie handeln kann. Behalten Sie im Blick, was es tut.

## Rückgängig machen

**Vollständig**, zurück zum Zustand vor dem ersten Lauf:

1. Chrome vollständig schließen: alle Fenster schließen und, falls im Infobereich ein Chrome-Symbol ist, mit der rechten Maustaste darauf klicken und **Exit** (Beenden) wählen. Im Task-Manager (Registerkarte Details) prüfen, dass kein `chrome.exe` mehr läuft, sonst schreibt Chrome seine Einstellungen über die wiederhergestellten Dateien.
2. `%LOCALAPPDATA%\chrome-gemini-unlock\backup` öffnen. Jede Zeile von `manifest.txt` lautet `Sicherungsdatei  ->  ursprünglicher Ort`.
3. Jede Sicherungsdatei an ihren ursprünglichen Ort zurückkopieren und die dortige Datei ersetzen: `Local State`, `profiles\<Profil>\Preferences`, `shortcuts\<Code>\<Name>.lnk`. Verknüpfungen für alle Benutzer (`C:\Users\Public\Desktop`, `C:\ProgramData\...`) erfordern Administratorrechte.
4. Die Registrierungsschlüssel löschen, die im Manifest als `created` aufgeführt sind:
   ```bat
   reg delete "HKCU\Software\Classes\ChromeHTML" /f
   reg delete "HKCU\Software\Classes\ChromePDF" /f
   ```
   Enthält die Sicherung `registry\handler-*.reg`, doppelklicken Sie stattdessen darauf: Die Datei stellt einen Schlüssel wieder her, der vor dem Skript existierte.
5. Enthält das Manifest eine Zeile `...\Run  GoogleChromeAutoLaunch_<Code> = ...`, löschen Sie diesen Autostart-Wert; Chrome legt ihn bei Bedarf selbst wieder an:
   ```bat
   reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v GoogleChromeAutoLaunch_<Code> /f
   ```

Das Zurückkopieren alter Dateien verwirft auch alles, was Chrome nach dem Skript gespeichert hat, etwa neue Einstellungen oder neue Profile.

**Teilweise**, ohne Dateien zurückzukopieren:

1. In Chrome: `chrome://flags` → **Reset all** (oder die `glic`-Flags einzeln auf Default setzen), dann in `chrome://settings/languages` Ihre Sprachen und die Anzeigesprache wählen.
2. `--variations-override-country=us --lang=en-US` aus dem Feld „Ziel“ in den Eigenschaften jeder Chrome-Verknüpfung entfernen. Hatte eine Verknüpfung vorher ein eigenes `--lang=`, dieses wieder eintragen; die ursprüngliche Verknüpfung liegt in der Sicherung.
3. Die Schritte 4 und 5 der vollständigen Variante ausführen.
4. Chrome vollständig schließen (wie in Schritt 1 der vollständigen Variante) und das gespeicherte Land mit PowerShell aus `Local State` entfernen:
   ```powershell
   $f = "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"
   [IO.File]::WriteAllText($f, ([IO.File]::ReadAllText($f) -replace ',"variations_permanent_overridden_country":"[a-z]*"', ''))
   ```

## Dateien

| Datei | Zweck |
|---|---|
| `chrome-gemini-unlock.bat` | Starter für Doppelklick: führt das PowerShell-Skript aus und reicht Optionen durch. |
| `chrome-gemini-unlock.ps1` | Das eigentliche Skript. Meldungen auf Englisch, Russisch, Französisch und Deutsch, je nach Windows-Sprache. |

Getestet unter Windows 11 mit Chrome 154.

## Lizenz

[MIT](LICENSE)
