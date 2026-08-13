function cleanport {
    <#
    .SYNOPSIS
        Restart the WinNAT service.
    #>
    net stop winnat
    net start winnat
}
