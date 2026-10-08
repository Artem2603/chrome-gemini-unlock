# Chrome Gemini Unlock

[![test](https://github.com/artem2603/chrome-gemini-unlock/actions/workflows/test.yml/badge.svg)](https://github.com/artem2603/chrome-gemini-unlock/actions/workflows/test.yml)

**English** · [Русский](README.ru.md) · [Français](README.fr.md) · [Deutsch](README.de.md)

A Windows script that turns on the Gemini side panel in Google Chrome (internal name "Glic"), and optionally its agent features, when Chrome hides them because of the profile language or the region.

> Unofficial project, not affiliated with Google. The flags are experimental: Google can rename or remove them in any Chrome version, and can still decide availability by account. Use at your own risk.

## What it does

0. Looks for Google Chrome: in the registry, among running programs and in the standard folders. If Chrome is not installed, or has never been started in this Windows account, the script stops without changing anything.
1. Closes Google Chrome. If Chrome is running, the script asks first (`-Force` skips the question). In a non-interactive session, where it cannot ask, it stops without changing anything and asks you to run it with `-Force`. It then asks every window to close, as if you closed them yourself, and ends whatever is still running a few seconds later. In that case Chrome may offer to restore pages on the next start: click **Restore**. Text typed into unsent forms is lost either way.
2. Enables 5 Glic flags in Chrome's `Local State` file, for the side panel, its toolbar button and its context menu entry:
   `glic`, `glic-toolbar-height-side-panel`, `glic-horizontal-tab-toolbar-button`, `glic-toolbar-button-location`, `glic-context-menu-below-search`.

   The 6 agent flags are enabled only with `-Agent`; a run without `-Agent` sets them back to Default:
   `glic-actor`, `enable-browser-actuator-for-glic-experimental-triggering`, `glic-background-actuation`, `glic-actor-autofill`, `glic-actor-cursor`, `glic-actor-script-tools`.

   If the installed Chrome is newer than the expiry milestone of a flag it enables, the script warns that Chrome may ignore that flag.
3. Switches the Chrome interface to English (en-US) and sets the languages of every profile to `en-US,en`.
4. Makes Chrome use the United States as its region for experiments:
   - adds `--variations-override-country=us --lang=en-US` to Chrome shortcuts: desktop, Start menu, taskbar, and the shortcuts shared by all users (these need administrator rights, Windows asks through UAC). A `--lang=` or `--variations-override-country=` already present in a shortcut is replaced;
   - adds the same arguments to Chrome's autostart entry, if there is one;
   - adds them to the link handler, so Chrome opened by a link from another program also gets them;
   - stores the country in `Local State` (`variations_permanent_overridden_country`).
5. Starts Chrome again and checks that it runs with the override. When the script runs with administrator rights, it does not start Chrome, because Chrome would get these rights too: start Chrome from a shortcut.

Before changing anything, the script saves the original state to `%LOCALAPPDATA%\chrome-gemini-unlock\backup`: files are copied there, registry values are written to `manifest.txt`. Later runs never overwrite this backup. `-Restore` uses it to undo the changes; after a complete restore the folder is renamed to `backup-restored-<date>`, so the next run saves the state as it is then.

## Requirements

- Windows 10 or 11 with Windows PowerShell 5.1 (built in). Started from PowerShell 7, the script restarts itself in Windows PowerShell 5.1.
- Google Chrome, stable channel, started at least once in your Windows account. Beta, Dev and Canary are not supported.

## Usage

1. Download `chrome-gemini-unlock-vX.Y.Z.zip` from the [latest release](https://github.com/Artem2603/chrome-gemini-unlock/releases/latest) and extract it. (**Code → Download ZIP** gives the current development state instead.)
2. Double-click `chrome-gemini-unlock.bat`.
3. If Chrome is running, the script asks whether to close it: type **Y** and press Enter. Any other answer cancels without changing anything.
4. If Windows asks for administrator rights, confirm. This is only needed for the shortcuts shared by all users; if you decline, everything else still works.
5. Chrome restarts. The Gemini button should appear in the toolbar.

Options can be added when the script is started from a command prompt in the extracted folder, for example:

```bat
chrome-gemini-unlock.bat -NoAdmin
```

| Option | Meaning |
|---|---|
| `-Country us` | Region for experiments, two letters. Default: `us`. |
| `-Agent` | Also enable the agent features (see "Good to know"). Without it, the agent flags are set back to Default. |
| `-Force` | Close Chrome without asking. Needed in a non-interactive session, where the script cannot ask. |
| `-Restore` | Undo the changes with the backup (see "Undo"). |
| `-NoAdmin` | Never ask for administrator rights; shared shortcuts stay unchanged. |
| `-NoLaunch` | Do not start Chrome at the end. |

Running the script again is safe: shortcuts and link handlers that are already set up are reported as "already set up", an autostart entry that already has the arguments stays as it is, and the backup keeps the state from before the first run. Each run still closes and restarts Chrome and writes the flags and language settings again.

**Checking the download.** Each release has a `.sha256` file next to its ZIP. In PowerShell, in the folder with both files, this command must print `True`; otherwise the ZIP is not the one that was published:

```powershell
(Get-FileHash .\chrome-gemini-unlock-v1.0.0.zip -Algorithm SHA256).Hash -eq (Get-Content .\chrome-gemini-unlock-v1.0.0.zip.sha256).Split(' ')[0]
```

Replace `v1.0.0` with the version you downloaded.

## Good to know

- **Start Chrome from its shortcuts.** If some program runs `chrome.exe` directly, that Chrome starts without the command-line override. The country stored in `Local State` then covers only part of the experiments.
- **Check the override:** open `chrome://version`. The "Command Line" row must contain `--variations-override-country=us`.
- **Autostart.** Chrome manages its own autostart entry and can recreate it without the override. If Gemini disappears after a reboot, turn off "Continue running background apps when Google Chrome is closed" in `chrome://settings/system`, or run the script again.
- **Chrome updates** can recreate the shared shortcuts. If Gemini disappears after an update, run the script again.
- **Shared computer.** The shortcuts shared by all users affect every Windows account on the PC. To change only your own shortcuts, run the script with `-NoAdmin`. Chrome running in other users' Windows sessions is never closed; a Chrome started with "Run as different user" on your own desktop is closed like your own.
- **Languages and sync.** Profiles get the languages `en-US,en`, so websites will prefer English. With Chrome sync turned on, the language list also reaches your Chrome on other computers.
- **Link handler.** The script puts a per-user copy of Chrome's link registration into `HKCU\Software\Classes` (`ChromeHTML`, `ChromePDF`). If you uninstall Chrome, delete these keys (see "Undo").
- **Agent features** are off by default. With `-Agent`, Gemini can click, type and fill in forms for you in your browser, where you are signed in to your accounts. A web page can hide instructions for the AI in its content (prompt injection) and make Gemini act against you. Enable them only if you accept that risk, and keep an eye on what Gemini does.
- **Flags expire.** In Chromium's flag metadata, most of these flags are due to expire after Chrome 160; `glic-actor` after Chrome 172, `enable-browser-actuator-for-glic-experimental-triggering` and `glic-actor-script-tools` after Chrome 170. After that, Chrome ignores a flag unless Google extends it. The script warns when the installed Chrome is past a flag's expiry. `glic-actor-cursor` had already expired in Chrome 155 and was extended to 160 only from Chrome 156: on Chrome 155 the script warns. Chrome removes an expired flag's setting at every start, so to bring it back for now: enable `chrome://flags/#temporary-unexpire-flags-m154`, restart Chrome, then run the script again.
- **Administrator copy.** For the shared shortcuts, the script writes a copy of itself to the backup folder and runs it with administrator rights. The copy is checked by SHA-256 before it runs: if a program changed it while the Windows prompt was open, it does not run and shared shortcuts stay unchanged. Before every write into the backup folder the script checks it for a junction or symbolic link and refuses to write through one.

## Undo

Run this from a command prompt in the extracted folder:

```bat
chrome-gemini-unlock.bat -Restore
```

Like a normal run, it asks before closing Chrome and starts Chrome again at the end. Using the backup, it puts back only what the script changed:

- the Glic flags (other flags stay as they are);
- the interface language and the languages of the profiles the script changed;
- the stored country;
- the arguments of the Chrome shortcuts (icon, pinning and name stay as they are now);
- the autostart entry, if Chrome still has it;
- the link handler: the per-user copy is deleted, or the key that existed before the script is imported again;
- Chrome shortcuts that got the arguments without a backup, for example a taskbar pin made from a changed shortcut, lose the two arguments.

Everything else Chrome saved since the first run, for example other settings or new profiles, is kept. Shared shortcuts need administrator rights again: confirm the Windows prompt, or they stay unchanged; the script then says the restore is not complete, keeps the backup, and you can run `-Restore` again. After a complete restore the backup folder is renamed to `backup-restored-<date>`: a later `-Restore` does not go back to the state before the very first run.

**Manual undo** (if the script cannot run):

1. In Chrome: `chrome://flags` → **Reset all** (or set the `glic` flags and `enable-browser-actuator-for-glic-experimental-triggering` back to Default one by one), then pick your languages and the display language in `chrome://settings/languages`.
2. Remove `--variations-override-country=us --lang=en-US` from the "Target" field in the properties of each Chrome shortcut. If a shortcut had its own `--lang=` before, put it back; the original shortcut is in the backup (`shortcuts\<code>\<name>.lnk`).
3. Open `%LOCALAPPDATA%\chrome-gemini-unlock\backup\manifest.txt` and delete the registry keys that it lists as `created`:
   ```bat
   reg delete "HKCU\Software\Classes\ChromeHTML" /f
   reg delete "HKCU\Software\Classes\ChromePDF" /f
   ```
   If the backup contains `registry\handler-*.reg`, double-click it instead: it restores a key that existed before the script.
4. If the manifest has a line `...\Run  GoogleChromeAutoLaunch_<code> = ...`, delete that autostart value; Chrome creates it again by itself when it needs it:
   ```bat
   reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v GoogleChromeAutoLaunch_<code> /f
   ```
5. Close Chrome completely: close all windows, then, if there is a Chrome icon in the notification area, right-click it and choose **Exit**. Make sure no `chrome.exe` is left in Task Manager (Details tab), otherwise Chrome writes its settings back over the change. Then remove the stored country from `Local State` with PowerShell:
   ```powershell
   $f = "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"
   [IO.File]::WriteAllText($f, ([IO.File]::ReadAllText($f) -replace ',"variations_permanent_overridden_country":"[a-z]*"', ''))
   ```

## Files

| File | Purpose |
|---|---|
| `chrome-gemini-unlock.bat` | Launcher for double-click; runs the PowerShell script and passes options through. |
| `chrome-gemini-unlock.ps1` | The script itself. Messages in English, Russian, French and German, chosen by the Windows language. |
| `tests/` | Unit tests, a check of the flags in a real Chrome, and an end-to-end test on Windows. |
| `.github/workflows/test.yml` | Runs the tests on GitHub Actions. |
| `.github/workflows/release.yml` | On a tag like `v1.2.3`, or when started by hand (Actions → Release → Run workflow, version `v1.2.3`), runs all tests and, if they pass, publishes the release. |
| `tools/build-release.sh` | Builds a release: the ZIP, its SHA-256 and the release notes. |
| `CHANGELOG.md` | What changed in each version. |

Tested on Windows 11 with Chrome 154. `tests/chrome-flags.ps1` starts a real Chrome and checks that it applies every flag, except those the script's expiry table marks as expired in that version (with Chrome 155: all but `glic-actor-cursor`).

## License

[MIT](LICENSE)
