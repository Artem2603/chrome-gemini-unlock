# Chrome Gemini Unlock

**English** · [Русский](README.ru.md) · [Français](README.fr.md) · [Deutsch](README.de.md)

A Windows script that turns on the Gemini side panel in Google Chrome (internal name "Glic") together with its agent features, when Chrome hides them because of the profile language or the region.

> Unofficial project, not affiliated with Google. The flags are experimental: Google can rename or remove them in any Chrome version, and can still decide availability by account. Use at your own risk.

## What it does

0. Looks for Google Chrome: in the registry, among running programs and in the standard folders. If Chrome is not installed, or has never been started in this Windows account, the script stops without changing anything.
1. Closes Google Chrome. It first asks every window to close, as if you closed them yourself, and ends whatever is still running a few seconds later. In that case Chrome may offer to restore pages on the next start: click **Restore**. Text typed into unsent forms is lost either way.
2. Enables 11 Glic flags in Chrome's `Local State` file:
   `glic`, `glic-actor`, `enable-browser-actuator-for-glic-experimental-triggering`, `glic-background-actuation`, `glic-actor-autofill`, `glic-actor-cursor`, `glic-actor-script-tools`, `glic-toolbar-height-side-panel`, `glic-horizontal-tab-toolbar-button`, `glic-toolbar-button-location`, `glic-context-menu-below-search`.
3. Switches the Chrome interface to English (en-US) and sets the languages of every profile to `en-US,en`.
4. Makes Chrome use the United States as its region for experiments:
   - adds `--variations-override-country=us --lang=en-US` to Chrome shortcuts: desktop, Start menu, taskbar, and the shortcuts shared by all users (these need administrator rights, Windows asks through UAC). A `--lang=` or `--variations-override-country=` already present in a shortcut is replaced;
   - adds the same arguments to Chrome's autostart entry, if there is one;
   - adds them to the link handler, so Chrome opened by a link from another program also gets them;
   - stores the country in `Local State` (`variations_permanent_overridden_country`).
5. Starts Chrome again and checks that it runs with the override.

Before changing anything, the script saves the original state to `%LOCALAPPDATA%\chrome-gemini-unlock\backup`: files are copied there, registry values are written to `manifest.txt`. Later runs never overwrite this backup.

## Requirements

- Windows 10 or 11 with Windows PowerShell 5.1 (built in).
- Google Chrome, stable channel, started at least once in your Windows account. Beta, Dev and Canary are not supported.

## Usage

1. Download the repository: **Code → Download ZIP**, then extract the archive.
2. Double-click `chrome-gemini-unlock.bat`.
3. If Windows asks for administrator rights, confirm. This is only needed for the shortcuts shared by all users; if you decline, everything else still works.
4. Chrome restarts. The Gemini button should appear in the toolbar.

Options can be added when the script is started from a command prompt in the extracted folder, for example:

```bat
chrome-gemini-unlock.bat -NoAdmin
```

| Option | Meaning |
|---|---|
| `-Country us` | Region for experiments, two letters. Default: `us`. |
| `-NoAdmin` | Never ask for administrator rights; shared shortcuts stay unchanged. |
| `-NoLaunch` | Do not start Chrome at the end. |

Running the script again is safe: steps that are already done are reported as "already set up", and the backup keeps the state from before the first run.

## Good to know

- **Start Chrome from its shortcuts.** If some program runs `chrome.exe` directly, that Chrome starts without the command-line override. The country stored in `Local State` then covers only part of the experiments.
- **Check the override:** open `chrome://version`. The "Command Line" row must contain `--variations-override-country=us`.
- **Autostart.** Chrome manages its own autostart entry and can recreate it without the override. If Gemini disappears after a reboot, turn off "Continue running background apps when Google Chrome is closed" in `chrome://settings/system`, or run the script again.
- **Chrome updates** can recreate the shared shortcuts. If Gemini disappears after an update, run the script again.
- **Shared computer.** The shortcuts shared by all users affect every Windows account on the PC. To change only your own shortcuts, run the script with `-NoAdmin`. Chrome running in other users' Windows sessions is never closed; a Chrome started with "Run as different user" on your own desktop is closed like your own.
- **Languages and sync.** Profiles get the languages `en-US,en`, so websites will prefer English. With Chrome sync turned on, the language list also reaches your Chrome on other computers.
- **Link handler.** The script puts a per-user copy of Chrome's link registration into `HKCU\Software\Classes` (`ChromeHTML`, `ChromePDF`). If you uninstall Chrome, delete these keys (see "Undo").
- **Agent features.** The `glic-actor*` flags turn on the mode in which Gemini can act on web pages for you. Keep an eye on what it does.

## Undo

**Full undo**, back to the state before the first run:

1. Close Chrome completely: close all windows, then, if there is a Chrome icon in the notification area, right-click it and choose **Exit**. Make sure no `chrome.exe` is left in Task Manager (Details tab), otherwise Chrome writes its settings back over the restored files.
2. Open `%LOCALAPPDATA%\chrome-gemini-unlock\backup`. Each line of `manifest.txt` reads `backup file  ->  original location`.
3. Copy every backup file back to its original location, replacing the file there: `Local State`, `profiles\<profile>\Preferences`, `shortcuts\<code>\<name>.lnk`. Shared shortcuts (`C:\Users\Public\Desktop`, `C:\ProgramData\...`) need administrator rights.
4. Delete the registry keys that the manifest lists as `created`:
   ```bat
   reg delete "HKCU\Software\Classes\ChromeHTML" /f
   reg delete "HKCU\Software\Classes\ChromePDF" /f
   ```
   If the backup contains `registry\handler-*.reg`, double-click it instead: it restores a key that existed before the script.
5. If the manifest has a line `...\Run  GoogleChromeAutoLaunch_<code> = ...`, delete that autostart value; Chrome creates it again by itself when it needs it:
   ```bat
   reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v GoogleChromeAutoLaunch_<code> /f
   ```

Copying old files back also discards whatever Chrome saved after the script ran, for example new settings or new profiles.

**Partial undo**, without restoring files:

1. In Chrome: `chrome://flags` → **Reset all** (or set the `glic` flags back to Default one by one), then pick your languages and the display language in `chrome://settings/languages`.
2. Remove `--variations-override-country=us --lang=en-US` from the "Target" field in the properties of each Chrome shortcut. If a shortcut had its own `--lang=` before, put it back; the original shortcut is in the backup.
3. Do steps 4 and 5 of the full undo.
4. Close Chrome completely (as in step 1 of the full undo) and remove the stored country from `Local State` with PowerShell:
   ```powershell
   $f = "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"
   [IO.File]::WriteAllText($f, ([IO.File]::ReadAllText($f) -replace ',"variations_permanent_overridden_country":"[a-z]*"', ''))
   ```

## Files

| File | Purpose |
|---|---|
| `chrome-gemini-unlock.bat` | Launcher for double-click; runs the PowerShell script and passes options through. |
| `chrome-gemini-unlock.ps1` | The script itself. Messages in English, Russian, French and German, chosen by the Windows language. |

Tested on Windows 11 with Chrome 154.

## License

[MIT](LICENSE)
