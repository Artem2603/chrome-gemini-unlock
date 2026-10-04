#Requires -Version 5.1
<#
.SYNOPSIS
    Enables the Gemini side panel (Glic) and its agent features in Google Chrome on Windows.

.DESCRIPTION
    0. Looks for Google Chrome (registry, running processes, standard folders) and stops
       without changing anything if Chrome is missing or has never been started.
    1. Closes Google Chrome: windows first, leftovers by force.
    2. Enables the Glic flags in "Local State" and sets the interface language to en-US.
    3. Switches every Chrome profile to en-US.
    4. Adds --variations-override-country=<Country> --lang=en-US to every way Chrome
       is started: shortcuts, the autostart entry and the link handler. The country is
       also stored in "Local State" as variations_permanent_overridden_country.
    5. Starts Chrome again and checks that it runs with the override.

    The state from before the first run is saved once to
    %LOCALAPPDATA%\chrome-gemini-unlock\backup and never overwritten by later runs.

.PARAMETER Country
    Two-letter country code Chrome should use for its experiments. Default: us.

.PARAMETER NoAdmin
    Never ask for administrator rights. Shortcuts shared by all users stay unchanged.

.PARAMETER NoLaunch
    Do not start Chrome at the end.

.EXAMPLE
    .\chrome-gemini-unlock.ps1
.EXAMPLE
    .\chrome-gemini-unlock.ps1 -NoAdmin -NoLaunch
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z]{2}$')]
    [string]$Country = 'us',
    [switch]$NoAdmin,
    [switch]$NoLaunch,
    # Internal: the elevated copy of the script only updates shortcuts shared by all users
    [switch]$SystemShortcutsOnly,
    [string]$BackupDir,
    [string]$LogFile
)

$ErrorActionPreference = 'Stop'
$Country = $Country.ToLowerInvariant()

$Flags = @(
    'glic@1',
    'glic-actor@1',
    'enable-browser-actuator-for-glic-experimental-triggering@1',
    'glic-background-actuation@1',
    'glic-actor-autofill@1',
    'glic-actor-cursor@1',
    'glic-actor-script-tools@1',
    'glic-toolbar-height-side-panel@1',
    'glic-horizontal-tab-toolbar-button@1',
    'glic-toolbar-button-location@1',
    'glic-context-menu-below-search@1'
)
$Languages    = 'en-US,en'
$OverrideArgs = "--variations-override-country=$Country --lang=en-US"
$ChromeSub    = 'Google\Chrome\Application\chrome.exe'
$UserData     = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
$MySession    = (Get-Process -Id $PID).SessionId

# ---------------------------------------------------------------------------
# Messages
# ---------------------------------------------------------------------------
$Messages = @{
    en = @{
        title         = 'Chrome Gemini Unlock: Gemini side panel (Glic) for Google Chrome'
        searching     = 'Looking for Google Chrome...'
        found         = 'Google Chrome found: {0}'
        foundInfo     = 'version {0}, installed {1}, found via: {2}'
        scopeSystem   = 'for all users'
        scopeUser     = 'for the current user'
        foundOther    = 'Another copy of Chrome, not used: {0}'
        userData      = 'Profile folder: {0}'
        chromeMissing = 'Google Chrome is not installed: nothing found in the registry, among running programs or in the standard folders. Nothing was changed.'
        neverStarted  = 'Chrome has not been started in this Windows account yet ({0} is missing). Start Chrome once, close it and run the script again. Nothing was changed.'
        closing       = 'Closing Google Chrome...'
        closed        = 'Chrome closed'
        restoreHint   = 'Some Chrome windows did not close normally. If Chrome offers to restore pages on the next start, click Restore.'
        stillRunning  = 'chrome.exe is still running. Close Chrome manually and run the script again.'
        backup        = 'Backups (state before the first run): {0}'
        localState    = 'Local State: {0} Glic flags, interface language en-US, country {1}'
        profile       = 'Profile {0}: languages {1}'
        profileSkip   = 'Profile {0}: no Preferences file, skipped'
        shortcut      = 'Shortcut: {0}'
        shortcutOk    = 'Shortcut already set up: {0}'
        adminAsk      = 'Shortcuts shared by all users need administrator rights; the change affects every Windows account on this PC. Confirm the Windows (UAC) prompt, or decline to skip them.'
        adminDeclined = 'Administrator rights were not granted, shared shortcuts were left unchanged.'
        adminNoRun    = 'The administrator copy of the script did not run (exit code {0}), shared shortcuts were left unchanged. Run the script from a folder on a local disk, or use -NoAdmin.'
        adminSkip     = 'Shared shortcuts skipped (-NoAdmin).'
        autostart     = 'Autostart entry: {0}'
        handler       = 'Link handler: {0}'
        handlerOk     = 'Link handler already set up: {0}'
        started       = 'Chrome started with {0} (PID {1})'
        startTimeout  = 'Chrome did not start within 15 seconds. Start it from a shortcut.'
        startFail     = 'Chrome is running, but without the region override. Close it and start it from a shortcut.'
        noLaunch      = 'Chrome was not started (-NoLaunch).'
        done          = 'Done. If Gemini does not appear, open chrome://version and check that "Command Line" contains --variations-override-country.'
        doneErrors    = 'Finished with errors, see the messages above.'
        undo          = 'How to undo: see the "Undo" section in README.'
    }
    ru = @{
        title         = 'Chrome Gemini Unlock: боковая панель Gemini (Glic) в Google Chrome'
        searching     = 'Ищу Google Chrome...'
        found         = 'Google Chrome найден: {0}'
        foundInfo     = 'версия {0}, установлен {1}, найден через: {2}'
        scopeSystem   = 'для всех пользователей'
        scopeUser     = 'для текущего пользователя'
        foundOther    = 'Ещё одна копия Chrome, не используется: {0}'
        userData      = 'Папка профилей: {0}'
        chromeMissing = 'Google Chrome не установлен: его нет ни в реестре, ни среди запущенных программ, ни в стандартных папках. Ничего не изменено.'
        neverStarted  = 'Chrome ещё ни разу не запускался под этой учётной записью Windows (нет {0}). Запустите Chrome один раз, закройте его и запустите скрипт снова. Ничего не изменено.'
        closing       = 'Закрываю Google Chrome...'
        closed        = 'Chrome закрыт'
        restoreHint   = 'Часть окон Chrome не закрылась штатно. Если при следующем запуске Chrome предложит восстановить страницы, нажмите «Восстановить» (Restore).'
        stillRunning  = 'chrome.exe всё ещё работает. Закройте Chrome вручную и запустите скрипт снова.'
        backup        = 'Резервные копии (состояние до первого запуска): {0}'
        localState    = 'Local State: флагов Glic: {0}, язык интерфейса en-US, страна {1}'
        profile       = 'Профиль {0}: языки {1}'
        profileSkip   = 'Профиль {0}: нет файла Preferences, пропущен'
        shortcut      = 'Ярлык: {0}'
        shortcutOk    = 'Ярлык уже настроен: {0}'
        adminAsk      = 'Для общих ярлыков нужны права администратора; изменение затронет все учётные записи Windows на этом компьютере. Подтвердите запрос Windows (UAC) или откажитесь, чтобы их пропустить.'
        adminDeclined = 'Права администратора не получены, общие ярлыки не изменены.'
        adminNoRun    = 'Копия скрипта с правами администратора не запустилась (код выхода {0}), общие ярлыки не изменены. Запустите скрипт из папки на локальном диске или используйте -NoAdmin.'
        adminSkip     = 'Общие ярлыки пропущены (-NoAdmin).'
        autostart     = 'Автозагрузка: {0}'
        handler       = 'Обработчик ссылок: {0}'
        handlerOk     = 'Обработчик ссылок уже настроен: {0}'
        started       = 'Chrome запущен с {0} (PID {1})'
        startTimeout  = 'Chrome не запустился за 15 секунд. Запустите его с ярлыка.'
        startFail     = 'Chrome работает, но без подмены региона. Закройте его и запустите с ярлыка.'
        noLaunch      = 'Chrome не запускался (-NoLaunch).'
        done          = 'Готово. Если Gemini не появился, откройте chrome://version и проверьте, что в строке "Command Line" есть --variations-override-country.'
        doneErrors    = 'Завершено с ошибками, см. сообщения выше.'
        undo          = 'Как откатить изменения: раздел «Откат» в README.'
    }
    fr = @{
        title         = 'Chrome Gemini Unlock : panneau latéral Gemini (Glic) pour Google Chrome'
        searching     = 'Recherche de Google Chrome...'
        found         = 'Google Chrome trouvé : {0}'
        foundInfo     = 'version {0}, installé {1}, trouvé via : {2}'
        scopeSystem   = 'pour tous les utilisateurs'
        scopeUser     = 'pour l''utilisateur actuel'
        foundOther    = 'Autre copie de Chrome, non utilisée : {0}'
        userData      = 'Dossier des profils : {0}'
        chromeMissing = 'Google Chrome n''est pas installé : rien trouvé dans le registre, parmi les programmes en cours ni dans les dossiers standard. Rien n''a été modifié.'
        neverStarted  = 'Chrome n''a encore jamais été démarré sur ce compte Windows ({0} est absent). Démarrez Chrome une fois, fermez-le et relancez le script. Rien n''a été modifié.'
        closing       = 'Fermeture de Google Chrome...'
        closed        = 'Chrome fermé'
        restoreHint   = 'Certaines fenêtres de Chrome ne se sont pas fermées normalement. Si Chrome propose de restaurer les pages au prochain démarrage, cliquez sur Restaurer (Restore).'
        stillRunning  = 'chrome.exe est toujours en cours d''exécution. Fermez Chrome manuellement et relancez le script.'
        backup        = 'Sauvegardes (état avant la première exécution) : {0}'
        localState    = 'Local State : {0} flags Glic, langue de l''interface en-US, pays {1}'
        profile       = 'Profil {0} : langues {1}'
        profileSkip   = 'Profil {0} : pas de fichier Preferences, ignoré'
        shortcut      = 'Raccourci : {0}'
        shortcutOk    = 'Raccourci déjà configuré : {0}'
        adminAsk      = 'Les raccourcis communs nécessitent des droits d''administrateur ; la modification concerne tous les comptes Windows de ce PC. Confirmez la demande UAC de Windows, ou refusez pour les ignorer.'
        adminDeclined = 'Droits d''administrateur refusés, les raccourcis communs n''ont pas été modifiés.'
        adminNoRun    = 'La copie administrateur du script ne s''est pas exécutée (code de sortie {0}), les raccourcis communs n''ont pas été modifiés. Lancez le script depuis un dossier sur un disque local, ou utilisez -NoAdmin.'
        adminSkip     = 'Raccourcis communs ignorés (-NoAdmin).'
        autostart     = 'Démarrage automatique : {0}'
        handler       = 'Gestionnaire de liens : {0}'
        handlerOk     = 'Gestionnaire de liens déjà configuré : {0}'
        started       = 'Chrome démarré avec {0} (PID {1})'
        startTimeout  = 'Chrome n''a pas démarré en 15 secondes. Démarrez-le depuis un raccourci.'
        startFail     = 'Chrome fonctionne, mais sans le changement de région. Fermez-le et relancez-le depuis un raccourci.'
        noLaunch      = 'Chrome n''a pas été démarré (-NoLaunch).'
        done          = 'Terminé. Si Gemini n''apparaît pas, ouvrez chrome://version et vérifiez que « Command Line » contient --variations-override-country.'
        doneErrors    = 'Terminé avec des erreurs, voir les messages ci-dessus.'
        undo          = 'Pour annuler : voir la section « Annulation » du README.'
    }
    de = @{
        title         = 'Chrome Gemini Unlock: Gemini-Seitenleiste (Glic) für Google Chrome'
        searching     = 'Google Chrome wird gesucht...'
        found         = 'Google Chrome gefunden: {0}'
        foundInfo     = 'Version {0}, installiert {1}, gefunden über: {2}'
        scopeSystem   = 'für alle Benutzer'
        scopeUser     = 'für den aktuellen Benutzer'
        foundOther    = 'Weitere Chrome-Kopie, nicht verwendet: {0}'
        userData      = 'Profilordner: {0}'
        chromeMissing = 'Google Chrome ist nicht installiert: weder in der Registrierung noch unter laufenden Programmen oder in den Standardordnern gefunden. Es wurde nichts geändert.'
        neverStarted  = 'Chrome wurde in diesem Windows-Konto noch nie gestartet ({0} fehlt). Starten Sie Chrome einmal, schließen Sie es und führen Sie das Skript erneut aus. Es wurde nichts geändert.'
        closing       = 'Google Chrome wird geschlossen...'
        closed        = 'Chrome geschlossen'
        restoreHint   = 'Einige Chrome-Fenster wurden nicht regulär geschlossen. Wenn Chrome beim nächsten Start anbietet, Seiten wiederherzustellen, klicken Sie auf Wiederherstellen (Restore).'
        stillRunning  = 'chrome.exe läuft noch. Schließen Sie Chrome manuell und starten Sie das Skript erneut.'
        backup        = 'Sicherungen (Zustand vor dem ersten Lauf): {0}'
        localState    = 'Local State: {0} Glic-Flags, Oberflächensprache en-US, Land {1}'
        profile       = 'Profil {0}: Sprachen {1}'
        profileSkip   = 'Profil {0}: keine Preferences-Datei, übersprungen'
        shortcut      = 'Verknüpfung: {0}'
        shortcutOk    = 'Verknüpfung bereits eingerichtet: {0}'
        adminAsk      = 'Verknüpfungen für alle Benutzer erfordern Administratorrechte; die Änderung betrifft jedes Windows-Konto auf diesem PC. Bestätigen Sie die UAC-Abfrage von Windows oder lehnen Sie ab, um sie zu überspringen.'
        adminDeclined = 'Keine Administratorrechte erteilt, gemeinsame Verknüpfungen wurden nicht geändert.'
        adminNoRun    = 'Die Administrator-Kopie des Skripts wurde nicht ausgeführt (Exitcode {0}), gemeinsame Verknüpfungen wurden nicht geändert. Starten Sie das Skript aus einem Ordner auf einem lokalen Laufwerk oder verwenden Sie -NoAdmin.'
        adminSkip     = 'Gemeinsame Verknüpfungen übersprungen (-NoAdmin).'
        autostart     = 'Autostart-Eintrag: {0}'
        handler       = 'Link-Handler: {0}'
        handlerOk     = 'Link-Handler bereits eingerichtet: {0}'
        started       = 'Chrome gestartet mit {0} (PID {1})'
        startTimeout  = 'Chrome ist nicht innerhalb von 15 Sekunden gestartet. Starten Sie es über eine Verknüpfung.'
        startFail     = 'Chrome läuft, aber ohne Regions-Override. Schließen Sie Chrome und starten Sie es über eine Verknüpfung.'
        noLaunch      = 'Chrome wurde nicht gestartet (-NoLaunch).'
        done          = 'Fertig. Falls Gemini nicht erscheint, öffnen Sie chrome://version und prüfen Sie, ob „Command Line“ --variations-override-country enthält.'
        doneErrors    = 'Mit Fehlern beendet, siehe Meldungen oben.'
        undo          = 'Rückgängig machen: siehe Abschnitt „Rückgängig machen“ in der README.'
    }
}
$Lang = (Get-UICulture).TwoLetterISOLanguageName
if (-not $Messages.ContainsKey($Lang)) { $Lang = 'en' }

function T([string]$Key) {
    $text = $Messages[$Lang][$Key]
    if (-not $text) { $text = $Messages['en'][$Key] }
    if ($args.Count) { return $text -f $args }
    return $text
}

$script:HadErrors = $false
function Write-LogLine([string]$Line) {
    if ($LogFile) { Add-Content -LiteralPath $LogFile -Value $Line -Encoding UTF8 }
}
function Ok([string]$m)   { Write-Host "[ OK ] $m" -ForegroundColor Green;  Write-LogLine "[ OK ] $m" }
function Note([string]$m) { Write-Host "       $m" -ForegroundColor Gray;   Write-LogLine "       $m" }
function Warn([string]$m) { Write-Host "[WARN] $m" -ForegroundColor Yellow; Write-LogLine "[WARN] $m" }
function Fail([string]$m) { Write-Host "[FAIL] $m" -ForegroundColor Red;    Write-LogLine "[FAIL] $m"; $script:HadErrors = $true }

# ---------------------------------------------------------------------------
# Files and JSON
# ---------------------------------------------------------------------------
# Windows PowerShell's ConvertFrom-Json treats keys case-insensitively and can
# break Chrome's files, so JavaScriptSerializer (case-sensitive dictionaries) is used.
Add-Type -AssemblyName System.Web.Extensions
$Json = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$Json.MaxJsonLength  = [int]::MaxValue
$Json.RecursionLimit = 1000
$Utf8 = New-Object System.Text.UTF8Encoding($false)

# Retries cover short locks by antivirus, indexer or a Chrome process that is still exiting
function Invoke-WithRetry([scriptblock]$Action) {
    for ($i = 1; ; $i++) {
        try { return & $Action }
        catch { if ($i -ge 10) { throw }; Start-Sleep -Milliseconds 500 }
    }
}

function Read-Json([string]$Path) {
    $text = Invoke-WithRetry { [System.IO.File]::ReadAllText($Path, $Utf8) }
    return $Json.DeserializeObject($text)
}

function Write-Json([string]$Path, $Data) {
    $item = Get-Item -LiteralPath $Path
    if ($item.IsReadOnly) { $item.IsReadOnly = $false }
    $tmp = "$Path.chrome-gemini-unlock.tmp"
    $text = $Json.Serialize($Data)
    $null = $Json.DeserializeObject($text)
    try {
        Invoke-WithRetry { [System.IO.File]::WriteAllText($tmp, $text, $Utf8) } | Out-Null
        # File.Replace swaps the files in one step, so an interruption never leaves a truncated file.
        # [NullString]::Value: a plain $null would reach .NET as an empty string, which is not a valid path
        Invoke-WithRetry { [System.IO.File]::Replace($tmp, $Path, [NullString]::Value) } | Out-Null
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Get-Section($Dict, [string]$Key) {
    if (-not ($Dict[$Key] -is [System.Collections.IDictionary])) {
        # ::new() instead of New-Object: a PSObject-wrapped dictionary breaks Serialize()
        $Dict[$Key] = [System.Collections.Generic.Dictionary[string,object]]::new()
    }
    return $Dict[$Key]
}

# ---------------------------------------------------------------------------
# Backups: the state before the first run, saved once and never overwritten
# ---------------------------------------------------------------------------
if (-not $BackupDir) { $BackupDir = Join-Path $env:LOCALAPPDATA 'chrome-gemini-unlock\backup' }
$BackupDir = [System.IO.Path]::GetFullPath($BackupDir).TrimEnd('\')
$Manifest  = Join-Path $BackupDir 'manifest.txt'

function Test-Manifest([string]$Text) {
    if (-not (Test-Path -LiteralPath $Manifest)) { return $false }
    return ([System.IO.File]::ReadAllText($Manifest)).Contains($Text)
}

function Add-ManifestLine([string]$Line) {
    Add-Content -LiteralPath $Manifest -Value $Line -Encoding UTF8
}

function Save-Backup([string]$Path, [string]$Name) {
    $dest = Join-Path $BackupDir $Name
    if (Test-Path -LiteralPath $dest) { return }
    $parent = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Invoke-WithRetry { Copy-Item -LiteralPath $Path -Destination $dest -Force } | Out-Null
    Add-ManifestLine "$Name  ->  $Path"
}

# Short stable folder name per shortcut path, so equal names in different folders do not clash
function Get-PathTag([string]$Path) {
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Path.ToLowerInvariant()))
    return -join ($hash[0..3] | ForEach-Object { $_.ToString('x2') })
}

# ---------------------------------------------------------------------------
# Command lines
# ---------------------------------------------------------------------------
# Each switch is removed together with its own trailing space, so quoted values stay byte for byte
function Add-OverrideArgs([string]$Arguments) {
    $rest = $Arguments -replace '(?<!\S)--variations-override-country=\S*\s*', '' -replace '(?<!\S)--lang=\S*\s*', ''
    $rest = $rest.Trim()
    if ($rest) { return "$OverrideArgs $rest" }
    return $OverrideArgs
}

function Add-OverrideToCommand([string]$Command) {
    # The executable is a quoted path, an unquoted path ending in chrome.exe (may contain spaces), or a single token
    if ($Command -match '^\s*("[^"]+"|[^"]+?\\chrome\.exe(?=\s|$)|\S+)\s*(.*)$') {
        $exe  = $Matches[1]
        $rest = $Matches[2]
        if (-not $exe.StartsWith('"') -and $exe.Contains(' ')) { $exe = '"' + $exe + '"' }
        return "$exe $(Add-OverrideArgs $rest)"
    }
    return $Command
}

# ---------------------------------------------------------------------------
# Shortcuts
# ---------------------------------------------------------------------------
$UserShortcutDirs = @(
    @{ Path = [Environment]::GetFolderPath('Desktop');   Recurse = $false },
    @{ Path = (Join-Path $env:USERPROFILE 'Desktop');    Recurse = $false },
    @{ Path = [Environment]::GetFolderPath('StartMenu'); Recurse = $true },
    @{ Path = (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch'); Recurse = $true }
)
$SystemShortcutDirs = @(
    @{ Path = [Environment]::GetFolderPath('CommonDesktopDirectory'); Recurse = $false },
    @{ Path = [Environment]::GetFolderPath('CommonStartMenu');        Recurse = $true }
)

function Get-ChromeShortcuts($Dirs) {
    $shell = New-Object -ComObject WScript.Shell
    $seen = @{}
    foreach ($d in $Dirs) {
        if (-not $d.Path -or -not (Test-Path -LiteralPath $d.Path)) { continue }
        $files = Get-ChildItem -LiteralPath $d.Path -Filter *.lnk -Recurse:$d.Recurse -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            # -Filter *.lnk also matches *.lnk_old / *.lnkx through their 8.3 short names
            if ($f.Extension -ne '.lnk') { continue }
            if ($seen.ContainsKey($f.FullName)) { continue }
            $seen[$f.FullName] = $true
            try {
                $link = $shell.CreateShortcut($f.FullName)
                if ($link.TargetPath -like "*\$ChromeSub") {
                    [pscustomobject]@{ Path = $f.FullName; Name = $f.Name; Link = $link }
                }
            } catch { Warn "$($f.FullName): $($_.Exception.Message)" }
        }
    }
}

function Test-ShortcutPending($Shortcut) {
    return (Add-OverrideArgs $Shortcut.Link.Arguments) -ne $Shortcut.Link.Arguments
}

function Update-Shortcuts($Shortcuts) {
    foreach ($s in $Shortcuts) {
        try {
            if (-not (Test-ShortcutPending $s)) { Ok (T 'shortcutOk' $s.Path); continue }
            Save-Backup $s.Path ("shortcuts\{0}\{1}" -f (Get-PathTag $s.Path), $s.Name)
            # Saving through the same IShellLink keeps icon, AppUserModelID and taskbar pinning
            $s.Link.Arguments = Add-OverrideArgs $s.Link.Arguments
            $s.Link.Save()
            Ok (T 'shortcut' $s.Path)
            Note $s.Link.Arguments
        } catch { Fail "$($s.Path): $($_.Exception.Message)" }
    }
}

# Elevated copy started by the main run: shared shortcuts only
if ($SystemShortcutsOnly) {
    try { Update-Shortcuts @(Get-ChromeShortcuts $SystemShortcutDirs) }
    catch { Fail $_.Exception.Message }
    if ($script:HadErrors) { exit 2 }
    exit 0
}

# ---------------------------------------------------------------------------
# Chrome installation and processes
# ---------------------------------------------------------------------------
# Every place Windows records a Chrome installation, in order of trust
function Find-Chrome {
    $found = [ordered]@{}
    $add = {
        param([string]$Value, [string]$Source)
        if (-not $Value) { return }
        $path = [Environment]::ExpandEnvironmentVariables($Value.Trim())
        # "C:\...\chrome.exe" --args  /  C:\...\chrome.exe,0  /  C:\...\Application
        if ($path -match '^"([^"]+)"') { $path = $Matches[1] }
        $path = ($path -replace ',\s*-?\d+$', '').Trim()
        if ($path -notlike '*.exe') { $path = Join-Path $path 'chrome.exe' }
        if ($path -notlike "*\$ChromeSub" -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
        $path = (Get-Item -LiteralPath $path).FullName
        if (-not $found.Contains($path)) { $found[$path] = New-Object System.Collections.Generic.List[string] }
        if (-not $found[$path].Contains($Source)) { $found[$path].Add($Source) }
    }
    $roots = 'HKCU:\SOFTWARE', 'HKLM:\SOFTWARE', 'HKLM:\SOFTWARE\WOW6432Node'
    foreach ($root in $roots) {
        $key = Get-Item -LiteralPath "$root\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" -ErrorAction SilentlyContinue
        if ($key) { & $add $key.GetValue('') 'App Paths' }
    }
    foreach ($root in $roots) {
        $key = Get-Item -LiteralPath "$root\Clients\StartMenuInternet\Google Chrome\shell\open\command" -ErrorAction SilentlyContinue
        if ($key) { & $add $key.GetValue('') 'StartMenuInternet' }
    }
    foreach ($root in $roots) {
        $key = Get-Item -LiteralPath "$root\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome" -ErrorAction SilentlyContinue
        if ($key) {
            & $add $key.GetValue('InstallLocation') 'Uninstall'
            & $add $key.GetValue('DisplayIcon') 'Uninstall'
        }
    }
    foreach ($p in Get-Process chrome -ErrorAction SilentlyContinue) { & $add $p.Path 'running process' }
    foreach ($dir in $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA) {
        if ($dir) { & $add (Join-Path $dir $ChromeSub) 'standard folder' }
    }
    foreach ($path in $found.Keys) {
        $isUser = $path.StartsWith($env:LOCALAPPDATA + '\', [StringComparison]::OrdinalIgnoreCase)
        [pscustomobject]@{
            Path    = $path
            Version = (Get-Item -LiteralPath $path).VersionInfo.ProductVersion
            Scope   = if ($isUser) { 'User' } else { 'System' }
            Sources = $found[$path] -join ', '
        }
    }
}

# Only Chrome of the current Windows session: Chrome in other users' sessions is neither waited for nor killed
function Get-ChromeProcesses {
    Get-Process chrome -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $MySession -and (-not $_.Path -or $_.Path -like "*\$ChromeSub") }
}

# ---------------------------------------------------------------------------
# Main run
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host (T 'title') -ForegroundColor Cyan
Write-Host ''

# ---- 0. Find Chrome before touching anything
Note (T 'searching')
# A system-wide Chrome wins: Chrome itself removes a leftover per-user copy when both exist.
# Two passes instead of Sort-Object, which is not stable in Windows PowerShell 5.1
$all = @(Find-Chrome)
$installs = @($all | Where-Object { $_.Scope -eq 'System' }) + @($all | Where-Object { $_.Scope -ne 'System' })
if ($installs.Count -eq 0) { Fail (T 'chromeMissing'); exit 1 }
$chromeExe = $installs[0].Path
Ok (T 'found' $chromeExe)
Note (T 'foundInfo' $installs[0].Version (T ('scope' + $installs[0].Scope)) $installs[0].Sources)
foreach ($other in ($installs | Select-Object -Skip 1)) { Warn (T 'foundOther' $other.Path) }

$localState = Join-Path $UserData 'Local State'
if (-not (Test-Path -LiteralPath $localState)) { Fail (T 'neverStarted' $localState); exit 1 }
Note (T 'userData' $UserData)

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Note (T 'backup' $BackupDir)

# ---- 1. Close Chrome: ask every window to close, then end what is left
Note (T 'closing')
$deadline = (Get-Date).AddSeconds(10)
while ((Get-Date) -lt $deadline) {
    $windows = @(Get-ChromeProcesses | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero })
    if ($windows.Count -eq 0) { break }
    foreach ($p in $windows) { try { $null = $p.CloseMainWindow() } catch { } }
    Start-Sleep -Milliseconds 700
}
$deadline = (Get-Date).AddSeconds(5)
while ((Get-ChromeProcesses) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
$leftovers = @(Get-ChromeProcesses)
if ($leftovers.Count) {
    $leftovers | Stop-Process -Force -ErrorAction SilentlyContinue
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-ChromeProcesses) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
}
if (Get-ChromeProcesses) { Fail (T 'stillRunning'); exit 1 }
Ok (T 'closed')
if ($leftovers.Count) { Note (T 'restoreHint') }

# ---- 2. Local State: flags, interface language, stored country
$state = $null
try {
    Save-Backup $localState 'Local State'
    $state = Read-Json $localState
    $browser = Get-Section $state 'browser'
    $flagNames = $Flags | ForEach-Object { $_.Split('@')[0] }
    $list = New-Object System.Collections.Generic.List[object]
    if ($browser['enabled_labs_experiments']) {
        foreach ($e in $browser['enabled_labs_experiments']) {
            # Drop other states of the same flags so glic@2 does not fight with glic@1
            if ($flagNames -notcontains ([string]$e).Split('@')[0]) { $list.Add($e) }
        }
    }
    foreach ($f in $Flags) { $list.Add($f) }
    $browser['enabled_labs_experiments'] = $list.ToArray()
    # On Windows the interface language is read from Local State, not from the profile
    (Get-Section $state 'intl')['app_locale'] = 'en-US'
    # Covers the experiments that use the permanent country, also when Chrome starts without the switch
    $state['variations_permanent_overridden_country'] = $Country
    Write-Json $localState $state
    Ok (T 'localState' $Flags.Count $Country.ToUpperInvariant())
} catch { Fail "Local State: $($_.Exception.Message)" }

# ---- 3. Profiles: en-US
$profiles = @()
if ($state -and $state['profile'] -is [System.Collections.IDictionary] -and
    $state['profile']['info_cache'] -is [System.Collections.IDictionary]) {
    foreach ($dir in $state['profile']['info_cache'].Keys) {
        $profiles += [pscustomobject]@{ Dir = $dir; Name = [string]$state['profile']['info_cache'][$dir]['name'] }
    }
}
if (-not $profiles) { $profiles = @([pscustomobject]@{ Dir = 'Default'; Name = '' }) }

foreach ($p in $profiles) {
    $label = if ($p.Name) { "`"$($p.Dir)`" ($($p.Name))" } else { "`"$($p.Dir)`"" }
    $prefs = Join-Path $UserData "$($p.Dir)\Preferences"
    try {
        if (-not (Test-Path -LiteralPath $prefs)) { Note (T 'profileSkip' $label); continue }
        Save-Backup $prefs "profiles\$($p.Dir)\Preferences"
        $data = Read-Json $prefs
        $intl = Get-Section $data 'intl'
        $intl['app_locale']         = 'en-US'
        $intl['accept_languages']   = $Languages
        # Chrome rebuilds accept_languages from this list, so it has to change too
        $intl['selected_languages'] = $Languages
        Write-Json $prefs $data
        Ok (T 'profile' $label $Languages)
    } catch { Fail "$label : $($_.Exception.Message)" }
}

# ---- 4. Shortcuts of the current user
try { Update-Shortcuts @(Get-ChromeShortcuts $UserShortcutDirs) }
catch { Fail $_.Exception.Message }

# ---- 5. Shortcuts shared by all users (administrator rights)
try {
    $shared  = @(Get-ChromeShortcuts $SystemShortcutDirs)
    $pending = @($shared | Where-Object { Test-ShortcutPending $_ })
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                   [Security.Principal.WindowsBuiltInRole]::Administrator)
    # -NoAdmin wins even when the script already runs elevated
    if ($pending.Count -eq 0) {
        Update-Shortcuts $shared
    } elseif ($NoAdmin) {
        Warn (T 'adminSkip')
    } elseif ($isAdmin) {
        Update-Shortcuts $shared
    } else {
        Warn (T 'adminAsk')
        $log = Join-Path $BackupDir 'elevated.log'
        if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
        # A local copy: an elevated process does not see mapped network or SUBST drives
        $elevatedScript = Join-Path $BackupDir 'elevated.ps1'
        Copy-Item -LiteralPath $PSCommandPath -Destination $elevatedScript -Force
        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$elevatedScript`" -SystemShortcutsOnly " +
                   "-Country $Country -BackupDir `"$BackupDir`" -LogFile `"$log`""
        $proc = $null
        try {
            $proc = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList -WindowStyle Hidden -Wait -PassThru
        } catch { Warn (T 'adminDeclined') }
        Remove-Item -LiteralPath $elevatedScript -Force -ErrorAction SilentlyContinue
        if ($proc) {
            $hasLog = (Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 0
            if ($hasLog) {
                foreach ($line in Get-Content -LiteralPath $log -Encoding UTF8) {
                    $color = if ($line.StartsWith('[FAIL]')) { 'Red' } elseif ($line.StartsWith('[ OK ]')) { 'Green' } elseif ($line.StartsWith('[WARN]')) { 'Yellow' } else { 'Gray' }
                    Write-Host $line -ForegroundColor $color
                }
            }
            if ($proc.ExitCode -ne 0) {
                if ($hasLog) { $script:HadErrors = $true } else { Fail (T 'adminNoRun' $proc.ExitCode) }
            }
        }
    }
} catch { Fail $_.Exception.Message }

# ---- 6. Autostart entry (Chrome started in the background at Windows logon)
$runKey  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runName = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run'
try {
    $run = Get-Item -LiteralPath $runKey -ErrorAction SilentlyContinue
    if ($run) {
        foreach ($name in $run.GetValueNames()) {
            if ($name -notlike 'GoogleChromeAutoLaunch*') { continue }
            $value = [string]$run.GetValue($name)
            if ($value -notlike "*\$ChromeSub*") { continue }
            $new = Add-OverrideToCommand $value
            if ($new -ne $value) {
                $entry = "[registry] $runName  $name = "
                if (-not (Test-Manifest $entry)) { Add-ManifestLine "$entry$value" }
                Set-ItemProperty -LiteralPath $runKey -Name $name -Value $new
            }
            Ok (T 'autostart' $name)
            Note $new
        }
    }
} catch { Fail "Autostart: $($_.Exception.Message)" }

# ---- 7. Link handlers (a link clicked in another program while Chrome is closed)
try {
    $progIds = @()
    foreach ($hive in 'HKCU', 'HKLM') {
        $progIds += @(Get-ChildItem -Path "${hive}:\Software\Classes" -Name -ErrorAction SilentlyContinue |
                      Where-Object { $_ -match '^Chrome(HTML|PDF)(\..+)?$' })
    }
    foreach ($id in ($progIds | Select-Object -Unique)) {
        try {
            $userKey    = "HKCU:\Software\Classes\$id"
            $userCmd    = "$userKey\shell\open\command"
            $machineCmd = "HKLM:\Software\Classes\$id\shell\open\command"
            $source = if (Test-Path -LiteralPath $userCmd) { $userCmd } elseif (Test-Path -LiteralPath $machineCmd) { $machineCmd } else { $null }
            if (-not $source) { continue }
            $command = [string](Get-Item -LiteralPath $source).GetValue('')
            if ($command -notlike "*\$ChromeSub*") { continue }
            $new = Add-OverrideToCommand $command
            if ($new -eq $command) { Ok (T 'handlerOk' $id); continue }
            $created = "[registry] created HKCU\Software\Classes\$id "
            if (Test-Path -LiteralPath $userKey) {
                # A key that existed before the first run (per-user Chrome install) is exported once
                $regName = "registry\handler-$id.reg"
                $reg = Join-Path $BackupDir $regName
                if (-not (Test-Manifest $created) -and -not (Test-Path -LiteralPath $reg)) {
                    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $reg) | Out-Null
                    & reg.exe export "HKCU\Software\Classes\$id" $reg /y | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "reg export exit code $LASTEXITCODE" }
                    Add-ManifestLine "$regName  ->  HKCU\Software\Classes\$id"
                }
            } else {
                # A per-user copy of the machine-wide handler takes precedence over it
                & reg.exe copy "HKLM\Software\Classes\$id" "HKCU\Software\Classes\$id" /s /f | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "reg copy exit code $LASTEXITCODE" }
                if (-not (Test-Manifest $created)) { Add-ManifestLine "$created(delete it to undo)" }
            }
            if (-not (Test-Path -LiteralPath $userCmd)) { New-Item -Path $userCmd -Force | Out-Null }
            Set-Item -LiteralPath $userCmd -Value $new
            Ok (T 'handler' $id)
            Note $new
        } catch { Fail "${id}: $($_.Exception.Message)" }
    }
} catch { Fail "Link handlers: $($_.Exception.Message)" }

# ---- 8. Start Chrome and check its command line
if ($NoLaunch) {
    Note (T 'noLaunch')
} else {
    try {
        Start-Process -FilePath $chromeExe -ArgumentList $OverrideArgs.Split(' ')
        $main = $null
        $deadline = (Get-Date).AddSeconds(15)
        while (-not $main -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 500
            $main = Get-CimInstance Win32_Process -Filter "Name='chrome.exe' AND SessionId=$MySession" |
                    Where-Object { $_.ExecutablePath -like "*\$ChromeSub" -and $_.CommandLine -notmatch '--type=' } |
                    Select-Object -First 1
        }
        if (-not $main) {
            Fail (T 'startTimeout')
        } elseif ($main.CommandLine -like "*--variations-override-country=$Country*") {
            Ok (T 'started' $OverrideArgs $main.ProcessId)
        } else {
            Fail (T 'startFail')
        }
    } catch { Fail "Chrome: $($_.Exception.Message)" }
}

Write-Host ''
if ($script:HadErrors) {
    Write-Host (T 'doneErrors') -ForegroundColor Red
} else {
    Write-Host (T 'done') -ForegroundColor Cyan
}
Note (T 'backup' $BackupDir)
Note (T 'undo')
if ($script:HadErrors) { exit 2 }
exit 0
