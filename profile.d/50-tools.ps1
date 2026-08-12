function cleanport {
    net stop winnat
    net start winnat
}

function claude_remote {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Specifies the folder path to pass to the script.")]
        [string]$FolderPath
    )

    $scriptPath = "D:\work\self\__claude\pve_claude.ps1"

    if (-not (Test-Path $scriptPath -PathType Leaf)) {
        Write-Error "The specified script file '$scriptPath' does not exist."
        return
    }

    try {
        $absoluteFolderPath = Resolve-Path -Path $FolderPath -ErrorAction Stop
    }
    catch {
        Write-Error "Invalid or non-existent folder path provided: '$FolderPath'. Error: $($_.Exception.Message)"
        return
    }

    Write-Host "Calling script: '$scriptPath' with Path: '$FolderPath'"

    try {
        & $scriptPath -LocalDir $absoluteFolderPath
    }
    catch {
        Write-Error "An error occurred while executing the script '$scriptPath': $($_.Exception.Message)"
    }
}
