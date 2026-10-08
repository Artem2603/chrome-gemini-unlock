# Changelog

Versions follow [semantic versioning](https://semver.org/): MAJOR changes what an existing run does, MINOR adds an option, PATCH fixes a bug. The release workflow publishes the section of a version as its release notes.

## v1.0.0

First versioned release.

**Changed: agent features are opt-in.** The 5 flags of the Gemini side panel are enabled as before. The 6 agent flags (`glic-actor`, `enable-browser-actuator-for-glic-experimental-triggering`, `glic-background-actuation`, `glic-actor-autofill`, `glic-actor-cursor`, `glic-actor-script-tools`), which let Gemini click, type and fill in forms on web pages, are enabled only with `-Agent`; a run without it sets them back to Default.

Added:
- `-Restore` undoes the changes with the backup: the Glic flags, languages, stored country, shortcut arguments, autostart entry and link handler. Everything else Chrome saved since is kept. After a complete restore the backup folder is renamed to `backup-restored-<date>`.
- The script asks before closing Chrome; `-Force` skips the question. In a non-interactive session it stops without changing anything.
- A warning when the installed Chrome is past a flag's expiry milestone (for example `glic-actor-cursor` in Chrome 155).
- Started from PowerShell 7, the script restarts itself in Windows PowerShell 5.1.
- Tests: unit tests, a check in a real Chrome that every flag is applied, and an end-to-end run on Windows, in GitHub Actions.

Security:
- The copy of the script that runs with administrator rights is checked by SHA-256 before it runs, so a program that swaps it while the UAC prompt is open gets nothing. The script refuses to write through a junction or symbolic link in the backup folder.
- Chrome is no longer started with administrator rights when the script itself runs elevated.

Fixed:
- A `--lang=` inside a quoted shortcut argument no longer breaks that argument.
- A read-only `Local State` or `Preferences` stays read-only.
- Paths with typographic apostrophes (U+2018 to U+201B) no longer break the administrator copy.
- `Get-Help` shows the script's help again.
