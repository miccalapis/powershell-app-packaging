function Get-InstalledDrivers() {
    #Clear any Errors
    $Error.Clear()

    $procName = "pnputil.exe"
    $procArgs = "/enum-drivers"

    $procInfo = New-Object System.Diagnostics.ProcessStartInfo
    $procInfo.FileName = $procName
    $procInfo.Arguments = $procArgs
    $procInfo.RedirectStandardError = $true
    $procInfo.RedirectStandardOutput = $true
    $procInfo.UseShellExecute = $false

    $procExec = New-Object System.Diagnostics.Process
    $procExec.StartInfo = $procInfo

    $global:driverInformation = [System.Collections.ArrayList]::New()

    $driverInformationOutput = {
 
        $error.Clear()

        if (![string]::IsNullOrEmpty($Event.SourceEventArgs.Data)) {
            try {
                $global:driverInformation.Add($($Event.SourceEventArgs.Data))
            }
            catch {
                Write-Host "Failed to add the event to the array. The reported error is: $error" 
            }
             
        }
    }

    $driverInformationError = {
        if (! [string]::IsNullOrEmpty($Event.SourceEventArgs.Data)) {
            Write-Host "$($Event.SourceEventArgs.Data)" 
        
        }
    }

    # Register Object Events for stdin\stdout reading
    Register-ObjectEvent -InputObject $procExec -Action $driverInformationOutput -EventName OutputDataReceived -SourceIdentifier StdOutEvent | Out-Null
    Register-ObjectEvent -InputObject $procExec -Action $driverInformationError -EventName ErrorDataReceived -SourceIdentifier StdErrEvent  | Out-Null

    try {

        #Attempt to Execute the Application
        $procExec.Start() | Out-Null
        $procExec.BeginErrorReadLine()
        $procExec.BeginOutputReadLine()
        $procExec.WaitForExit()
        $procExitCode = $procExec.ExitCode

    }
    catch {

        $ErrorMessage = $_.Exception.Message
        $FullErrorMessage = $_.Exception
        
        Write-Host "The execution of '$procName' with parameters: '$procArgs has failed with error: $errorMessage `nExit Code: $procExitCode `nFull Exception Error:`n $FullErrorMessage " 

        Exit 1
    }


    # Unregistering events to retrieve process output.
    Unregister-Event -SourceIdentifier StdOutEvent | Out-Null
    Unregister-Event -SourceIdentifier StdErrEvent  | Out-Null

    Write-Host "Execution '$procName' with arguments '$procArgs' has returned the exit code of : $procExitCode."

    return $global:driverInformation
}

$driverReferenceList = @(
    "brimm22a.inf",
    "brpom22a.inf",
    "BRPRM22A.INF",
    "HttpToUsbBridge.inf"
)

$printerName = "Brother MFC-L2820DW"

$installedDrivers = Get-InstalledDrivers

$installedDriverCount = 0
$driverIsInstalled = $false

foreach ($driver in $installedDrivers) {
    foreach ($driverReference in $driverReferenceList) {
        if ($driver -like "*$driverReference*") {
            $installedDriverCount++
            $driverName = $driver.split(":")[1].Trim()
            Write-Host "Found installed driver: $driverName"
            $installedDriverCount++
            break
        }
    }
}

if ($installedDriverCount -eq $driverReferenceList.Count) {
    $driverIsInstalled = $true
} 

if ($driverIsInstalled) {
    Write-Host "All Printer drivers for $printerName detected successfully"
    exit 0
}
else {
    Write-Host "Not all Printer driver for $printerName  were detected successfully"
    exit 1
}