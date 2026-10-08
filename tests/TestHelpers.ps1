# Loads the definitions of chrome-gemini-unlock.ps1 (its functions and the constants they use)
# without running the script. The script itself only runs on Windows PowerShell 5.1, but most of
# its logic works on plain dictionaries and strings and can be tested on any PowerShell.
#
#   . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
#   $Agent = $false; $Country = 'us'; $Lang = 'en'     # inputs the constants depend on
#   . (Import-ScriptDefinitions)                       # dot-source: defines into the caller's scope

$ScriptUnderTest = Join-Path (Split-Path -Parent $PSScriptRoot) 'chrome-gemini-unlock.ps1'

# Top-level assignments that are pure constants; everything else (Add-Type, registry and process
# lookups, the main run) is left out
$DefinitionVariables = @(
    'Messages', 'BaseFlags', 'AgentFlags', 'Flags', 'ManagedFlags', 'FlagExpiry', 'Languages',
    'ProfileLanguageKeys', 'OverrideArgs', 'OverridePrefixPattern', 'ChromeSub', 'RunName', 'HandlerKeyPattern', 'Utf8'
)

function Get-ScriptAst([string]$Path = $ScriptUnderTest) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $Path).Path, [ref]$tokens, [ref]$errors)
    if ($errors) { throw "Parse errors in ${Path}: $($errors[0].Message)" }
    return $ast
}

function Import-ScriptDefinitions([string]$Path = $ScriptUnderTest) {
    $ast = Get-ScriptAst $Path
    $parts = foreach ($st in $ast.EndBlock.Statements) {
        if ($st -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
            $st.Extent.Text
        } elseif ($st -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                  $st.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                  $DefinitionVariables -contains $st.Left.VariablePath.UserPath) {
            $st.Extent.Text
        }
    }
    return [scriptblock]::Create($parts -join "`n")
}

# A dictionary like the ones JavaScriptSerializer returns, built from nested hashtables/arrays
function New-JsonDict($Value) {
    if ($Value -is [System.Collections.IDictionary]) {
        $d = [System.Collections.Generic.Dictionary[string,object]]::new()
        foreach ($k in $Value.Keys) { $d[[string]$k] = New-JsonDict $Value[$k] }
        return $d
    }
    if ($Value -is [array]) { return , [object[]]@($Value | ForEach-Object { New-JsonDict $_ }) }
    return $Value
}
