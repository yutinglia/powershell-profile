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
    Set-PSReadLineOption -PredictionSource History -PredictionViewStyle ListView -ErrorAction Stop
}
catch {
}
