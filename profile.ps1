
#region conda initialize
# !! Contents within this block are managed by 'conda init' !!
$condaExe = Join-Path $env:USERPROFILE 'miniconda3\Scripts\conda.exe'
If (Test-Path $condaExe) {
    (& $condaExe "shell.powershell" "hook") | Out-String | ?{$_} | Invoke-Expression
}
#endregion

