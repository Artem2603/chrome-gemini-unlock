#Requires -Version 5.1
<#
.SYNOPSIS
    Enables the Gemini side panel (Glic) in Google Chrome on Windows.

.DESCRIPTION
    0. Looks for Google Chrome (registry, running processes, standard folders) and stops
       without changing anything if Chrome is missing or has never been started.
    1. Asks before closing Google Chrome, then closes it: windows first, leftovers by force.
    2. Enables the Glic flags in "Local State" and sets the interface language to en-US.
       The agent flags, which let Gemini act on web pages, are enabled only with -Agent.
    3. Switches every Chrome profile to en-US.
    4. Adds --variations-override-country=<Country> --lang=en-US to every way Chrome
       is started: shortcuts, the autostart entry and the link handler. The country is
       also stored in "Local State" as variations_permanent_overridden_country.
    5. Starts Chrome again and checks that it runs with the override.

    The state from before the first run is saved once to
    %LOCALAPPDATA%\chrome-gemini-unlock\backup and never overwritten by later runs.
    -Restore puts that state back.

.PARAMETER Country
    Two-letter country code Chrome should use for its experiments. Default: us.

.PARAMETER Agent
    Also enable the agent features: Gemini clicking, typing and filling in forms on web
    pages for you. Without -Agent these flags are set back to Default.

.PARAMETER Force
    Close Chrome without asking first.

.PARAMETER Restore
    Undo the changes: the Glic flags, languages, stored country, shortcuts, the autostart
    entry and the link handler return to the state before the first run. Other Chrome
    settings are kept.

.PARAMETER NoAdmin
    Never ask for administrator rights. Shortcuts shared by all users stay unchanged.

.PARAMETER NoLaunch
    Do not start Chrome at the end.

.EXAMPLE
    .\chrome-gemini-unlock.ps1
.EXAMPLE
    .\chrome-gemini-unlock.ps1 -Agent
.EXAMPLE
    .\chrome-gemini-unlock.ps1 -Restore
.EXAMPLE
    .\chrome-gemini-unlock.ps1 -NoAdmin -NoLaunch
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z]{2}\z')]
    [string]$Country = 'us',
    [switch]$Agent,
    [switch]$Force,
    [switch]$Restore,
    [switch]$NoAdmin,
    [switch]$NoLaunch,
    # Internal: the elevated copy of the script only handles shortcuts shared by all users
    [switch]$SystemShortcutsOnly,
    [string]$BackupDir,
    [string]$LogFile
)

$ErrorActionPreference = 'Stop'
$Country = $Country.ToLowerInvariant()
# The exact text this process runs; the elevated copy is checked against it (Invoke-ElevatedShortcuts)
$ScriptText = $MyInvocation.MyCommand.ScriptContents

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
        flagExpiry    = 'Flag {0} expired after Chrome {1}, and this is Chrome {2}: Chrome ignores it. While chrome://flags/#temporary-unexpire-flags-m{1} exists, enabling it brings the flag back.'
        confirmClose  = 'Google Chrome is running and will be closed. Downloads, calls and unsent form input in Chrome will be interrupted.'
        confirmPrompt = 'Close Chrome now? [Y/N]'
        cancelled     = 'Cancelled. Nothing was changed.'
        needForce     = 'Cannot ask before closing Chrome in a non-interactive session. Run the script with -Force. Nothing was changed.'
        closing       = 'Closing Google Chrome...'
        closed        = 'Chrome closed'
        restoreHint   = 'Some Chrome windows did not close normally. If Chrome offers to restore pages on the next start, click Restore.'
        stillRunning  = 'chrome.exe is still running. Close Chrome manually and run the script again.'
        backup        = 'Backups (state before the first run): {0}'
        localState    = 'Local State: {0} Glic flags, interface language en-US, country {1}'
        agentOn       = 'Agent features are on (-Agent): Gemini can click, type and fill in forms on web pages for you. Keep an eye on what it does.'
        agentOff      = 'Agent features are off. To let Gemini act on web pages for you, run the script with -Agent.'
        profile       = 'Profile {0}: languages {1}'
        profileSkip   = 'Profile {0}: no Preferences file, skipped'
        shortcut      = 'Shortcut: {0}'
        shortcutOk    = 'Shortcut already set up: {0}'
        adminAsk      = 'Shortcuts shared by all users need administrator rights; the change affects every Windows account on this PC. Confirm the Windows (UAC) prompt, or decline to skip them.'
        adminDeclined = 'Administrator rights were not granted, shared shortcuts were left unchanged.'
        adminNoRun    = 'The administrator copy of the script did not run (exit code {0}), shared shortcuts were left unchanged. Run the script from a folder on a local disk, or use -NoAdmin.'
        adminTampered = 'The administrator copy of the script was changed before it could run, so it was not run: {0}. Shared shortcuts were left unchanged.'
        adminSkip     = 'Shared shortcuts skipped (-NoAdmin).'
        unsafePath    = 'The backup folder contains a junction or symbolic link, nothing is written through it: {0}'
        autostart     = 'Autostart entry: {0}'
        autostartOk   = 'Autostart entry already set up: {0}'
        handler       = 'Link handler: {0}'
        handlerOk     = 'Link handler already set up: {0}'
        started       = 'Chrome started with {0} (PID {1})'
        startedPlain  = 'Chrome started (PID {0})'
        startTimeout  = 'Chrome did not start within 15 seconds. Start it from a shortcut.'
        startFail     = 'Chrome is running, but without the region override. Close it and start it from a shortcut.'
        noLaunch      = 'Chrome was not started (-NoLaunch).'
        noLaunchAdmin = 'Chrome was not started: the script runs with administrator rights, and Chrome started from it would get them too. Start Chrome from a shortcut.'
        noBackup      = 'No backup in {0}: the script has not changed anything here yet, so there is nothing to restore.'
        restoreLocal  = 'Local State: Glic flags, interface language and country restored'
        restoreProfile = 'Profile {0}: languages restored'
        restoreShortcut = 'Shortcut restored: {0}'
        restoreShortcutOk = 'Shortcut already as before: {0}'
        restoreMissing = 'No longer exists, skipped: {0}'
        restoreAutostart = 'Autostart entry restored: {0}'
        restoreHandler = 'Link handler restored: {0}'
        restoreHandlerDeleted = 'Link handler copy removed: {0}'
        relaunch      = 'PowerShell 7 detected: restarting in Windows PowerShell 5.1...'
        needWinPS     = 'This script needs Windows PowerShell 5.1 (powershell.exe, built into Windows 10 and 11).'
        done          = 'Done. If Gemini does not appear, open chrome://version and check that "Command Line" contains --variations-override-country, and that chrome://flags/#glic is Enabled.'
        restoreDone   = 'Restore finished. Chrome uses your own languages and region again.'
        doneErrors    = 'Finished with errors, see the messages above.'
        undo          = 'How to undo: run chrome-gemini-unlock.bat -Restore (see "Undo" in README).'
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
        flagExpiry    = 'Срок флага {0} истёк после Chrome {1}, а установлен Chrome {2}: Chrome его игнорирует. Пока в chrome://flags есть #temporary-unexpire-flags-m{1}, его включение возвращает флаг.'
        confirmClose  = 'Google Chrome запущен и будет закрыт. Загрузки, звонки и неотправленные формы в Chrome будут прерваны.'
        confirmPrompt = 'Закрыть Chrome сейчас? [Y/N]'
        cancelled     = 'Отменено. Ничего не изменено.'
        needForce     = 'Не могу спросить перед закрытием Chrome: сеанс не интерактивный. Запустите скрипт с -Force. Ничего не изменено.'
        closing       = 'Закрываю Google Chrome...'
        closed        = 'Chrome закрыт'
        restoreHint   = 'Часть окон Chrome не закрылась штатно. Если при следующем запуске Chrome предложит восстановить страницы, нажмите «Восстановить» (Restore).'
        stillRunning  = 'chrome.exe всё ещё работает. Закройте Chrome вручную и запустите скрипт снова.'
        backup        = 'Резервные копии (состояние до первого запуска): {0}'
        localState    = 'Local State: флагов Glic: {0}, язык интерфейса en-US, страна {1}'
        agentOn       = 'Агентские функции включены (-Agent): Gemini может нажимать, вводить текст и заполнять формы на веб-страницах за вас. Следите за тем, что он делает.'
        agentOff      = 'Агентские функции выключены. Чтобы Gemini мог действовать на веб-страницах за вас, запустите скрипт с -Agent.'
        profile       = 'Профиль {0}: языки {1}'
        profileSkip   = 'Профиль {0}: нет файла Preferences, пропущен'
        shortcut      = 'Ярлык: {0}'
        shortcutOk    = 'Ярлык уже настроен: {0}'
        adminAsk      = 'Для общих ярлыков нужны права администратора; изменение затронет все учётные записи Windows на этом компьютере. Подтвердите запрос Windows (UAC) или откажитесь, чтобы их пропустить.'
        adminDeclined = 'Права администратора не получены, общие ярлыки не изменены.'
        adminNoRun    = 'Копия скрипта с правами администратора не запустилась (код выхода {0}), общие ярлыки не изменены. Запустите скрипт из папки на локальном диске или используйте -NoAdmin.'
        adminTampered = 'Копия скрипта для администратора была изменена до запуска, поэтому не запущена: {0}. Общие ярлыки не изменены.'
        adminSkip     = 'Общие ярлыки пропущены (-NoAdmin).'
        unsafePath    = 'В папке резервных копий есть точка соединения или символическая ссылка, запись через неё не выполняется: {0}'
        autostart     = 'Автозагрузка: {0}'
        autostartOk   = 'Автозагрузка уже настроена: {0}'
        handler       = 'Обработчик ссылок: {0}'
        handlerOk     = 'Обработчик ссылок уже настроен: {0}'
        started       = 'Chrome запущен с {0} (PID {1})'
        startedPlain  = 'Chrome запущен (PID {0})'
        startTimeout  = 'Chrome не запустился за 15 секунд. Запустите его с ярлыка.'
        startFail     = 'Chrome работает, но без подмены региона. Закройте его и запустите с ярлыка.'
        noLaunch      = 'Chrome не запускался (-NoLaunch).'
        noLaunchAdmin = 'Chrome не запущен: скрипт работает с правами администратора, и запущенный из него Chrome получил бы их тоже. Запустите Chrome с ярлыка.'
        noBackup      = 'В {0} нет резервной копии: скрипт здесь ещё ничего не менял, восстанавливать нечего.'
        restoreLocal  = 'Local State: флаги Glic, язык интерфейса и страна восстановлены'
        restoreProfile = 'Профиль {0}: языки восстановлены'
        restoreShortcut = 'Ярлык восстановлен: {0}'
        restoreShortcutOk = 'Ярлык уже в исходном виде: {0}'
        restoreMissing = 'Больше не существует, пропущено: {0}'
        restoreAutostart = 'Автозагрузка восстановлена: {0}'
        restoreHandler = 'Обработчик ссылок восстановлен: {0}'
        restoreHandlerDeleted = 'Копия обработчика ссылок удалена: {0}'
        relaunch      = 'Обнаружен PowerShell 7: перезапуск в Windows PowerShell 5.1...'
        needWinPS     = 'Скрипту нужен Windows PowerShell 5.1 (powershell.exe, встроен в Windows 10 и 11).'
        done          = 'Готово. Если Gemini не появился, откройте chrome://version и проверьте, что в строке "Command Line" есть --variations-override-country, а в chrome://flags/#glic стоит Enabled.'
        restoreDone   = 'Откат завершён. Chrome снова использует ваши языки и регион.'
        doneErrors    = 'Завершено с ошибками, см. сообщения выше.'
        undo          = 'Как откатить изменения: запустите chrome-gemini-unlock.bat -Restore (раздел «Откат» в README).'
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
        flagExpiry    = 'Le flag {0} a expiré après Chrome {1} et la version installée est Chrome {2} : Chrome l''ignore. Tant que chrome://flags/#temporary-unexpire-flags-m{1} existe, l''activer rétablit le flag.'
        confirmClose  = 'Google Chrome est en cours d''exécution et va être fermé. Les téléchargements, appels et formulaires non envoyés dans Chrome seront interrompus.'
        confirmPrompt = 'Fermer Chrome maintenant ? [O/N]'
        cancelled     = 'Annulé. Rien n''a été modifié.'
        needForce     = 'Impossible de demander avant de fermer Chrome dans une session non interactive. Lancez le script avec -Force. Rien n''a été modifié.'
        closing       = 'Fermeture de Google Chrome...'
        closed        = 'Chrome fermé'
        restoreHint   = 'Certaines fenêtres de Chrome ne se sont pas fermées normalement. Si Chrome propose de restaurer les pages au prochain démarrage, cliquez sur Restaurer (Restore).'
        stillRunning  = 'chrome.exe est toujours en cours d''exécution. Fermez Chrome manuellement et relancez le script.'
        backup        = 'Sauvegardes (état avant la première exécution) : {0}'
        localState    = 'Local State : {0} flags Glic, langue de l''interface en-US, pays {1}'
        agentOn       = 'Fonctions d''agent activées (-Agent) : Gemini peut cliquer, saisir du texte et remplir des formulaires sur les pages web à votre place. Surveillez ce qu''il fait.'
        agentOff      = 'Fonctions d''agent désactivées. Pour que Gemini puisse agir sur les pages web à votre place, lancez le script avec -Agent.'
        profile       = 'Profil {0} : langues {1}'
        profileSkip   = 'Profil {0} : pas de fichier Preferences, ignoré'
        shortcut      = 'Raccourci : {0}'
        shortcutOk    = 'Raccourci déjà configuré : {0}'
        adminAsk      = 'Les raccourcis communs nécessitent des droits d''administrateur ; la modification concerne tous les comptes Windows de ce PC. Confirmez la demande UAC de Windows, ou refusez pour les ignorer.'
        adminDeclined = 'Droits d''administrateur refusés, les raccourcis communs n''ont pas été modifiés.'
        adminNoRun    = 'La copie administrateur du script ne s''est pas exécutée (code de sortie {0}), les raccourcis communs n''ont pas été modifiés. Lancez le script depuis un dossier sur un disque local, ou utilisez -NoAdmin.'
        adminTampered = 'La copie administrateur du script a été modifiée avant son exécution, elle n''a donc pas été lancée : {0}. Les raccourcis communs n''ont pas été modifiés.'
        adminSkip     = 'Raccourcis communs ignorés (-NoAdmin).'
        unsafePath    = 'Le dossier de sauvegarde contient une jonction ou un lien symbolique, rien n''est écrit à travers : {0}'
        autostart     = 'Démarrage automatique : {0}'
        autostartOk   = 'Démarrage automatique déjà configuré : {0}'
        handler       = 'Gestionnaire de liens : {0}'
        handlerOk     = 'Gestionnaire de liens déjà configuré : {0}'
        started       = 'Chrome démarré avec {0} (PID {1})'
        startedPlain  = 'Chrome démarré (PID {0})'
        startTimeout  = 'Chrome n''a pas démarré en 15 secondes. Démarrez-le depuis un raccourci.'
        startFail     = 'Chrome fonctionne, mais sans le changement de région. Fermez-le et relancez-le depuis un raccourci.'
        noLaunch      = 'Chrome n''a pas été démarré (-NoLaunch).'
        noLaunchAdmin = 'Chrome n''a pas été démarré : le script s''exécute avec des droits d''administrateur, et un Chrome lancé par lui les aurait aussi. Démarrez Chrome depuis un raccourci.'
        noBackup      = 'Aucune sauvegarde dans {0} : le script n''a encore rien modifié ici, il n''y a rien à restaurer.'
        restoreLocal  = 'Local State : flags Glic, langue de l''interface et pays restaurés'
        restoreProfile = 'Profil {0} : langues restaurées'
        restoreShortcut = 'Raccourci restauré : {0}'
        restoreShortcutOk = 'Raccourci déjà dans son état d''origine : {0}'
        restoreMissing = 'N''existe plus, ignoré : {0}'
        restoreAutostart = 'Démarrage automatique restauré : {0}'
        restoreHandler = 'Gestionnaire de liens restauré : {0}'
        restoreHandlerDeleted = 'Copie du gestionnaire de liens supprimée : {0}'
        relaunch      = 'PowerShell 7 détecté : redémarrage dans Windows PowerShell 5.1...'
        needWinPS     = 'Ce script nécessite Windows PowerShell 5.1 (powershell.exe, intégré à Windows 10 et 11).'
        done          = 'Terminé. Si Gemini n''apparaît pas, ouvrez chrome://version et vérifiez que « Command Line » contient --variations-override-country, et que chrome://flags/#glic est sur Enabled.'
        restoreDone   = 'Restauration terminée. Chrome utilise de nouveau vos langues et votre région.'
        doneErrors    = 'Terminé avec des erreurs, voir les messages ci-dessus.'
        undo          = 'Pour annuler : lancez chrome-gemini-unlock.bat -Restore (voir la section « Annulation » du README).'
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
        flagExpiry    = 'Flag {0} ist nach Chrome {1} abgelaufen, installiert ist Chrome {2}: Chrome ignoriert es. Solange es chrome://flags/#temporary-unexpire-flags-m{1} gibt, holt dessen Aktivierung das Flag zurück.'
        confirmClose  = 'Google Chrome läuft und wird geschlossen. Downloads, Anrufe und nicht abgeschickte Formulareingaben in Chrome werden unterbrochen.'
        confirmPrompt = 'Chrome jetzt schließen? [J/N]'
        cancelled     = 'Abgebrochen. Es wurde nichts geändert.'
        needForce     = 'In einer nicht interaktiven Sitzung kann vor dem Schließen von Chrome nicht nachgefragt werden. Starten Sie das Skript mit -Force. Es wurde nichts geändert.'
        closing       = 'Google Chrome wird geschlossen...'
        closed        = 'Chrome geschlossen'
        restoreHint   = 'Einige Chrome-Fenster wurden nicht regulär geschlossen. Wenn Chrome beim nächsten Start anbietet, Seiten wiederherzustellen, klicken Sie auf Wiederherstellen (Restore).'
        stillRunning  = 'chrome.exe läuft noch. Schließen Sie Chrome manuell und starten Sie das Skript erneut.'
        backup        = 'Sicherungen (Zustand vor dem ersten Lauf): {0}'
        localState    = 'Local State: {0} Glic-Flags, Oberflächensprache en-US, Land {1}'
        agentOn       = 'Agent-Funktionen sind aktiv (-Agent): Gemini kann auf Webseiten für Sie klicken, tippen und Formulare ausfüllen. Behalten Sie im Blick, was es tut.'
        agentOff      = 'Agent-Funktionen sind aus. Damit Gemini auf Webseiten für Sie handeln kann, starten Sie das Skript mit -Agent.'
        profile       = 'Profil {0}: Sprachen {1}'
        profileSkip   = 'Profil {0}: keine Preferences-Datei, übersprungen'
        shortcut      = 'Verknüpfung: {0}'
        shortcutOk    = 'Verknüpfung bereits eingerichtet: {0}'
        adminAsk      = 'Verknüpfungen für alle Benutzer erfordern Administratorrechte; die Änderung betrifft jedes Windows-Konto auf diesem PC. Bestätigen Sie die UAC-Abfrage von Windows oder lehnen Sie ab, um sie zu überspringen.'
        adminDeclined = 'Keine Administratorrechte erteilt, gemeinsame Verknüpfungen wurden nicht geändert.'
        adminNoRun    = 'Die Administrator-Kopie des Skripts wurde nicht ausgeführt (Exitcode {0}), gemeinsame Verknüpfungen wurden nicht geändert. Starten Sie das Skript aus einem Ordner auf einem lokalen Laufwerk oder verwenden Sie -NoAdmin.'
        adminTampered = 'Die Administrator-Kopie des Skripts wurde vor dem Start verändert und deshalb nicht ausgeführt: {0}. Gemeinsame Verknüpfungen wurden nicht geändert.'
        adminSkip     = 'Gemeinsame Verknüpfungen übersprungen (-NoAdmin).'
        unsafePath    = 'Der Sicherungsordner enthält eine Verzweigung oder symbolische Verknüpfung, darüber wird nichts geschrieben: {0}'
        autostart     = 'Autostart-Eintrag: {0}'
        autostartOk   = 'Autostart-Eintrag bereits eingerichtet: {0}'
        handler       = 'Link-Handler: {0}'
        handlerOk     = 'Link-Handler bereits eingerichtet: {0}'
        started       = 'Chrome gestartet mit {0} (PID {1})'
        startedPlain  = 'Chrome gestartet (PID {0})'
        startTimeout  = 'Chrome ist nicht innerhalb von 15 Sekunden gestartet. Starten Sie es über eine Verknüpfung.'
        startFail     = 'Chrome läuft, aber ohne Regions-Override. Schließen Sie Chrome und starten Sie es über eine Verknüpfung.'
        noLaunch      = 'Chrome wurde nicht gestartet (-NoLaunch).'
        noLaunchAdmin = 'Chrome wurde nicht gestartet: Das Skript läuft mit Administratorrechten, und ein von ihm gestartetes Chrome hätte sie auch. Starten Sie Chrome über eine Verknüpfung.'
        noBackup      = 'Keine Sicherung in {0}: Das Skript hat hier noch nichts geändert, es gibt nichts wiederherzustellen.'
        restoreLocal  = 'Local State: Glic-Flags, Oberflächensprache und Land wiederhergestellt'
        restoreProfile = 'Profil {0}: Sprachen wiederhergestellt'
        restoreShortcut = 'Verknüpfung wiederhergestellt: {0}'
        restoreShortcutOk = 'Verknüpfung bereits im ursprünglichen Zustand: {0}'
        restoreMissing = 'Existiert nicht mehr, übersprungen: {0}'
        restoreAutostart = 'Autostart-Eintrag wiederhergestellt: {0}'
        restoreHandler = 'Link-Handler wiederhergestellt: {0}'
        restoreHandlerDeleted = 'Kopie des Link-Handlers entfernt: {0}'
        relaunch      = 'PowerShell 7 erkannt: Neustart in Windows PowerShell 5.1...'
        needWinPS     = 'Dieses Skript benötigt Windows PowerShell 5.1 (powershell.exe, in Windows 10 und 11 enthalten).'
        done          = 'Fertig. Falls Gemini nicht erscheint, öffnen Sie chrome://version und prüfen Sie, ob „Command Line“ --variations-override-country enthält und chrome://flags/#glic auf Enabled steht.'
        restoreDone   = 'Wiederherstellung abgeschlossen. Chrome verwendet wieder Ihre Sprachen und Region.'
        doneErrors    = 'Mit Fehlern beendet, siehe Meldungen oben.'
        undo          = 'Rückgängig machen: chrome-gemini-unlock.bat -Restore ausführen (siehe Abschnitt „Rückgängig machen“ in der README).'
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
    if (-not $LogFile) { return }
    # Only the elevated copy logs; it checks for a planted link before every write and stops if one appears
    try { Assert-NoLink $LogFile } catch { exit 4 }
    Add-Content -LiteralPath $LogFile -Value $Line -Encoding UTF8
}
function Ok([string]$m)   { Write-Host "[ OK ] $m" -ForegroundColor Green;  Write-LogLine "[ OK ] $m" }
function Note([string]$m) { Write-Host "       $m" -ForegroundColor Gray;   Write-LogLine "       $m" }
function Warn([string]$m) { Write-Host "[WARN] $m" -ForegroundColor Yellow; Write-LogLine "[WARN] $m" }
function Fail([string]$m) { Write-Host "[FAIL] $m" -ForegroundColor Red;    Write-LogLine "[FAIL] $m"; $script:HadErrors = $true }

# ---------------------------------------------------------------------------
# Windows PowerShell 5.1 only: JavaScriptSerializer below exists only in .NET Framework.
# PowerShell 7 hands the run over to powershell.exe with the same options.
# ---------------------------------------------------------------------------
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    $winPS = if ($env:SystemRoot) { Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
    if ($winPS -and $PSCommandPath -and (Test-Path -LiteralPath $winPS)) {
        $relaunch = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
        # Without it the relaunched copy could wait for an answer nobody can give
        if (@([Environment]::GetCommandLineArgs() | Where-Object { $_ -match '^[-/]noni' }).Count -or
            -not [Environment]::UserInteractive) { $relaunch += '-NonInteractive' }
        $relaunch += '-File', $PSCommandPath
        foreach ($p in $PSBoundParameters.GetEnumerator()) {
            if ($p.Value -is [switch]) { if ($p.Value) { $relaunch += "-$($p.Key)" } }
            else { $relaunch += "-$($p.Key)", [string]$p.Value }
        }
        Note (T 'relaunch')
        & $winPS @relaunch
        exit $LASTEXITCODE
    }
    Fail (T 'needWinPS')
    exit 1
}

# ---------------------------------------------------------------------------
# What the script changes
# ---------------------------------------------------------------------------
# The Gemini side panel and where its toolbar button and context menu entry appear
$BaseFlags = @(
    'glic@1',
    'glic-toolbar-height-side-panel@1',
    'glic-horizontal-tab-toolbar-button@1',
    'glic-toolbar-button-location@1',
    'glic-context-menu-below-search@1'
)
# Gemini acting on web pages for the user (clicking, typing, autofill, background tabs): -Agent only
$AgentFlags = @(
    'glic-actor@1',
    'enable-browser-actuator-for-glic-experimental-triggering@1',
    'glic-background-actuation@1',
    'glic-actor-autofill@1',
    'glic-actor-cursor@1',
    'glic-actor-script-tools@1'
)
$Flags = if ($Agent) { $BaseFlags + $AgentFlags } else { $BaseFlags }
# Every flag the script manages: a run without -Agent sets the agent flags back to Default
$ManagedFlags = @(($BaseFlags + $AgentFlags) | ForEach-Object { $_.Split('@')[0] })
# Expiry milestones from chrome/browser/flag-metadata.json of the Chrome 154-157 release branches,
# as @{ <first Chrome version> = <expiry milestone> }: Google sometimes extends a flag only after
# it has already expired in one version. Chrome ignores a flag after its expiry milestone.
$FlagExpiry = @{
    'glic'                                                     = @{ 154 = 160 }
    'glic-toolbar-height-side-panel'                           = @{ 154 = 160 }
    'glic-horizontal-tab-toolbar-button'                       = @{ 154 = 160 }
    'glic-toolbar-button-location'                             = @{ 154 = 160 }
    'glic-context-menu-below-search'                           = @{ 154 = 160 }
    'glic-actor'                                               = @{ 154 = 172 }
    'enable-browser-actuator-for-glic-experimental-triggering' = @{ 154 = 170 }
    'glic-background-actuation'                                = @{ 154 = 160 }
    'glic-actor-autofill'                                      = @{ 154 = 160 }
    'glic-actor-cursor'                                        = @{ 154 = 154; 156 = 160 }
    'glic-actor-script-tools'                                  = @{ 154 = 170 }
}
$Languages           = 'en-US,en'
$ProfileLanguageKeys = 'app_locale', 'accept_languages', 'selected_languages'
$OverrideArgs        = "--variations-override-country=$Country --lang=en-US"
$ChromeSub           = 'Google\Chrome\Application\chrome.exe'
$UserData            = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
$MySession           = (Get-Process -Id $PID).SessionId
$RunKey              = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunName             = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run'
# Only these keys are ever copied, exported or deleted under HKCU\Software\Classes
$HandlerKeyPattern   = '^HKCU\\Software\\Classes\\Chrome(HTML|PDF)(\.[^\\\s]+)?$'

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

# A missing backup reads as an empty object: every setting it would hold was absent
function Read-JsonOrEmpty([string]$Path) {
    if (Test-Path -LiteralPath $Path) { return Read-Json $Path }
    return [System.Collections.Generic.Dictionary[string,object]]::new()
}

function Write-Json([string]$Path, $Data) {
    $item = Get-Item -LiteralPath $Path
    # A read-only file is written anyway and made read-only again afterwards
    $wasReadOnly = $item.IsReadOnly
    if ($wasReadOnly) { $item.IsReadOnly = $false }
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
        if ($wasReadOnly) { (Get-Item -LiteralPath $Path).IsReadOnly = $true }
    }
}

function Get-Section($Dict, [string]$Key) {
    if (-not ($Dict[$Key] -is [System.Collections.IDictionary])) {
        # ::new() instead of New-Object: a PSObject-wrapped dictionary breaks Serialize()
        $Dict[$Key] = [System.Collections.Generic.Dictionary[string,object]]::new()
    }
    return $Dict[$Key]
}

# Sets $Target[$Key] to the original value, or removes the key if the original had none
function Copy-Setting($Target, $Source, [string]$Key) {
    if ($Source -is [System.Collections.IDictionary] -and $Source.ContainsKey($Key)) { $Target[$Key] = $Source[$Key] }
    elseif ($Target.ContainsKey($Key)) { $null = $Target.Remove($Key) }
}

# ---------------------------------------------------------------------------
# Chrome settings: what a run sets and what -Restore puts back
# ---------------------------------------------------------------------------
# The expiry milestone the given Chrome version ships for a flag (see $FlagExpiry)
function Get-FlagExpiry([string]$Name, [int]$ChromeMajor) {
    $table = $FlagExpiry[$Name]
    $versions = @($table.Keys | Sort-Object)
    $from = $versions[0]
    foreach ($v in $versions) { if ($v -le $ChromeMajor) { $from = $v } }
    return $table[$from]
}

# Entries of enabled_labs_experiments that belong to flags the script does not manage
function Get-ForeignFlags($Browser) {
    foreach ($e in @($Browser['enabled_labs_experiments'])) {
        if ($null -ne $e -and $ManagedFlags -notcontains ([string]$e).Split('@')[0]) { $e }
    }
}

function Set-LocalStateSettings($State) {
    $browser = Get-Section $State 'browser'
    # Every state of the managed flags is dropped first, so glic@2 does not fight with glic@1
    # and a run without -Agent sets the agent flags back to Default
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($e in Get-ForeignFlags $browser) { $list.Add($e) }
    foreach ($f in $Flags) { $list.Add($f) }
    $browser['enabled_labs_experiments'] = $list.ToArray()
    # On Windows the interface language is read from Local State, not from the profile
    (Get-Section $State 'intl')['app_locale'] = 'en-US'
    # Covers the experiments that use the permanent country, also when Chrome starts without the switch
    $State['variations_permanent_overridden_country'] = $Country
}

# Puts back only what Set-LocalStateSettings changes; everything Chrome saved since then is kept
function Restore-LocalStateSettings($State, $Original) {
    $browser = Get-Section $State 'browser'
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($e in Get-ForeignFlags $browser) { $list.Add($e) }
    if ($Original['browser'] -is [System.Collections.IDictionary]) {
        foreach ($e in @($Original['browser']['enabled_labs_experiments'])) {
            if ($null -ne $e -and $ManagedFlags -contains ([string]$e).Split('@')[0]) { $list.Add($e) }
        }
    }
    $browser['enabled_labs_experiments'] = $list.ToArray()
    Copy-Setting (Get-Section $State 'intl') $Original['intl'] 'app_locale'
    Copy-Setting $State $Original 'variations_permanent_overridden_country'
}

function Set-ProfileSettings($Prefs) {
    $intl = Get-Section $Prefs 'intl'
    $intl['app_locale']         = 'en-US'
    $intl['accept_languages']   = $Languages
    # Chrome rebuilds accept_languages from this list, so it has to change too
    $intl['selected_languages'] = $Languages
}

function Restore-ProfileSettings($Prefs, $Original) {
    $intl = Get-Section $Prefs 'intl'
    foreach ($k in $ProfileLanguageKeys) { Copy-Setting $intl $Original['intl'] $k }
}

# ---------------------------------------------------------------------------
# Backups: the state before the first run, saved once and never overwritten
# ---------------------------------------------------------------------------
if (-not $BackupDir) { $BackupDir = Join-Path $env:LOCALAPPDATA 'chrome-gemini-unlock\backup' }
$BackupDir = [System.IO.Path]::GetFullPath($BackupDir).TrimEnd('\')
$Manifest  = Join-Path $BackupDir 'manifest.txt'

# The elevated copy writes into this folder, which the user can change. A junction or symbolic
# link planted in it could send an administrator's write anywhere, so writing through one is refused.
function Assert-NoLink([string]$Path) {
    $stop = Split-Path -Parent $BackupDir
    for ($p = $Path; $p; $p = Split-Path -Parent $p) {
        # GetAttributes looks at the link itself, also when its target does not exist
        $attributes = 0
        try { $attributes = [System.IO.File]::GetAttributes($p) } catch { }
        if ($attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw (T 'unsafePath' $p) }
        if ($p -eq $stop) { break }
    }
}

function Test-Manifest([string]$Text) {
    if (-not (Test-Path -LiteralPath $Manifest)) { return $false }
    return ([System.IO.File]::ReadAllText($Manifest)).Contains($Text)
}

function Add-ManifestLine([string]$Line) {
    Assert-NoLink $Manifest
    Add-Content -LiteralPath $Manifest -Value $Line -Encoding UTF8
}

function Save-Backup([string]$Path, [string]$Name) {
    $dest = Join-Path $BackupDir $Name
    Assert-NoLink $dest
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

# The manifest written by Save-Backup and the registry steps, as objects for -Restore.
# Lines that do not look like the script's own entries are ignored, so an edited manifest
# can never make -Restore touch anything the script does not manage.
function Read-Manifest {
    if (-not (Test-Path -LiteralPath $Manifest)) { return }
    foreach ($line in [System.IO.File]::ReadAllLines($Manifest)) {
        if ($line -match '^\[registry\] created (\S+) ') {
            if ($Matches[1] -match $HandlerKeyPattern) { [pscustomobject]@{ Kind = 'CreatedKey'; Target = $Matches[0] } }
        } elseif ($line -match '^\[registry\] (\S+)  (GoogleChromeAutoLaunch\S*) = (.*)$') {
            if ($Matches[1] -eq $RunName) { [pscustomobject]@{ Kind = 'RunValue'; Name = $Matches[2]; Value = $Matches[3] } }
        } elseif ($line -match '^(.+?)  ->  (.+)$') {
            $name = $Matches[1]; $target = $Matches[2]
            # Backup names stay inside the backup folder: no '..', no '/' (Windows reads it as '\'), no drive
            if ($name -match '[/:]' -or $name -match '(^|\\)\.\.(\\|$)') { continue }
            $kind = $null
            if ($name -eq 'Local State' -and $target -like '*\Local State') { $kind = 'LocalState' }
            elseif ($name -like 'profiles\*\Preferences' -and $target -like '*\Preferences') { $kind = 'Profile' }
            elseif ($name -like 'shortcuts\*.lnk' -and $target -like '*.lnk') { $kind = 'Shortcut' }
            elseif ($name -like 'registry\handler-*.reg' -and $target -match $HandlerKeyPattern) { $kind = 'RegFile' }
            if ($kind) { [pscustomobject]@{ Kind = $kind; Target = $target; Backup = (Join-Path $BackupDir $name) } }
        }
    }
}

# ---------------------------------------------------------------------------
# Command lines
# ---------------------------------------------------------------------------
# A switch is removed together with its trailing spaces; tokens are split on spaces outside
# quotes, so quoted values stay byte for byte, even when they contain " --lang="
function Add-OverrideArgs([string]$Arguments) {
    $rest = [regex]::Replace($Arguments, '(?:"[^"]*"?|[^\s"])+\s*', {
            param($m)
            if ($m.Value -match '^"?--(?:variations-override-country|lang)=') { '' } else { $m.Value }
        }).Trim()
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

# reg.exe reports success on stderr; a separate process keeps that text out of PowerShell's error stream
function Invoke-Reg([string[]]$Arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo 'reg.exe'
    $psi.Arguments = ($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $null = $proc.StandardOutput.ReadToEndAsync()
    $err = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) { throw "reg $($Arguments[0]): $($err.Trim()) (exit code $($proc.ExitCode))" }
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

function Get-WShell {
    if (-not $script:WShell) { $script:WShell = New-Object -ComObject WScript.Shell }
    return $script:WShell
}

function Get-ChromeShortcuts($Dirs) {
    $shell = Get-WShell
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

function Test-SharedShortcut([string]$Path) {
    foreach ($d in $SystemShortcutDirs) {
        if ($d.Path -and $Path.StartsWith($d.Path.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Test-RestorePending($Entry) {
    if (-not (Test-Path -LiteralPath $Entry.Target) -or -not (Test-Path -LiteralPath $Entry.Backup)) { return $false }
    $shell = Get-WShell
    return $shell.CreateShortcut($Entry.Target).Arguments -cne $shell.CreateShortcut($Entry.Backup).Arguments
}

# A shortcut gets its original arguments back; its icon, pinning and name stay as they are now
function Restore-Shortcuts($Entries) {
    $shell = Get-WShell
    foreach ($e in $Entries) {
        try {
            if (-not (Test-Path -LiteralPath $e.Target)) { Note (T 'restoreMissing' $e.Target); continue }
            if (-not (Test-Path -LiteralPath $e.Backup)) { Warn (T 'restoreMissing' $e.Backup); continue }
            $link = $shell.CreateShortcut($e.Target)
            if ($link.TargetPath -notlike "*\$ChromeSub") { Note (T 'restoreMissing' $e.Target); continue }
            $original = $shell.CreateShortcut($e.Backup).Arguments
            if ($link.Arguments -ceq $original) { Ok (T 'restoreShortcutOk' $e.Target); continue }
            $link.Arguments = $original
            $link.Save()
            Ok (T 'restoreShortcut' $e.Target)
            Note $original
        } catch { Fail "$($e.Target): $($_.Exception.Message)" }
    }
}

# ---------------------------------------------------------------------------
# Administrator rights for the shortcuts shared by all users
# ---------------------------------------------------------------------------
function Test-IsAdmin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# EscapeSingleQuotedStringContent also doubles the typographic quotes PowerShell reads as ' (U+2018-U+201B)
function ConvertTo-PSLiteral([string]$Text) {
    return "'" + [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($Text) + "'"
}

function Get-Sha256Hex([byte[]]$Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    return -join ($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') })
}

# The command the elevated PowerShell runs: read the copy once, check its hash, run what was checked.
# The hash travels in the command line, which no other program can change once UAC shows it.
function New-ElevatedBootstrap([string]$Path, [string]$Hash, [string]$Arguments) {
    return @"
`$ErrorActionPreference = 'Stop'
`$b = [System.IO.File]::ReadAllBytes($(ConvertTo-PSLiteral $Path))
`$h = -join ([System.Security.Cryptography.SHA256]::Create().ComputeHash(`$b) | ForEach-Object { `$_.ToString('x2') })
if (`$h -ne '$Hash') { exit 3 }
`$t = (New-Object System.Text.UTF8Encoding(`$false)).GetString(`$b).TrimStart([char]0xFEFF)
& ([scriptblock]::Create(`$t)) $Arguments
exit `$LASTEXITCODE
"@
}

# Runs the shared-shortcut step in an elevated copy of this script. The copy sits in a folder the
# user can write to, so a program could swap it while the UAC prompt is open; the elevated side
# therefore runs it only if its SHA-256 matches the text this process runs.
function Invoke-ElevatedShortcuts {
    $log = Join-Path $BackupDir 'elevated.log'
    Assert-NoLink $log
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    $text = $ScriptText
    if (-not $text) { $text = [System.IO.File]::ReadAllText($PSCommandPath) }
    $bytes = $Utf8.GetBytes($text)
    # A local copy: an elevated process does not see mapped network or SUBST drives
    $copy = Join-Path $BackupDir 'elevated.ps1'
    Assert-NoLink $copy
    [System.IO.File]::WriteAllBytes($copy, $bytes)
    $arguments = "-SystemShortcutsOnly -Country $Country -BackupDir $(ConvertTo-PSLiteral $BackupDir) -LogFile $(ConvertTo-PSLiteral $log)"
    if ($Restore) { $arguments += ' -Restore' }
    $bootstrap = New-ElevatedBootstrap $copy (Get-Sha256Hex $bytes) $arguments
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($bootstrap))
    $proc = $null
    try {
        $proc = Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -Wait -PassThru `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
    } catch { Warn (T 'adminDeclined') }
    Remove-Item -LiteralPath $copy -Force -ErrorAction SilentlyContinue
    if (-not $proc) { return }
    $hasLog = (Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 0
    if ($hasLog) {
        foreach ($line in Get-Content -LiteralPath $log -Encoding UTF8) {
            $color = if ($line.StartsWith('[FAIL]')) { 'Red' } elseif ($line.StartsWith('[ OK ]')) { 'Green' } elseif ($line.StartsWith('[WARN]')) { 'Yellow' } else { 'Gray' }
            Write-Host $line -ForegroundColor $color
        }
    }
    if ($proc.ExitCode -eq 3) { Fail (T 'adminTampered' $copy) }
    elseif ($proc.ExitCode -ne 0) {
        if ($hasLog) { $script:HadErrors = $true } else { Fail (T 'adminNoRun' $proc.ExitCode) }
    }
}

# Elevated copy started by the main run: shared shortcuts only
if ($SystemShortcutsOnly) {
    # Nothing is logged through a planted link; the main run then reports the exit code
    try { Assert-NoLink $LogFile } catch { exit 4 }
    try {
        if ($Restore) {
            Restore-Shortcuts @(Read-Manifest | Where-Object { $_.Kind -eq 'Shortcut' -and (Test-SharedShortcut $_.Target) })
        } else {
            Update-Shortcuts @(Get-ChromeShortcuts $SystemShortcutDirs)
        }
    } catch { Fail $_.Exception.Message }
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

if ($Restore) {
    if (-not (Test-Path -LiteralPath $Manifest)) { Fail (T 'noBackup' $BackupDir); exit 1 }
} else {
    $chromeMajor = 0
    if ([string]$installs[0].Version -match '^(\d+)\.') { $chromeMajor = [int]$Matches[1] }
    foreach ($f in $Flags) {
        $name = $f.Split('@')[0]
        $expiry = Get-FlagExpiry $name $chromeMajor
        if ($chromeMajor -and $expiry -lt $chromeMajor) { Warn (T 'flagExpiry' $name $expiry $chromeMajor) }
    }
}

# ---- 1. Close Chrome: ask first, then ask every window to close, then end what is left
if (-not $Force -and @(Get-ChromeProcesses).Count) {
    Warn (T 'confirmClose')
    $answer = $null
    try { $answer = Read-Host (T 'confirmPrompt') } catch { Fail (T 'needForce'); exit 1 }
    if ([string]$answer -notmatch '^\s*(y|yes|д|да|o|oui|j|ja)\s*$') { Note (T 'cancelled'); exit 1 }
}

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Note (T 'backup' $BackupDir)

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

if ($Restore) {
    $entries = @(Read-Manifest)

    # ---- 2. Local State: the managed flags, interface language and stored country go back
    try {
        $state = Read-Json $localState
        Restore-LocalStateSettings $state (Read-JsonOrEmpty (Join-Path $BackupDir 'Local State'))
        Write-Json $localState $state
        Ok (T 'restoreLocal')
    } catch { Fail "Local State: $($_.Exception.Message)" }

    # ---- 3. Profiles: languages go back
    foreach ($e in @($entries | Where-Object { $_.Kind -eq 'Profile' })) {
        $label = '"' + (Split-Path -Leaf (Split-Path -Parent $e.Target)) + '"'
        try {
            if (-not (Test-Path -LiteralPath $e.Target)) { Note (T 'restoreMissing' $e.Target); continue }
            $data = Read-Json $e.Target
            Restore-ProfileSettings $data (Read-JsonOrEmpty $e.Backup)
            Write-Json $e.Target $data
            Ok (T 'restoreProfile' $label)
        } catch { Fail "$label : $($_.Exception.Message)" }
    }

    # ---- 4. Shortcuts of the current user
    $shortcutEntries = @($entries | Where-Object { $_.Kind -eq 'Shortcut' })
    try { Restore-Shortcuts @($shortcutEntries | Where-Object { -not (Test-SharedShortcut $_.Target) }) }
    catch { Fail $_.Exception.Message }

    # ---- 5. Shortcuts shared by all users (administrator rights)
    try {
        $shared  = @($shortcutEntries | Where-Object { Test-SharedShortcut $_.Target })
        $pending = @($shared | Where-Object { Test-RestorePending $_ })
        if ($pending.Count -eq 0) { Restore-Shortcuts $shared }
        elseif ($NoAdmin) { Warn (T 'adminSkip') }
        elseif (Test-IsAdmin) { Restore-Shortcuts $shared }
        else { Warn (T 'adminAsk'); Invoke-ElevatedShortcuts }
    } catch { Fail $_.Exception.Message }

    # ---- 6. Autostart entry: the original command goes back, if Chrome still has the entry
    try {
        $run = Get-Item -LiteralPath $RunKey -ErrorAction SilentlyContinue
        foreach ($e in @($entries | Where-Object { $_.Kind -eq 'RunValue' })) {
            if ($run -and $run.GetValueNames() -contains $e.Name) {
                Set-ItemProperty -LiteralPath $RunKey -Name $e.Name -Value $e.Value
                Ok (T 'restoreAutostart' $e.Name)
            } else { Note (T 'restoreMissing' "$RunName  $($e.Name)") }
        }
    } catch { Fail (T 'autostart' $_.Exception.Message) }

    # ---- 7. Link handlers: the per-user copy goes away, an exported original comes back
    try {
        foreach ($e in @($entries | Where-Object { $_.Kind -eq 'CreatedKey' })) {
            $key = 'HKCU:\' + $e.Target.Substring(5)
            if (Test-Path -LiteralPath $key) {
                Remove-Item -LiteralPath $key -Recurse -Force
                Ok (T 'restoreHandlerDeleted' $e.Target)
            }
        }
        foreach ($e in @($entries | Where-Object { $_.Kind -eq 'RegFile' })) {
            if (-not (Test-Path -LiteralPath $e.Backup)) { Warn (T 'restoreMissing' $e.Backup); continue }
            # The export holds the whole key: removing it first also drops subkeys the script added
            $key = 'HKCU:\' + $e.Target.Substring(5)
            if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force }
            Invoke-Reg 'import', $e.Backup
            Ok (T 'restoreHandler' $e.Target)
        }
    } catch { Fail (T 'handler' $_.Exception.Message) }
} else {
    # ---- 2. Local State: flags, interface language, stored country
    $state = $null
    try {
        Save-Backup $localState 'Local State'
        $state = Read-Json $localState
        Set-LocalStateSettings $state
        Write-Json $localState $state
        Ok (T 'localState' $Flags.Count $Country.ToUpperInvariant())
        if ($Agent) { Warn (T 'agentOn') } else { Note (T 'agentOff') }
    } catch { Fail "Local State: $($_.Exception.Message)" }

    # ---- 3. Profiles: en-US
    $profiles = @()
    if ($state -and $state['profile'] -is [System.Collections.IDictionary] -and
        $state['profile']['info_cache'] -is [System.Collections.IDictionary]) {
        foreach ($dir in $state['profile']['info_cache'].Keys) {
            $info = $state['profile']['info_cache'][$dir]
            $name = if ($info -is [System.Collections.IDictionary]) { [string]$info['name'] } else { '' }
            $profiles += [pscustomobject]@{ Dir = $dir; Name = $name }
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
            Set-ProfileSettings $data
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
        # -NoAdmin wins even when the script already runs elevated
        if ($pending.Count -eq 0) { Update-Shortcuts $shared }
        elseif ($NoAdmin) { Warn (T 'adminSkip') }
        elseif (Test-IsAdmin) { Update-Shortcuts $shared }
        else { Warn (T 'adminAsk'); Invoke-ElevatedShortcuts }
    } catch { Fail $_.Exception.Message }

    # ---- 6. Autostart entry (Chrome started in the background at Windows logon)
    try {
        $run = Get-Item -LiteralPath $RunKey -ErrorAction SilentlyContinue
        if ($run) {
            foreach ($name in $run.GetValueNames()) {
                if ($name -notlike 'GoogleChromeAutoLaunch*') { continue }
                $value = [string]$run.GetValue($name)
                if ($value -notlike "*\$ChromeSub*") { continue }
                $new = Add-OverrideToCommand $value
                if ($new -eq $value) { Ok (T 'autostartOk' $name); continue }
                $entry = "[registry] $RunName  $name = "
                if (-not (Test-Manifest $entry)) { Add-ManifestLine "$entry$value" }
                Set-ItemProperty -LiteralPath $RunKey -Name $name -Value $new
                Ok (T 'autostart' $name)
                Note $new
            }
        }
    } catch { Fail (T 'autostart' $_.Exception.Message) }

    # ---- 7. Link handlers (a link clicked in another program while Chrome is closed)
    try {
        $progIds = @()
        foreach ($hive in 'HKCU', 'HKLM') {
            $progIds += @(Get-ChildItem -Path "${hive}:\Software\Classes" -Name -ErrorAction SilentlyContinue |
                          Where-Object { "HKCU\Software\Classes\$_" -match $HandlerKeyPattern })
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
                    Assert-NoLink $reg
                    if (-not (Test-Manifest $created) -and -not (Test-Path -LiteralPath $reg)) {
                        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $reg) | Out-Null
                        Invoke-Reg 'export', "HKCU\Software\Classes\$id", $reg, '/y'
                        Add-ManifestLine "$regName  ->  HKCU\Software\Classes\$id"
                    }
                } else {
                    # A per-user copy of the machine-wide handler takes precedence over it
                    Invoke-Reg 'copy', "HKLM\Software\Classes\$id", "HKCU\Software\Classes\$id", '/s', '/f'
                    if (-not (Test-Manifest $created)) { Add-ManifestLine "$created(delete it to undo)" }
                }
                if (-not (Test-Path -LiteralPath $userCmd)) { New-Item -Path $userCmd -Force | Out-Null }
                Set-Item -LiteralPath $userCmd -Value $new
                Ok (T 'handler' $id)
                Note $new
            } catch { Fail "${id}: $($_.Exception.Message)" }
        }
    } catch { Fail (T 'handler' $_.Exception.Message) }
}

# ---- 8. Start Chrome and check its command line
if ($NoLaunch) {
    Note (T 'noLaunch')
} elseif (Test-IsAdmin) {
    # A Chrome started from an elevated script would run with administrator rights too
    Warn (T 'noLaunchAdmin')
} else {
    try {
        if ($Restore) { Start-Process -FilePath $chromeExe }
        else { Start-Process -FilePath $chromeExe -ArgumentList $OverrideArgs.Split(' ') }
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
        } elseif ($Restore) {
            Ok (T 'startedPlain' $main.ProcessId)
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
} elseif ($Restore) {
    Write-Host (T 'restoreDone') -ForegroundColor Cyan
} else {
    Write-Host (T 'done') -ForegroundColor Cyan
}
Note (T 'backup' $BackupDir)
if (-not $Restore) { Note (T 'undo') }
if ($script:HadErrors) { exit 2 }
exit 0
