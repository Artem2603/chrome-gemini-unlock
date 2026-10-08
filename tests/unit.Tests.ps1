# Unit tests for chrome-gemini-unlock.ps1: the logic that works on strings, dictionaries and files,
# without Chrome, the registry or WScript.Shell. Pester 5, on Windows PowerShell 5.1 or PowerShell 7.
#
#   Import-Module Pester -RequiredVersion 5.7.1
#   Invoke-Pester -Path tests/unit.Tests.ps1 -Output Detailed

BeforeDiscovery {
    $OnWindows = $PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $Agent = $false; $Country = 'us'; $Lang = 'en'
    . (Import-ScriptDefinitions)

    $OnWindows = $PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows
    $Override = '--variations-override-country=us --lang=en-US'
    # "Ivan" in Cyrillic: non-ASCII account, profile and shortcut names are common on Windows
    $Ivan = -join [char[]](0x0418, 0x0432, 0x0430, 0x043D)

    function Get-Labs($State) { return (@($State['browser']['enabled_labs_experiments']) -join ' | ') }

    # Directory link: a junction on Windows (no special rights needed), a symbolic link elsewhere
    function New-DirectoryLink([string]$Path, [string]$Target) {
        $type = if ($OnWindows) { 'Junction' } else { 'SymbolicLink' }
        $null = New-Item -ItemType $type -Path $Path -Target $Target
    }
}

Describe 'Add-OverrideArgs' {
    It '<Name>' -ForEach @(
        @{ Name = 'empty arguments get only the override'
           Arguments = ''
           Expected = '--variations-override-country=us --lang=en-US' }
        @{ Name = 'a quoted profile directory is kept as it is'
           Arguments = '--profile-directory="Profile 1"'
           Expected = '--variations-override-country=us --lang=en-US --profile-directory="Profile 1"' }
        @{ Name = 'old --lang= and --variations-override-country= at the start are replaced'
           Arguments = '--lang=de --variations-override-country=ru --new-window'
           Expected = '--variations-override-country=us --lang=en-US --new-window' }
        @{ Name = 'old switches in the middle and at the end are replaced, in any letter case'
           Arguments = '--a --LANG=de --b --Variations-Override-Country=RU'
           Expected = '--variations-override-country=us --lang=en-US --a --b' }
        @{ Name = 'a quoted "--lang=x" token is removed'
           Arguments = '"--lang=x" --foo "--variations-override-country=jp"'
           Expected = '--variations-override-country=us --lang=en-US --foo' }
        @{ Name = 'a --lang= switch with a quoted value is removed with its quotes'
           Arguments = '--lang="en GB" --foo'
           Expected = '--variations-override-country=us --lang=en-US --foo' }
        @{ Name = 'a quoted value containing " --lang=zz" stays byte for byte'
           Arguments = '--app="a  --lang=zz   b" --x'
           Expected = '--variations-override-country=us --lang=en-US --app="a  --lang=zz   b" --x' }
        @{ Name = 'a quoted argument containing " --variations-override-country=" stays'
           Arguments = '"C:\x --variations-override-country=de\y.html"'
           Expected = '--variations-override-country=us --lang=en-US "C:\x --variations-override-country=de\y.html"' }
        @{ Name = 'a glued foo--lang=x is not a switch and stays'
           Arguments = 'foo--lang=x'
           Expected = '--variations-override-country=us --lang=en-US foo--lang=x' }
        @{ Name = 'switches that only start like the override stay'
           Arguments = '--language=fr --langs=1 --variations-override-country-x=1'
           Expected = '--variations-override-country=us --lang=en-US --language=fr --langs=1 --variations-override-country-x=1' }
        @{ Name = 'spacing between the remaining arguments is kept, outer spaces are trimmed'
           Arguments = '  a   --lang=x    b  '
           Expected = '--variations-override-country=us --lang=en-US a   b' }
        @{ Name = 'tabs separate arguments too'
           Arguments = "a`t--lang=x`tb"
           Expected = "--variations-override-country=us --lang=en-US a`tb" }
        @{ Name = 'an unterminated quote runs to the end, as on the Windows command line'
           Arguments = 'a "b --lang=x'
           Expected = '--variations-override-country=us --lang=en-US a "b --lang=x' }
        @{ Name = 'only old override switches leave just the override'
           Arguments = '--lang=x --variations-override-country=de'
           Expected = '--variations-override-country=us --lang=en-US' }
    ) {
        Add-OverrideArgs $Arguments | Should -BeExactly $Expected
    }

    It 'is idempotent and keeps every other argument with its spacing (2500 seeded random command lines)' {
        $keep = @(
            '--profile-directory="Profile 1"', '--profile-directory=Default', '--new-window', '--incognito',
            '"https://example.com/?q=a b&lang=x"', '--app="a --lang=zz b"', '"--app=x --lang=zz"', 'foo--lang=x',
            '--language=fr', '--user-data-dir="C:\Users\A B\Chrome"', '""', 'x"y z"w', '%1', '--single-argument',
            '--', '/prefetch:5', ('--window-name="' + $Ivan + '"'), '--enable-features=A,B'
        )
        $drop = @(
            '--lang=de', '--LANG=fr-FR', '--lang="en GB"', '"--lang=x"', '"--lang=a b"', '--lang=',
            '--variations-override-country=ru', '--Variations-Override-Country=DE', '"--variations-override-country=jp"'
        )
        $separators = @(' ', '  ', "`t", " `t ")
        $rng = New-Object System.Random 20261008
        $failures = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt 2500; $i++) {
            $line = if ($rng.Next(4) -eq 0) { ' ' } else { '' }
            $kept = ''
            $n = $rng.Next(0, 9)
            for ($j = 0; $j -lt $n; $j++) {
                $isDrop = $rng.Next(3) -eq 0
                $token = if ($isDrop) { $drop[$rng.Next($drop.Count)] } else { $keep[$rng.Next($keep.Count)] }
                $sep = if ($j -lt $n - 1 -or $rng.Next(2) -eq 0) { $separators[$rng.Next($separators.Count)] } else { '' }
                $line += $token + $sep
                if (-not $isDrop) { $kept += $token + $sep }
            }
            $kept = $kept.Trim()
            $expected = if ($kept) { "$Override $kept" } else { $Override }
            $once = Add-OverrideArgs $line
            $twice = Add-OverrideArgs $once
            if ($once -cne $expected -or $twice -cne $once) { $failures.Add("[$line] -> [$once] -> [$twice]") }
        }
        $failures.Count | Should -Be 0 -Because (($failures | Select-Object -First 3) -join '; ')
    }
}

Describe 'Add-OverrideToCommand' {
    It '<Name>' -ForEach @(
        @{ Name = 'quoted path with spaces: the override goes before --single-argument %1'
           Command = '"C:\Program Files\Google\Chrome\Application\chrome.exe" --single-argument %1'
           Expected = '"C:\Program Files\Google\Chrome\Application\chrome.exe" --variations-override-country=us --lang=en-US --single-argument %1' }
        @{ Name = 'unquoted path with spaces gets quotes'
           Command = 'C:\Program Files\Google\Chrome\Application\chrome.exe --no-startup-window /prefetch:5'
           Expected = '"C:\Program Files\Google\Chrome\Application\chrome.exe" --variations-override-country=us --lang=en-US --no-startup-window /prefetch:5' }
        @{ Name = 'per-user Chrome in a folder with spaces, -- "%1" stays after the override'
           Command = 'C:\Users\John Smith\AppData\Local\Google\Chrome\Application\chrome.exe -- "%1"'
           Expected = '"C:\Users\John Smith\AppData\Local\Google\Chrome\Application\chrome.exe" --variations-override-country=us --lang=en-US -- "%1"' }
        @{ Name = 'an old override is replaced and --single-argument %1 stays last'
           Command = '"C:\Program Files\Google\Chrome\Application\chrome.exe" --lang=de --variations-override-country=ru --single-argument %1'
           Expected = '"C:\Program Files\Google\Chrome\Application\chrome.exe" --variations-override-country=us --lang=en-US --single-argument %1' }
        @{ Name = 'a path without spaces stays unquoted'
           Command = 'C:\Chrome\Application\chrome.exe --no-startup-window'
           Expected = 'C:\Chrome\Application\chrome.exe --variations-override-country=us --lang=en-US --no-startup-window' }
        @{ Name = 'an executable without arguments gets the override'
           Command = '"C:\Program Files\Google\Chrome\Application\chrome.exe"'
           Expected = '"C:\Program Files\Google\Chrome\Application\chrome.exe" --variations-override-country=us --lang=en-US' }
        @{ Name = 'an empty command stays empty'
           Command = ''
           Expected = '' }
    ) {
        $once = Add-OverrideToCommand $Command
        $once | Should -BeExactly $Expected
        Add-OverrideToCommand $once | Should -BeExactly $once
    }
}

Describe 'Set-LocalStateSettings' {
    BeforeAll {
        function New-RunState {
            return New-JsonDict @{
                browser = @{
                    enabled_labs_experiments = @('foo@1', 'glic@2', 'bar@3', 'glic-actor@1', 'glic-actor-cursor@2', 'baz')
                    has_seen_welcome_page    = $true
                }
                intl    = @{ app_locale = 'ru'; other = 'kept' }
                profile = @{ info_cache = @{ Default = @{ name = 'Person 1' } } }
                variations_permanent_overridden_country = 'ru'
            }
        }
    }

    It 'without -Agent: foreign flags stay in order, every state of a managed flag gives way to the base flags' {
        $Flags = $BaseFlags
        $state = New-RunState
        Set-LocalStateSettings $state
        Get-Labs $state | Should -BeExactly ((@('foo@1', 'bar@3', 'baz') + $BaseFlags) -join ' | ')
    }

    It 'with -Agent: the agent flags follow the base flags' {
        $Flags = $BaseFlags + $AgentFlags
        $state = New-RunState
        Set-LocalStateSettings $state
        Get-Labs $state | Should -BeExactly ((@('foo@1', 'bar@3', 'baz') + $BaseFlags + $AgentFlags) -join ' | ')
    }

    It 'a run without -Agent removes the agent flags an earlier -Agent run set' {
        $state = New-RunState
        $Flags = $BaseFlags + $AgentFlags
        Set-LocalStateSettings $state
        $Flags = $BaseFlags
        Set-LocalStateSettings $state
        Get-Labs $state | Should -BeExactly ((@('foo@1', 'bar@3', 'baz') + $BaseFlags) -join ' | ')
    }

    It 'is idempotent' -ForEach @(@{ WithAgent = $false }, @{ WithAgent = $true }) {
        $Flags = if ($WithAgent) { $BaseFlags + $AgentFlags } else { $BaseFlags }
        $state = New-RunState
        Set-LocalStateSettings $state
        $first = Get-Labs $state
        Set-LocalStateSettings $state
        Get-Labs $state | Should -BeExactly $first
        $state['intl']['app_locale'] | Should -BeExactly 'en-US'
        $state['variations_permanent_overridden_country'] | Should -BeExactly 'us'
    }

    It 'works on an empty Local State' {
        $Flags = $BaseFlags
        $state = [System.Collections.Generic.Dictionary[string,object]]::new()
        Set-LocalStateSettings $state
        Get-Labs $state | Should -BeExactly ($BaseFlags -join ' | ')
        $state['intl']['app_locale'] | Should -BeExactly 'en-US'
        $state['variations_permanent_overridden_country'] | Should -BeExactly 'us'
    }

    It 'sets the interface language and the stored country and leaves other settings alone' {
        $Flags = $BaseFlags
        $Country = 'de'
        $state = New-RunState
        Set-LocalStateSettings $state
        $state['intl']['app_locale'] | Should -BeExactly 'en-US'
        $state['variations_permanent_overridden_country'] | Should -BeExactly 'de'
        $state['intl']['other'] | Should -BeExactly 'kept'
        $state['browser']['has_seen_welcome_page'] | Should -BeTrue
        $state['profile']['info_cache']['Default']['name'] | Should -BeExactly 'Person 1'
    }

    It 'reads a single flag string as a list' {
        $Flags = $BaseFlags
        $state = New-JsonDict @{ browser = @{ enabled_labs_experiments = 'foo@1' } }
        Set-LocalStateSettings $state
        Get-Labs $state | Should -BeExactly ((@('foo@1') + $BaseFlags) -join ' | ')
    }
}

Describe 'Restore-LocalStateSettings' {
    BeforeAll {
        function New-Original {
            return New-JsonDict @{
                browser = @{ enabled_labs_experiments = @('foo@1', 'glic@2', 'old@1', 'glic-actor@1') }
                intl    = @{ app_locale = 'ru' }
                variations_permanent_overridden_country = 'ru'
            }
        }
    }

    It 'brings back the original managed flags, language and country; flags added after the run stay' {
        $Flags = $BaseFlags
        $state = New-Original
        Set-LocalStateSettings $state
        # After the run the user turns on another flag and turns off one of theirs; Chrome stores new settings
        $state['browser']['enabled_labs_experiments'] = @(@($state['browser']['enabled_labs_experiments']) | Where-Object { $_ -ne 'old@1' }) + 'later@1'
        $state['browser']['new_setting'] = 1
        Restore-LocalStateSettings $state (New-Original)
        Get-Labs $state | Should -BeExactly 'foo@1 | later@1 | glic@2 | glic-actor@1'
        $state['intl']['app_locale'] | Should -BeExactly 'ru'
        $state['variations_permanent_overridden_country'] | Should -BeExactly 'ru'
        $state['browser']['new_setting'] | Should -Be 1
    }

    It 'removes the language and the country when the original had none' {
        $Flags = $BaseFlags + $AgentFlags
        $original = @{ browser = @{ enabled_labs_experiments = @('foo@1') }; intl = @{ other = 'x' } }
        $state = New-JsonDict $original
        Set-LocalStateSettings $state
        Restore-LocalStateSettings $state (New-JsonDict $original)
        Get-Labs $state | Should -BeExactly 'foo@1'
        $state['intl'].ContainsKey('app_locale') | Should -BeFalse
        $state['intl']['other'] | Should -BeExactly 'x'
        $state.ContainsKey('variations_permanent_overridden_country') | Should -BeFalse
    }

    It 'with an empty original removes every managed flag and setting; foreign flags stay' {
        $Flags = $BaseFlags + $AgentFlags
        $state = New-JsonDict @{ browser = @{ enabled_labs_experiments = @('foo@1', 'glic@2') } }
        Set-LocalStateSettings $state
        Restore-LocalStateSettings $state ([System.Collections.Generic.Dictionary[string,object]]::new())
        Get-Labs $state | Should -BeExactly 'foo@1'
        $state['intl'].ContainsKey('app_locale') | Should -BeFalse
        $state.ContainsKey('variations_permanent_overridden_country') | Should -BeFalse
    }

    It 'a missing backup reads as an empty original' {
        $empty = Read-JsonOrEmpty (Join-Path $TestDrive 'no such file')
        $empty | Should -BeOfType ([System.Collections.Generic.Dictionary[string,object]])
        $empty.Count | Should -Be 0
    }

    It 'Set then Restore gives back the original (400 seeded random originals, with and without -Agent)' {
        $rng = New-Object System.Random 154
        $foreign = 'foo@1', 'bar@2', 'baz', 'enable-parallel-downloading@1', 'smooth-scrolling@2'
        $failures = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt 400; $i++) {
            $labs = New-Object System.Collections.Generic.List[object]
            foreach ($f in $foreign) { if ($rng.Next(2)) { $labs.Add($f) } }
            foreach ($m in $ManagedFlags) { if ($rng.Next(3) -eq 0) { $labs.Add($m + '@' + $rng.Next(3)) } }
            $labs = @($labs | Sort-Object { $rng.Next() })
            $original = @{ browser = @{ enabled_labs_experiments = [object[]]$labs } }
            switch ($rng.Next(3)) {
                0 { $original['intl'] = @{ app_locale = 'ru'; other = 1 } }
                1 { $original['intl'] = @{ other = 1 } }
            }
            if ($rng.Next(2)) { $original['variations_permanent_overridden_country'] = 'br' }
            $Flags = if ($rng.Next(2)) { $BaseFlags + $AgentFlags } else { $BaseFlags }

            $state = New-JsonDict $original
            Set-LocalStateSettings $state
            Restore-LocalStateSettings $state (New-JsonDict $original)

            $want = (@($labs) | Sort-Object) -join ' | '
            $got = (@($state['browser']['enabled_labs_experiments']) | Sort-Object) -join ' | '
            $wantLocale = if ($original['intl'] -and $original['intl'].ContainsKey('app_locale')) { 'ru' } else { '<none>' }
            $gotLocale = if ($state['intl'].ContainsKey('app_locale')) { $state['intl']['app_locale'] } else { '<none>' }
            $wantCountry = if ($original.ContainsKey('variations_permanent_overridden_country')) { 'br' } else { '<none>' }
            $gotCountry = if ($state.ContainsKey('variations_permanent_overridden_country')) { $state['variations_permanent_overridden_country'] } else { '<none>' }
            if ($got -cne $want -or $gotLocale -cne $wantLocale -or $gotCountry -cne $wantCountry) {
                $failures.Add("[$want] -> [$got], locale $gotLocale, country $gotCountry")
            }
        }
        $failures.Count | Should -Be 0 -Because (($failures | Select-Object -First 3) -join '; ')
    }
}

Describe 'Profile settings' {
    BeforeAll {
        function New-Prefs {
            return New-JsonDict @{
                intl    = @{ app_locale = 'ru'; accept_languages = 'ru-RU,ru'; selected_languages = 'ru-RU,ru'; charset_default = 'windows-1251' }
                browser = @{ window_placement = @{ left = 10 } }
            }
        }
    }

    It 'Set-ProfileSettings switches all three language keys to en-US and leaves the rest alone' {
        $prefs = New-Prefs
        Set-ProfileSettings $prefs
        $prefs['intl']['app_locale'] | Should -BeExactly 'en-US'
        $prefs['intl']['accept_languages'] | Should -BeExactly 'en-US,en'
        $prefs['intl']['selected_languages'] | Should -BeExactly 'en-US,en'
        $prefs['intl']['charset_default'] | Should -BeExactly 'windows-1251'
        $prefs['browser']['window_placement']['left'] | Should -Be 10
    }

    It 'Set-ProfileSettings works on empty Preferences' {
        $prefs = [System.Collections.Generic.Dictionary[string,object]]::new()
        Set-ProfileSettings $prefs
        @($prefs['intl'].Keys | Sort-Object) -join ',' | Should -BeExactly 'accept_languages,app_locale,selected_languages'
    }

    It 'Restore-ProfileSettings brings back the original keys and removes the ones the original lacked' {
        $original = New-JsonDict @{ intl = @{ accept_languages = 'ru-RU,ru'; selected_languages = 'ru-RU,ru' } }
        $prefs = New-Prefs
        Set-ProfileSettings $prefs
        $prefs['intl']['charset_default'] = 'utf-8'
        Restore-ProfileSettings $prefs $original
        $prefs['intl'].ContainsKey('app_locale') | Should -BeFalse
        $prefs['intl']['accept_languages'] | Should -BeExactly 'ru-RU,ru'
        $prefs['intl']['selected_languages'] | Should -BeExactly 'ru-RU,ru'
        $prefs['intl']['charset_default'] | Should -BeExactly 'utf-8'
        $prefs['browser']['window_placement']['left'] | Should -Be 10
    }

    It 'Restore-ProfileSettings with an original without intl removes all three keys' -ForEach @(
        @{ Original = @{} }, @{ Original = @{ intl = 'not a dictionary' } }
    ) {
        $prefs = New-Prefs
        Set-ProfileSettings $prefs
        Restore-ProfileSettings $prefs (New-JsonDict $Original)
        @($prefs['intl'].Keys) -join ',' | Should -BeExactly 'charset_default'
    }

    It 'Copy-Setting copies a key the source has, also a null value' {
        $target = New-JsonDict @{ a = 1 }
        Copy-Setting $target (New-JsonDict @{ a = 2; b = 3 }) 'a'
        $target['a'] | Should -Be 2
        $target.ContainsKey('b') | Should -BeFalse
        $source = [System.Collections.Generic.Dictionary[string,object]]::new()
        $source['a'] = $null
        Copy-Setting $target $source 'a'
        $target.ContainsKey('a') | Should -BeTrue
        $target['a'] | Should -BeNullOrEmpty
    }

    It 'Copy-Setting removes a key the source lacks or when the source is not a dictionary' -ForEach @(
        @{ Source = @{ b = 1 } }, @{ Source = $null }, @{ Source = 'text' }
    ) {
        $target = New-JsonDict @{ a = 1; c = 2 }
        Copy-Setting $target (New-JsonDict $Source) 'a'
        $target.ContainsKey('a') | Should -BeFalse
        $target['c'] | Should -Be 2
    }

    It 'Copy-Setting does nothing when neither side has the key' {
        $target = New-JsonDict @{ c = 2 }
        Copy-Setting $target @{} 'a'
        @($target.Keys) -join ',' | Should -BeExactly 'c'
    }
}

Describe 'Save-Backup and Test-Manifest' {
    BeforeEach {
        $BackupDir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $Manifest = Join-Path $BackupDir 'manifest.txt'
        $null = New-Item -ItemType Directory -Path $BackupDir
        $source = Join-Path $TestDrive 'Local State'
        [System.IO.File]::WriteAllText($source, 'v1')
    }

    It 'copies the file once, records it, and never overwrites the backup' {
        Save-Backup $source 'Local State'
        [System.IO.File]::ReadAllText((Join-Path $BackupDir 'Local State')) | Should -BeExactly 'v1'
        [System.IO.File]::WriteAllText($source, 'v2')
        Save-Backup $source 'Local State'
        [System.IO.File]::ReadAllText((Join-Path $BackupDir 'Local State')) | Should -BeExactly 'v1'
        @([System.IO.File]::ReadAllLines($Manifest)) -join "`n" | Should -BeExactly "Local State  ->  $source"
        Test-Manifest "Local State  ->  " | Should -BeTrue
        Test-Manifest '[registry]' | Should -BeFalse
    }

    It 'creates the folders of a nested backup name' {
        Save-Backup $source 'profiles\Profile 1\Preferences'
        Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $BackupDir 'profiles') 'Profile 1') 'Preferences') | Should -BeTrue
        Test-Manifest "profiles\Profile 1\Preferences  ->  $source" | Should -BeTrue
    }

    It 'Test-Manifest is false without a manifest' {
        Test-Manifest 'Local State' | Should -BeFalse
    }
}

Describe 'Read-Manifest' {
    BeforeAll {
        $UserDataWin = 'C:\Users\Ivan\AppData\Local\Google\Chrome\User Data'
        $AutoLaunch = '"C:\Program Files\Google\Chrome\Application\chrome.exe" --no-startup-window /prefetch:5'
        # The lines Save-Backup, the autostart step and the link handler step write
        $ValidLines = @(
            "Local State  ->  $UserDataWin\Local State"
            "profiles\Default\Preferences  ->  $UserDataWin\Default\Preferences"
            "profiles\Profile 1\Preferences  ->  $UserDataWin\Profile 1\Preferences"
            'shortcuts\0a1b2c3d\Google Chrome.lnk  ->  C:\Users\Ivan\Desktop\Google Chrome.lnk'
            'shortcuts\9f8e7d6c\Google Chrome.lnk  ->  C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk'
            "[registry] HKCU\Software\Microsoft\Windows\CurrentVersion\Run  GoogleChromeAutoLaunch_8E1D5D7F2B5C4A0E = $AutoLaunch"
            '[registry] created HKCU\Software\Classes\ChromeHTML (delete it to undo)'
            'registry\handler-ChromePDF.ABC123.reg  ->  HKCU\Software\Classes\ChromePDF.ABC123'
        )
        $HostileLines = @(
            "profiles\..\..\..\..\Windows\Preferences  ->  $UserDataWin\Default\Preferences"
            'shortcuts\..\..\evil.lnk  ->  C:\Users\Ivan\Desktop\Google Chrome.lnk'
            '..\..\Windows\System32\config\SAM  ->  C:\Users\Ivan\Desktop\Google Chrome.lnk'
            'registry\handler-x\..\..\..\evil.reg  ->  HKCU\Software\Classes\ChromeHTML'
            '[registry] created HKCU\Software\Classes\Foo (delete it to undo)'
            '[registry] created HKCU\Software\Classes\ChromeHTML\shell (delete it to undo)'
            '[registry] created HKCU\Software\Classes\ChromeHTML.x\..\..\Microsoft (delete it to undo)'
            '[registry] created HKCU\Software\Classes\ChromeHTML'
            '[registry] HKCU\Software\Microsoft\Windows\CurrentVersion\Run  OneDrive = "C:\evil.exe"'
            '[registry] HKLM\Software\Microsoft\Windows\CurrentVersion\Run  GoogleChromeAutoLaunch_1 = "C:\evil.exe"'
            '[registry] HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce  GoogleChromeAutoLaunch_1 = "C:\evil.exe"'
            'registry\handler-Foo.reg  ->  HKCU\Software\Classes\Foo'
            'registry\handler-ChromeHTML.reg  ->  HKLM\Software\Classes\ChromeHTML'
            'evil.reg  ->  HKCU\Software\Classes\ChromeHTML'
            'Local State  ->  C:\Windows\win.ini'
            'profiles\Default\Preferences  ->  C:\Windows\system.ini'
            'shortcuts\0a1b2c3d\x.lnk  ->  C:\Windows\notepad.exe'
            'Local State ->  C:\x\Local State'
            'hello world', '', '   ', '  ->  ', '->', '[registry]', '[registry] created'
        )

        function Write-Manifest([string[]]$Lines, [bool]$Bom) {
            $text = ($Lines -join "`r`n") + "`r`n"
            [System.IO.File]::WriteAllText($Manifest, $text, (New-Object System.Text.UTF8Encoding($Bom)))
        }
        # Backup paths are Windows style in the names; compare them with either separator
        function Format-Entry($e) {
            $backup = if ($e.Backup) { $e.Backup -replace '[\\/]', '/' } else { '' }
            return '{0}|{1}|{2}|{3}|{4}' -f $e.Kind, $e.Target, $e.Name, $e.Value, $backup
        }
        function Get-ExpectedEntries {
            $bk = $BackupDir -replace '[\\/]', '/'
            return @(
                "LocalState|$UserDataWin\Local State|||$bk/Local State"
                "Profile|$UserDataWin\Default\Preferences|||$bk/profiles/Default/Preferences"
                "Profile|$UserDataWin\Profile 1\Preferences|||$bk/profiles/Profile 1/Preferences"
                "Shortcut|C:\Users\Ivan\Desktop\Google Chrome.lnk|||$bk/shortcuts/0a1b2c3d/Google Chrome.lnk"
                "Shortcut|C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk|||$bk/shortcuts/9f8e7d6c/Google Chrome.lnk"
                "RunValue||GoogleChromeAutoLaunch_8E1D5D7F2B5C4A0E|$AutoLaunch|"
                'CreatedKey|HKCU\Software\Classes\ChromeHTML|||'
                "RegFile|HKCU\Software\Classes\ChromePDF.ABC123|||$bk/registry/handler-ChromePDF.ABC123.reg"
            )
        }
    }

    BeforeEach {
        $BackupDir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $Manifest = Join-Path $BackupDir 'manifest.txt'
        $null = New-Item -ItemType Directory -Path $BackupDir
    }

    It 'returns nothing without a manifest' {
        @(Read-Manifest).Count | Should -Be 0
    }

    It 'reads every kind of entry the script writes' {
        Write-Manifest $ValidLines $false
        @(Read-Manifest | ForEach-Object { Format-Entry $_ }) -join "`n" | Should -BeExactly ((Get-ExpectedEntries) -join "`n")
    }

    It 'ignores lines that do not look like the script''s own entries' {
        $mixed = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt [Math]::Max($ValidLines.Count, $HostileLines.Count); $i++) {
            if ($i -lt $HostileLines.Count) { $mixed.Add($HostileLines[$i]) }
            if ($i -lt $ValidLines.Count) { $mixed.Add($ValidLines[$i]) }
        }
        Write-Manifest $mixed.ToArray() $false
        @(Read-Manifest | ForEach-Object { Format-Entry $_ }) -join "`n" | Should -BeExactly ((Get-ExpectedEntries) -join "`n")
    }

    It 'ignores backup names that climb out of the backup folder with forward slashes' {
        # Windows accepts / as a separator, so these backup paths would point outside the backup folder
        Write-Manifest @(
            "profiles\x/../../../../Windows\Preferences  ->  $UserDataWin\Default\Preferences"
            'shortcuts\x/../../../evil.lnk  ->  C:\Users\Ivan\Desktop\Google Chrome.lnk'
            'registry\handler-x/../../../evil.reg  ->  HKCU\Software\Classes\ChromeHTML'
        ) $false
        @(Read-Manifest | ForEach-Object { Format-Entry $_ }) | Should -BeNullOrEmpty
    }

    It 'reads a manifest that starts with a UTF-8 byte order mark, non-ASCII names included' {
        $lnk = "$Ivan.lnk"
        Write-Manifest (@("shortcuts\0a1b2c3d\$lnk  ->  C:\Users\$Ivan\Desktop\$lnk") + $ValidLines) $true
        [System.IO.File]::ReadAllBytes($Manifest)[0..2] -join ',' | Should -Be '239,187,191'
        $entries = @(Read-Manifest)
        $entries.Count | Should -Be ($ValidLines.Count + 1)
        Format-Entry $entries[0] | Should -BeExactly ("Shortcut|C:\Users\$Ivan\Desktop\$lnk|||" + ($BackupDir -replace '[\\/]', '/') + "/shortcuts/0a1b2c3d/$lnk")
        Format-Entry $entries[1] | Should -BeExactly (Get-ExpectedEntries)[0]
    }

    It 'reads what Add-ManifestLine writes (Add-Content -Encoding UTF8: with a BOM in Windows PowerShell)' {
        foreach ($line in $ValidLines) { Add-ManifestLine $line }
        @(Read-Manifest | ForEach-Object { Format-Entry $_ }) -join "`n" | Should -BeExactly ((Get-ExpectedEntries) -join "`n")
    }
}

Describe 'Assert-NoLink' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $local = Join-Path $root 'LocalAppData'
        $BackupDir = Join-Path (Join-Path $local 'chrome-gemini-unlock') 'backup'
        $Manifest = Join-Path $BackupDir 'manifest.txt'
        $outside = Join-Path $root 'outside'
        $null = New-Item -ItemType Directory -Path $outside
    }

    It 'lets ordinary paths through, existing or not' {
        $null = New-Item -ItemType Directory -Path (Join-Path $BackupDir 'registry')
        [System.IO.File]::WriteAllText($Manifest, 'x')
        { Assert-NoLink $Manifest } | Should -Not -Throw
        { Assert-NoLink (Join-Path (Join-Path $BackupDir 'registry') 'handler-ChromeHTML.reg') } | Should -Not -Throw
        { Assert-NoLink (Join-Path (Join-Path (Join-Path $BackupDir 'shortcuts') '0a1b2c3d') 'Google Chrome.lnk') } | Should -Not -Throw
        { Assert-NoLink $BackupDir } | Should -Not -Throw
    }

    It 'lets paths through when the backup folder does not exist yet' {
        { Assert-NoLink $Manifest } | Should -Not -Throw
    }

    It 'refuses a path below a directory link inside the backup folder' {
        $null = New-Item -ItemType Directory -Path $BackupDir
        $link = Join-Path $BackupDir 'shortcuts'
        New-DirectoryLink $link $outside
        $err = $null
        try { Assert-NoLink (Join-Path (Join-Path $link '0a1b2c3d') 'Google Chrome.lnk') } catch { $err = $_.Exception.Message }
        $err | Should -BeExactly (T 'unsafePath' $link)
    }

    It 'refuses a dangling file link' {
        $null = New-Item -ItemType Directory -Path $BackupDir
        try { $null = New-Item -ItemType SymbolicLink -Path $Manifest -Target (Join-Path $outside 'planted.txt') -ErrorAction Stop }
        catch { Set-ItResult -Skipped -Because "a symbolic link cannot be created here: $($_.Exception.Message)" }
        Test-Path -LiteralPath (Join-Path $outside 'planted.txt') | Should -BeFalse
        $err = $null
        try { Assert-NoLink $Manifest } catch { $err = $_.Exception.Message }
        $err | Should -BeExactly (T 'unsafePath' $Manifest)
    }

    It 'refuses when the backup folder itself is a link' {
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $BackupDir)
        New-DirectoryLink $BackupDir $outside
        $err = $null
        try { Assert-NoLink $Manifest } catch { $err = $_.Exception.Message }
        $err | Should -BeExactly (T 'unsafePath' $BackupDir)
    }

    It 'refuses when the folder holding the backup folder is a link' {
        $null = New-Item -ItemType Directory -Path (Join-Path $outside 'backup')
        $null = New-Item -ItemType Directory -Path $local
        $parent = Split-Path -Parent $BackupDir
        New-DirectoryLink $parent $outside
        $err = $null
        try { Assert-NoLink $Manifest } catch { $err = $_.Exception.Message }
        $err | Should -BeExactly (T 'unsafePath' $parent)
    }

    It 'does not look above the folder holding the backup folder' {
        $real = Join-Path $root 'real-local'
        $null = New-Item -ItemType Directory -Path (Join-Path (Join-Path $real 'chrome-gemini-unlock') 'backup')
        New-DirectoryLink $local $real
        { Assert-NoLink $Manifest } | Should -Not -Throw
    }

    It 'Add-ManifestLine writes nothing through a dangling manifest link' {
        $null = New-Item -ItemType Directory -Path $BackupDir
        $planted = Join-Path $outside 'planted.txt'
        try { $null = New-Item -ItemType SymbolicLink -Path $Manifest -Target $planted -ErrorAction Stop }
        catch { Set-ItResult -Skipped -Because "a symbolic link cannot be created here: $($_.Exception.Message)" }
        { Add-ManifestLine 'Local State  ->  C:\x\Local State' } | Should -Throw
        Test-Path -LiteralPath $planted | Should -BeFalse
    }

    It 'Save-Backup copies nothing through a linked folder' {
        $null = New-Item -ItemType Directory -Path $BackupDir
        New-DirectoryLink (Join-Path $BackupDir 'shortcuts') $outside
        $source = Join-Path $root 'Google Chrome.lnk'
        [System.IO.File]::WriteAllText($source, 'lnk')
        { Save-Backup $source 'shortcuts\0a1b2c3d\Google Chrome.lnk' } | Should -Throw
        @(Get-ChildItem -LiteralPath $outside -Recurse -Force).Count | Should -Be 0
        Test-Path -LiteralPath $Manifest | Should -BeFalse
    }
}

Describe 'Elevated bootstrap' {
    BeforeAll {
        # A folder name with a space, an apostrophe and Cyrillic letters, like C:\Users\<name>\AppData\Local
        $dir = Join-Path $TestDrive ("it's a dir " + $Ivan)
        $null = New-Item -ItemType Directory -Path $dir
        $copy = Join-Path $dir 'elevated.ps1'
        $received = Join-Path $dir 'received.txt'
        $log = Join-Path $dir 'elevated.log'
        $fake = @(
            '#Requires -Version 5.1'
            '[CmdletBinding()] param([switch]$SystemShortcutsOnly,[string]$Country,[string]$BackupDir,[string]$LogFile,[switch]$Restore)'
            '# padding: A'
            ('$out = ' + (ConvertTo-PSLiteral $received))
            '$lines = @("SystemShortcutsOnly=$SystemShortcutsOnly", "Country=$Country", "BackupDir=$BackupDir", "LogFile=$LogFile", "Restore=$Restore")'
            '[System.IO.File]::WriteAllLines($out, [string[]]$lines, (New-Object System.Text.UTF8Encoding($false)))'
            'exit 5'
        ) -join "`r`n"
        # Starts with a byte order mark, as an editor might save it
        $CopyBytes = [byte[]](@(0xEF, 0xBB, 0xBF) + @((New-Object System.Text.UTF8Encoding($false)).GetBytes($fake)))
        $CopyHash = Get-Sha256Hex $CopyBytes
        $exe = (Get-Process -Id $PID).Path
        $arguments = "-SystemShortcutsOnly -Country de -BackupDir $(ConvertTo-PSLiteral $dir) -LogFile $(ConvertTo-PSLiteral $log)"

        function Invoke-Bootstrap([string]$Arguments) {
            $bootstrap = New-ElevatedBootstrap $copy $CopyHash $Arguments
            $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($bootstrap))
            $null = & $exe -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1
            return $LASTEXITCODE
        }
    }

    BeforeEach {
        [System.IO.File]::WriteAllBytes($copy, $CopyBytes)
        if (Test-Path -LiteralPath $received) { Remove-Item -LiteralPath $received -Force }
    }

    It 'runs the verified copy with the arguments it was given' {
        Invoke-Bootstrap $arguments | Should -Be 5
        @([System.IO.File]::ReadAllLines($received)) -join "`n" | Should -BeExactly (@(
            'SystemShortcutsOnly=True', 'Country=de', "BackupDir=$dir", "LogFile=$log", 'Restore=False'
        ) -join "`n")
    }

    It 'passes -Restore on' {
        Invoke-Bootstrap "$arguments -Restore" | Should -Be 5
        @([System.IO.File]::ReadAllLines($received))[4] | Should -BeExactly 'Restore=True'
    }

    It 'refuses a copy changed after hashing (exit code 3) and does not run it' {
        $changed = [byte[]]$CopyBytes.Clone()
        $at = [System.Text.Encoding]::ASCII.GetString($changed).IndexOf('padding: A') + 'padding: '.Length
        $changed[$at] = [byte][char]'B'
        [System.IO.File]::WriteAllBytes($copy, $changed)
        Invoke-Bootstrap $arguments | Should -Be 3
        Test-Path -LiteralPath $received | Should -BeFalse
    }

    It 'Get-Sha256Hex gives lowercase hex SHA-256' {
        Get-Sha256Hex ([byte[]]@()) | Should -BeExactly 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
        Get-Sha256Hex ([System.Text.Encoding]::ASCII.GetBytes('abc')) | Should -BeExactly 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
        Get-Sha256Hex $CopyBytes | Should -BeExactly (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    It 'ConvertTo-PSLiteral round-trips quotes, dollars, backticks and empty text' {
        foreach ($text in @("it's", "a''b", '$env:PATH `n "x" $(1)', '', "C:\Users\O'Brien\AppData\Local")) {
            & ([scriptblock]::Create((ConvertTo-PSLiteral $text))) | Should -BeExactly $text
        }
    }

    It 'ConvertTo-PSLiteral round-trips every character PowerShell reads as a single quote' {
        # PowerShell ends a single-quoted string at U+2018, U+2019, U+201A and U+201B as well as at '
        foreach ($code in 0x2018, 0x2019, 0x201A, 0x201B) {
            $text = "C:\Users\O" + [char]$code + "Brien\AppData\Local"
            $result = try { & ([scriptblock]::Create((ConvertTo-PSLiteral $text))) } catch { "<parse error: $($_.Exception.Message)>" }
            $result | Should -BeExactly $text -Because ('U+{0:X4}' -f $code)
        }
    }
}

Describe 'Messages and T' {
    BeforeAll {
        function Get-Placeholders([string]$Text) {
            return (@([regex]::Matches($Text, '\{(\d+)[^}]*\}') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique) -join ',')
        }
        $ast = Get-ScriptAst
        $TCalls = @($ast.FindAll({
            param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'T'
        }, $true))
    }

    It 'has the four languages' {
        @($Messages.Keys | Sort-Object) -join ',' | Should -BeExactly 'de,en,fr,ru'
    }

    It '<Language> has exactly the English keys, the same placeholders, and no empty text' -ForEach @(
        @{ Language = 'ru' }, @{ Language = 'fr' }, @{ Language = 'de' }
    ) {
        $en = $Messages['en']
        $other = $Messages[$Language]
        @(Compare-Object @($en.Keys) @($other.Keys) -CaseSensitive | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) | Should -BeNullOrEmpty
        foreach ($key in $en.Keys) {
            Get-Placeholders $other[$key] | Should -BeExactly (Get-Placeholders $en[$key]) -Because "$Language.$key"
            $other[$key].Trim() | Should -Not -BeNullOrEmpty -Because "$Language.$key"
        }
    }

    It 'every message with placeholders formats without error in every language' {
        foreach ($language in $Messages.Keys) {
            foreach ($key in $Messages[$language].Keys) {
                $text = $Messages[$language][$key]
                $count = @([regex]::Matches($text, '\{(\d+)[^}]*\}') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Descending)[0]
                if ($null -eq $count) { continue }
                $values = @(0..$count | ForEach-Object { "v$_" })
                { $null = $text -f $values } | Should -Not -Throw -Because "$language.$key"
            }
        }
    }

    It 'every literal T call names an existing key with as many arguments as the text has placeholders' {
        $literal = @($TCalls | Where-Object { $_.CommandElements[1] -is [System.Management.Automation.Language.StringConstantExpressionAst] })
        $literal.Count | Should -BeGreaterThan 50
        foreach ($call in $literal) {
            $key = $call.CommandElements[1].Value
            $where = "line $($call.Extent.StartLineNumber): $($call.Extent.Text)"
            $Messages['en'].ContainsKey($key) | Should -BeTrue -Because $where
            $placeholders = Get-Placeholders $Messages['en'][$key]
            $needed = if ($placeholders) { [int]($placeholders.Split(',')[-1]) + 1 } else { 0 }
            ($call.CommandElements.Count - 2) | Should -Be $needed -Because $where
        }
    }

    It 'every message is used; the only computed key is scope + System/User' {
        $computed = @($TCalls | Where-Object { $_.CommandElements[1] -isnot [System.Management.Automation.Language.StringConstantExpressionAst] })
        @($computed | ForEach-Object { $_.Extent.Text }) -join "`n" | Should -BeExactly "T ('scope' + `$installs[0].Scope)"
        $used = @($TCalls | ForEach-Object { $_.CommandElements[1] } |
                  Where-Object { $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] } |
                  ForEach-Object { $_.Value }) + 'scopeSystem', 'scopeUser'
        @($Messages['en'].Keys | Where-Object { $used -notcontains $_ }) | Should -BeNullOrEmpty
    }

    It 'T formats its arguments into the current language' {
        $Lang = 'en'
        T 'found' 'C:\x\chrome.exe' | Should -BeExactly 'Google Chrome found: C:\x\chrome.exe'
        T 'flagExpiry' 'glic' 160 161 | Should -BeExactly ($Messages['en']['flagExpiry'] -f 'glic', 160, 161)
        $Lang = 'de'
        T 'found' 'C:\x\chrome.exe' | Should -BeExactly ($Messages['de']['found'] -f 'C:\x\chrome.exe')
    }

    It 'T falls back to English for a key the current language lacks' {
        $Messages = @{ en = @{ only = 'English {0}' }; ru = @{} }
        $Lang = 'ru'
        T 'only' 'x' | Should -BeExactly 'English x'
    }

    It 'a UI language <UiLanguage> selects <Expected>' -ForEach @(
        @{ UiLanguage = 'ja'; Expected = 'en' }, @{ UiLanguage = 'iv'; Expected = 'en' }, @{ UiLanguage = ''; Expected = 'en' },
        @{ UiLanguage = 'ru'; Expected = 'ru' }, @{ UiLanguage = 'fr'; Expected = 'fr' }, @{ UiLanguage = 'de'; Expected = 'de' }
    ) {
        # The script's own two statements that pick $Lang, run against a stand-in Get-UICulture
        $statements = @((Get-ScriptAst).EndBlock.Statements)
        $at = -1
        for ($i = 0; $i -lt $statements.Count; $i++) {
            $st = $statements[$i]
            if ($st -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $st.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $st.Left.VariablePath.UserPath -eq 'Lang') { $at = $i; break }
        }
        $at | Should -BeGreaterThan -1
        $select = [scriptblock]::Create($statements[$at].Extent.Text + "`n" + $statements[$at + 1].Extent.Text)
        function Get-UICulture { [pscustomobject]@{ TwoLetterISOLanguageName = $UiLanguage } }
        $Lang = $null
        . $select
        $Lang | Should -BeExactly $Expected
        T 'title' | Should -BeExactly $Messages[$Expected]['title']
    }
}

Describe 'Flag tables' {
    It 'has 5 base flags and 6 agent flags, every one set to @1' {
        $BaseFlags.Count | Should -Be 5
        $AgentFlags.Count | Should -Be 6
        @(($BaseFlags + $AgentFlags) | Where-Object { $_ -notmatch '^[a-z0-9-]+@1$' }) | Should -BeNullOrEmpty
    }

    It 'base and agent flags do not overlap' {
        $base = @($BaseFlags | ForEach-Object { $_.Split('@')[0] })
        @($AgentFlags | Where-Object { $base -contains $_.Split('@')[0] }) | Should -BeNullOrEmpty
    }

    It 'ManagedFlags holds the 11 names of the base and agent flags' {
        $ManagedFlags.Count | Should -Be 11
        @($ManagedFlags | Sort-Object -Unique).Count | Should -Be 11
        $ManagedFlags -join ',' | Should -BeExactly (@(($BaseFlags + $AgentFlags) | ForEach-Object { $_.Split('@')[0] }) -join ',')
    }

    It 'FlagExpiry has milestones for exactly the managed flags' {
        @(Compare-Object @($FlagExpiry.Keys) $ManagedFlags -CaseSensitive) | Should -BeNullOrEmpty
        foreach ($name in $ManagedFlags) {
            $FlagExpiry[$name] | Should -BeOfType ([hashtable]) -Because $name
            foreach ($from in $FlagExpiry[$name].Keys) {
                $from | Should -BeOfType ([int]) -Because $name
                $FlagExpiry[$name][$from] | Should -BeGreaterThan 100 -Because $name
            }
        }
    }

    It 'Get-FlagExpiry picks the milestone the given Chrome version ships' {
        # glic-actor-cursor: expiry 154 in the Chrome 154 and 155 branches, extended to 160 from Chrome 156
        Get-FlagExpiry 'glic-actor-cursor' 154 | Should -Be 154
        Get-FlagExpiry 'glic-actor-cursor' 155 | Should -Be 154
        Get-FlagExpiry 'glic-actor-cursor' 156 | Should -Be 160
        Get-FlagExpiry 'glic-actor-cursor' 170 | Should -Be 160
        Get-FlagExpiry 'glic' 155 | Should -Be 160
        # Older than every entry: the earliest known milestone
        Get-FlagExpiry 'glic-actor-cursor' 120 | Should -Be 154
    }

    It '-Agent decides $Flags; -Country goes into $OverrideArgs' {
        $Flags -join ',' | Should -BeExactly ($BaseFlags -join ',')
        $withAgent = & { $Agent = $true; $Country = 'de'; . (Import-ScriptDefinitions); , @($Flags, $OverrideArgs) }
        $withAgent[0] -join ',' | Should -BeExactly (($BaseFlags + $AgentFlags) -join ',')
        $withAgent[1] | Should -BeExactly '--variations-override-country=de --lang=en-US'
        $OverrideArgs | Should -BeExactly $Override
    }
}

Describe 'Shortcut helpers' {
    It 'Get-PathTag gives 8 hex digits, the same for any letter case, different per folder' {
        $a = Get-PathTag 'C:\Users\Ivan\Desktop\Google Chrome.lnk'
        $a | Should -Match '^[0-9a-f]{8}$'
        Get-PathTag 'c:\users\ivan\desktop\GOOGLE CHROME.LNK' | Should -BeExactly $a
        Get-PathTag 'C:\Users\Public\Desktop\Google Chrome.lnk' | Should -Not -Be $a
    }

    It 'Test-SharedShortcut matches only files below the shared folders' {
        $SystemShortcutDirs = @(
            @{ Path = 'C:\Users\Public\Desktop'; Recurse = $false },
            @{ Path = 'C:\ProgramData\Microsoft\Windows\Start Menu\'; Recurse = $true },
            @{ Path = ''; Recurse = $false }
        )
        Test-SharedShortcut 'C:\Users\Public\Desktop\Google Chrome.lnk' | Should -BeTrue
        Test-SharedShortcut 'c:\users\public\desktop\google chrome.lnk' | Should -BeTrue
        Test-SharedShortcut 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk' | Should -BeTrue
        Test-SharedShortcut 'C:\Users\Public\Desktop2\Google Chrome.lnk' | Should -BeFalse
        Test-SharedShortcut 'C:\Users\Ivan\Desktop\Google Chrome.lnk' | Should -BeFalse
    }

    It 'Test-ShortcutPending is true until the arguments carry the override' -ForEach @(
        @{ Arguments = ''; Pending = $true }
        @{ Arguments = '--profile-directory=Default'; Pending = $true }
        @{ Arguments = '--lang=de --variations-override-country=us'; Pending = $true }
        @{ Arguments = '--variations-override-country=us --lang=en-US'; Pending = $false }
        @{ Arguments = '--variations-override-country=us --lang=en-US --profile-directory="Profile 1"'; Pending = $false }
    ) {
        Test-ShortcutPending ([pscustomobject]@{ Link = [pscustomobject]@{ Arguments = $Arguments } }) | Should -Be $Pending
    }
}

Describe 'Running the whole script outside Windows PowerShell' {
    BeforeAll {
        $exe = (Get-Process -Id $PID).Path
        $scriptPath = (Resolve-Path -LiteralPath $ScriptUnderTest).Path

        # Runs the script in a child PowerShell with an invariant UI culture (English messages)
        function Invoke-WholeScript([string[]]$Arguments, [string]$SystemRoot) {
            $saved = @{ Invariant = $env:DOTNET_SYSTEM_GLOBALIZATION_INVARIANT; SystemRoot = $env:SystemRoot }
            $env:DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = '1'
            $env:SystemRoot = $SystemRoot
            try { $out = & $exe -NoProfile -NonInteractive -File $scriptPath @Arguments 2>&1 }
            finally {
                $env:DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = $saved.Invariant
                $env:SystemRoot = $saved.SystemRoot
            }
            return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = (@($out | ForEach-Object { "$_" }) -join "`n") }
        }
    }

    It 'stops with exit code 1 and the needWinPS message before any Windows-only call' -Skip:$OnWindows {
        $run = Invoke-WholeScript @('-Agent', '-NoLaunch') $null
        $run.ExitCode | Should -Be 1
        $run.Text | Should -BeExactly ('[FAIL] ' + $Messages['en']['needWinPS'])
    }

    It 'hands the run over to powershell.exe with the same parameters and returns its exit code' -Skip:$OnWindows {
        # A stand-in powershell.exe under a fake SystemRoot records its arguments
        $root = Join-Path $TestDrive 'Windows'
        $fakePS = Join-Path $root 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $argsFile = Join-Path $TestDrive 'relaunch-args.txt'
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fakePS)
        [System.IO.File]::WriteAllText($fakePS, "#!/bin/sh`nfor a in `"`$@`"; do printf '%s\n' `"`$a`"; done > '$argsFile'`nexit 7`n")
        & chmod +x $fakePS

        $run = Invoke-WholeScript @('-Country', 'DE', '-Agent', '-NoLaunch', '-BackupDir', 'C:\Users\A B\backup') $root
        $run.ExitCode | Should -Be 7
        $run.Text | Should -BeExactly ('       ' + $Messages['en']['relaunch'])
        $relaunch = @([System.IO.File]::ReadAllLines($argsFile))
        # The child runs -NonInteractive, so the relaunched copy must not wait for an answer either
        $relaunch[0..5] -join '|' | Should -BeExactly "-NoProfile|-ExecutionPolicy|Bypass|-NonInteractive|-File|$scriptPath"
        $rest = $relaunch[6..($relaunch.Count - 1)]
        $rest.Count | Should -Be 6
        $rest[[array]::IndexOf($rest, '-Country') + 1] | Should -BeExactly 'DE'
        $rest[[array]::IndexOf($rest, '-BackupDir') + 1] | Should -BeExactly 'C:\Users\A B\backup'
        $rest -contains '-Agent' | Should -BeTrue
        $rest -contains '-NoLaunch' | Should -BeTrue
    }
}
