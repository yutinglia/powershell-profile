#region conda initialize
# Fast hook: set conda env vars and import Conda.psm1 on first `conda`/`condac`.
# Skip `conda.exe shell.powershell hook` and `conda activate base`.
# `conda init powershell` may rewrite this block; restore this version if startup is slow again.
$condaRoot = Join-Path $env:USERPROFILE 'miniconda3'
$condaPsm1 = Join-Path $condaRoot 'shell\condabin\Conda.psm1'
if (Test-Path -LiteralPath $condaPsm1) {
    $env:CONDA_EXE = Join-Path $condaRoot 'Scripts\conda.exe'
    $env:_CE_M = $null
    $env:_CE_CONDA = $null
    $env:_CONDA_ROOT = $condaRoot
    $env:_CONDA_EXE = $env:CONDA_EXE
    $env:CONDA_PSM1 = $condaPsm1
    function global:conda {
        Remove-Item -Path Function:\conda -Force -ErrorAction SilentlyContinue
        Import-Module -Name $env:CONDA_PSM1 -ArgumentList @{ ChangePs1 = $false }
        conda @args
    }
}
#endregion
