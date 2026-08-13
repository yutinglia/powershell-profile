Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Ctrl+Backspace -Function BackwardKillWord

Set-PSReadLineOption -BellStyle None -Colors @{
    Command                = "`e[38;2;80;250;123m"
    Keyword                = "`e[38;2;255;121;198m"
    Operator               = "`e[38;2;255;121;198m"
    String                 = "`e[38;2;241;250;140m"
    Parameter              = "`e[38;2;255;184;108m"
    Type                   = "`e[38;2;139;233;253m"
    Number                 = "`e[38;2;189;147;249m"
    Variable               = "`e[38;2;189;147;249m"
    Comment                = "`e[38;2;98;114;164m"
    Default                = "`e[38;2;248;248;242m"
    Error                  = "`e[38;2;255;85;85m"
    Selection              = "`e[48;2;68;71;90m"
    InlinePrediction       = "`e[38;2;98;114;164m"
    ListPrediction         = "`e[38;2;189;147;249m"
    ListPredictionSelected = "`e[38;2;248;248;242m`e[48;2;68;71;90m"
}

try {
    if (-not ('ProfileCommandPredictor' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Management.Automation.Subsystem;
using System.Management.Automation.Subsystem.Prediction;
using System.Threading;

public sealed class ProfileCommandPredictor : ICommandPredictor
{
    public static readonly Guid PredictorId = new Guid("3f8c1a72-9d4e-4b6a-a1c0-7e5d92f4b8e1");
    private readonly string[] _names;
    private readonly string[] _tips;

    public ProfileCommandPredictor(string[] names, string[] tips)
    {
        _names = names ?? Array.Empty<string>();
        _tips = tips ?? Array.Empty<string>();
    }

    public Guid Id { get { return PredictorId; } }
    public string Name { get { return "Profile"; } }
    public string Description { get { return "Suggests commands from this PowerShell profile"; } }
    public Dictionary<string, ScriptBlock> FunctionsToDefine { get { return null; } }

    public SuggestionPackage GetSuggestion(PredictionClient client, PredictionContext context, CancellationToken cancellationToken)
    {
        string input = context.InputAst.Extent.Text;
        if (string.IsNullOrWhiteSpace(input) || input.IndexOf(' ') >= 0)
        {
            return default(SuggestionPackage);
        }

        var results = new List<PredictiveSuggestion>();
        for (int i = 0; i < _names.Length; i++)
        {
            string name = _names[i];
            if (name.Length > input.Length &&
                name.StartsWith(input, StringComparison.OrdinalIgnoreCase))
            {
                string tip = (i < _tips.Length) ? _tips[i] : null;
                if (string.IsNullOrEmpty(tip))
                {
                    results.Add(new PredictiveSuggestion(name));
                }
                else
                {
                    results.Add(new PredictiveSuggestion(name, tip));
                }
            }
        }

        return results.Count == 0 ? default(SuggestionPackage) : new SuggestionPackage(results);
    }

    public bool CanAcceptFeedback(PredictionClient client, PredictorFeedbackKind feedback)
    {
        return false;
    }

    public void OnSuggestionDisplayed(PredictionClient client, uint session, int countOrIndex) { }
    public void OnSuggestionAccepted(PredictionClient client, uint session, string acceptedSuggestion) { }
    public void OnCommandLineAccepted(PredictionClient client, IReadOnlyList<string> history) { }
    public void OnCommandLineExecuted(PredictionClient client, string commandLine, bool success) { }
}
'@
    }

    $profilePredictNames = [System.Collections.Generic.List[string]]::new()
    $profilePredictTips = [System.Collections.Generic.List[string]]::new()
    $profilePredictFiles = @()
    if ($profile -and (Test-Path -LiteralPath $profile)) {
        $profilePredictFiles += Get-Item -LiteralPath $profile
    }
    if ($PSScriptRoot -and (Test-Path -LiteralPath $PSScriptRoot)) {
        $profilePredictFiles += Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File
    }

    foreach ($profilePredictFile in $profilePredictFiles) {
        $profilePredictLines = Get-Content -LiteralPath $profilePredictFile.FullName
        for ($i = 0; $i -lt $profilePredictLines.Count; $i++) {
            if ($profilePredictLines[$i] -notmatch '^function\s+([a-zA-Z0-9_.-]+)') {
                continue
            }

            $profilePredictName = $Matches[1]
            if ($profilePredictName -match '^(Get|Invoke)-') {
                continue
            }

            $profilePredictTip = ''
            for ($j = $i + 1; $j -lt $profilePredictLines.Count; $j++) {
                $trim = $profilePredictLines[$j].Trim()
                if ($trim -eq '') {
                    continue
                }
                if ($trim -eq '{') {
                    continue
                }
                if ($trim -eq '<#' -or $trim.StartsWith('<#')) {
                    $inSynopsis = $false
                    $start = if ($trim -eq '<#') { $j + 1 } else { $j }
                    for ($k = $start; $k -lt $profilePredictLines.Count; $k++) {
                        $helpLine = $profilePredictLines[$k].Trim()
                        if ($helpLine -eq '#>' -or $helpLine.EndsWith('#>')) {
                            break
                        }
                        if ($helpLine -eq '.SYNOPSIS') {
                            $inSynopsis = $true
                            continue
                        }
                        if ($inSynopsis) {
                            if ($helpLine.StartsWith('.')) {
                                break
                            }
                            if ($helpLine) {
                                $profilePredictTip = $helpLine
                                break
                            }
                        }
                    }
                }
                break
            }

            $profilePredictNames.Add($profilePredictName)
            $profilePredictTips.Add($profilePredictTip)
        }
    }

    try {
        [System.Management.Automation.Subsystem.SubsystemManager]::UnregisterSubsystem(
            [System.Management.Automation.Subsystem.SubsystemKind]::CommandPredictor,
            [ProfileCommandPredictor]::PredictorId
        )
    }
    catch {
    }

    [System.Management.Automation.Subsystem.SubsystemManager]::RegisterSubsystem(
        [System.Management.Automation.Subsystem.SubsystemKind]::CommandPredictor,
        [ProfileCommandPredictor]::new([string[]]$profilePredictNames, [string[]]$profilePredictTips)
    )
}
catch {
}

Remove-Variable -Name profilePredictNames, profilePredictTips, profilePredictFiles, profilePredictFile, profilePredictLines, profilePredictName, profilePredictTip -ErrorAction SilentlyContinue

try {
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin -PredictionViewStyle ListView -ErrorAction Stop
}
catch {
}
