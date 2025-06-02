
Param
(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('Install', 'Uninstall', 'Update')]
    [string] $action,
    [string] $maintenanceToken
)

#Assembly for MessageBox
Add-Type -AssemblyName PresentationFramework

function global:write-LogEntry() {
    param (
        [parameter(Mandatory = $true, HelpMessage = "Value added to the log file.")]
        [ValidateNotNullOrEmpty()]
        [string]$value,
        
        [parameter(Mandatory = $true, HelpMessage = "Severity for the log entry. 1 for Informational, 2 for Warning and 3 for Error.")]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("1", "2", "3")]
        [string]$severity,
        
        [parameter(Mandatory = $false, HelpMessage = "Name of the log file that the entry will written to.")]
        [string]$fileName = $global:logFile
    )

    if (!([System.IO.File]::Exists($fileName))) {
        [System.IO.File]::Create($fileName).close() | Out-Null
    }

    $Time = Get-Date -Format "HH:mm:ss.fff"
    $Date = Get-Date -Format "MM-dd-yyyy"
    $LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""HPDriverUpdate"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"

    Add-Content -Value $LogText -Path $fileName

    Write-Host "$($date) - $($time) $value"
}

function FatalExceptionError() {
    param (
        [parameter(Mandatory = $true, HelpMessage = "Enter the message that will be sent to the log")]
        [ValidateNotNullOrEmpty()]
        [string]$value
    )

    global:write-LogEntry -value $value -severity 3
    global:write-LogEntry -value "LOG END : ERROR" -Severity 3
    Stop-Transcript

    exit 1
}


function Invoke-Executable() {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$procName,
        [Parameter()]
        [string]$procArgs,
        [Parameter()]
        [string]$workingDirectory

    )
    #Clear any Errors
    $Error.Clear()

    $procInfo = New-Object System.Diagnostics.ProcessStartInfo
    $procInfo.FileName = $procName

    if ($procArgs) {
        $procInfo.Arguments = $procArgs
    }
    
    $procInfo.WorkingDirectory = $workingDirectory

    $procInfo.RedirectStandardError = $true
    $procInfo.RedirectStandardOutput = $true
    $procInfo.UseShellExecute = $false

    $procExec = New-Object System.Diagnostics.Process
    $procExec.StartInfo = $procInfo

    $writeOutput = {
        #Write-Host ($Event.SourceEventArgs.Data)
        if (! [string]::IsNullOrEmpty($Event.SourceEventArgs.Data)) {
            if ($Event.SourceEventArgs.Data -notin "   / ", "   \ ", "   - ", "   | ", " " ) {
                if ($Event.SourceEventArgs.Data -notlike "*ûÆ*") {
                    global:write-LogEntry -Value "$($Event.SourceEventArgs.Data)" -Severity 1
                }
            }
        }
    }

    $writeError = {
        if (! [string]::IsNullOrEmpty($Event.SourceEventArgs.Data)) {
            global:write-LogEntry -Value "$($Event.SourceEventArgs.Data)" -Severity 3
        
        }
    }

    # Register Object Events for stdin\stdout reading
    Register-ObjectEvent -InputObject $procExec -Action $writeOutput -EventName OutputDataReceived -SourceIdentifier StdOutEvent | Out-Null
    Register-ObjectEvent -InputObject $procExec -Action $writeError -EventName ErrorDataReceived -SourceIdentifier StdErrEvent  | Out-Null

    $msg = "Attempting to execute '$procName' with parameters: '$procArgs'"

    global:write-LogEntry -Value $msg -Severity 3

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
        $msg = "The execution of '$procName' with parameters: '$procArgs has failed with error: $errorMessage `nExit Code: $procExitCode `nFull Exception Error:`n $FullErrorMessage "
        
        global:write-LogEntry -Value $msg -Severity 3

        Exit 1
    }
    
    # Unregistering events to retrieve process output.
    Unregister-Event -SourceIdentifier StdOutEvent | Out-Null
    Unregister-Event -SourceIdentifier StdErrEvent  | Out-Null

    $msg = "Execution '$procName' with arguments '$procArgs' has returned the exit code of : $procExitCode."

    global:write-LogEntry -Value $msg -Severity 1
    
    $global:exitCode = $procExitCode
}

function String-Formatter() {
    [OutputType([string])]

    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$stringInput
    )

    $formatedString = $stringInput.split(":")[1].replace(' ', '')

    return $formatedString

}

function Get-InstalledDrivers {
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
        if (![string]::IsNullOrEmpty($Event.SourceEventArgs.Data)) {
            try {
                $global:driverInformation.Add($($Event.SourceEventArgs.Data))
            }
            catch {
                global:write-LogEntry -Value "Failed to add the event to the array. The reported error is: $error" -Severity 3
            }
        }
    }

    $driverInformationError = {
        if (![string]::IsNullOrEmpty($Event.SourceEventArgs.Data)) {
            global:write-LogEntry -Value "$($Event.SourceEventArgs.Data)" -Severity 3
        }
    }

    # Register Object Events for stdin\stdout reading
    Register-ObjectEvent -InputObject $procExec -Action $driverInformationOutput -EventName OutputDataReceived -SourceIdentifier StdOutEvent | Out-Null
    Register-ObjectEvent -InputObject $procExec -Action $driverInformationError -EventName ErrorDataReceived -SourceIdentifier StdErrEvent  | Out-Null

    global:write-LogEntry -Value "Attempting to execute '$procName' with parameters: '$procArgs'" -Severity 3

    try {
        $procExec.Start() | Out-Null
        $procExec.BeginErrorReadLine()
        $procExec.BeginOutputReadLine()
        $procExec.WaitForExit()
        $procExitCode = $procExec.ExitCode
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        $FullErrorMessage = $_.Exception
        global:write-LogEntry -Value "The execution of '$procName' with parameters: '$procArgs has failed with error: $errorMessage `nExit Code: $procExitCode `nFull Exception Error:`n $FullErrorMessage " -Severity 3
        Exit 1
    }

    # Unregistering events to retrieve process output.
    Unregister-Event -SourceIdentifier StdOutEvent | Out-Null
    Unregister-Event -SourceIdentifier StdErrEvent  | Out-Null

    global:write-LogEntry -Value "Execution '$procName' with arguments '$procArgs' has returned the exit code of : $procExitCode." -Severity 1

    # Parse the output into PSCustomObjects
    $drivers = @()
    $currentDriver = @{}
    foreach ($line in $global:driverInformation) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^Microsoft PnP Utility') {
            continue
        }
        if ($line -match '^\s*(.+?):\s*(.+)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            # If we see a new Published Name and already have one, start a new object
            if ($key -eq 'Published Name' -and $currentDriver.Count -gt 0) {
                $drivers += [PSCustomObject]$currentDriver
                $currentDriver = @{}
            }
            $currentDriver[$key] = $value
        }
    }
    if ($currentDriver.Count -gt 0) {
        $drivers += [PSCustomObject]$currentDriver
    }
    return $drivers
}

function Write-InstallTags {
    #Create Install Tag file and reg key for manual detection of installation.
    global:write-LogEntry -value "CREATE INSTALL TAG - FILE: $pathTag\Installed.tag" -severity 1
    $error.Clear()

    try {
        Set-Content -Path "$pathTag\Installed.tag" -Value "TRUE"
    }
    catch {
        global:write-LogEntry -value "Unable to set the Installed tag. The reported error is: $error" -severity 3
    }
}


function Detect-CIMInstalled() {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$appName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [system.version]$appVersion
    )


    $qry = "select * from win32_product where name LIKE '%$appName%'"
    $appInfo = Get-CimInstance -query $qry

    if ($appInfo) {

        [system.version] $appInstalledVersion = $appInfo.Version

        if ($appInstalledVersion -eq $appVersion) {
            
            $msg = "Found $appName with version v$appInstalledVersion is greater than or equal to the required version v$appVersion"       
            global:write-LogEntry -value $msg -severity 1
            return $appInfo
        }
        else {
            $msg = "Found $appName with version v$appInstalledVersion is less than the required version v$appVersion"       
            global:write-LogEntry -value $msg -severity 1

            return $appInfo
        }
    }
    else {
        $msg = "$appName is not installed, no uninstall action will be taken."       
        global:write-LogEntry -value $msg -severity 3

        return $false
    }
    
}


################################ SCRIPT VARIABLES #######################################
$script:package = "Brother_MFC-L2820DW_Driver"                                         #Name of the package should be descriptive, but short, no special characters and no spaces
$version = "2.1.0.0"                                                           #Should be the version of the application - not the installer version which could be different
$pathLocal = "C:\Windows\Temp"                                                     #Must be C:\'something'
$global:pathLog = "$pathLocal\Intune\$package\$version\Logs"                #Default location for log files
$global:applicationLog = "$pathLog\$action-$package-Application.log"                    #This is an application installer log file - not the transcript log. Not all installers will support an application installer log parameter
$global:transcriptLog = "$global:pathLog\$action-$package-Transcript.log"   #This is the powershell transcript log file
$global:logFile = "$global:pathLog\$action-$package.log"                    #This is the log file that will be used by the write-LogEntry
$pathTag = "$pathLocal\Intune\$package\$version\Install"                    #Location for a 'tag' to assist with installation detection 
$global:exitCode = 0
#########################################################################################

$Error.Clear()


# Start the transcript log
Start-Transcript -Path $global:transcriptLog -Append

#Create the log directory if it does not exist
if (![System.IO.Directory]::Exists($global:pathLog)) {
    
    global:write-LogEntry -value "Creating the log directory: $global:pathLog" -severity 1

    try {
        [System.IO.Directory]::CreateDirectory($global:pathLog) | Out-Null
    }
    catch {

        FatalExceptionError -value "Unable to create the log directory. The reported error is: $error"
    }
    
}

#Create the Install directory if it does not exist
if (![System.IO.Directory]::Exists($pathTag)) {

    global:write-LogEntry -value "Creating the Install directory: $pathTag" -severity 1

    try {
        [System.IO.Directory]::CreateDirectory($pathTag) | Out-Null
    }
    catch {
        FatalExceptionError -value "Unable to create the Install directory. The reported error is: $error"
    }
}


#region AppLication Installer Logic Variables
################################ APPLICATION INSTALLER LOGIC VARIABLES #######################################

$driverFilesPath = "$PSScriptRoot\payload"
$infFileList = Get-ChildItem -Path $driverFilesPath -Recurse -Filter "*.inf"

##############################################################################################################
#end region

#Application Installer Logic Starts Here
global:write-LogEntry -value "Starting the $action of the application." -severity 1

#region Install
if ($action -eq "Install") {

    if (!$infFileList) {
        FatalExceptionError -value "Unable to find valid INF driver files in $driverFilesPath"
    }

    # Register Driver with Windows Driver Repository
    foreach ($infFile in $infFileList.FullName) {
        global:write-LogEntry -value "Attempting to register $infFile with Windows Driver Repository" -severity 1

        $appArguments = "/add-driver `"$infFile`" /install"

        Invoke-Executable -procName "pnputil.exe" -procArgs $appArguments
    }

    # Sleep to allow system to properly register driver
    Start-Sleep -Seconds 5

    # Query Driver Install and get array of PSCustomObjects
    $driverList = Get-InstalledDrivers

    if (!$driverList -or $driverList.Count -eq 0) {
        FatalExceptionError -value "Unable to retrieve the list of installed drivers from the Windows Driver Repository"
    }

    $installedDriverCount = 0

    foreach ($infFileName in $infFileList.Name) {
        foreach ($driver in $driverList) {
            if ($driver.'Original Name' -eq $infFileName) {
                $newOEMInfFilename = $driver.'Published Name'
                global:write-LogEntry -value "Driver $($infFileName) is installed, and is stored as `"$newOEMInfFilename`" in the driver repository" -severity 1
                $installedDriverCount++
                break
            }
        }
    }

    if ($installedDriverCount -ne $infFileList.Count) {
        global:write-LogEntry -value "The system located $installedDriverCount driver(s) but expected $($infFileList.Count). Not all drivers have installed successfully." -severity 2
    }
}
#end region

#region Uninstall
if ($action -eq "Uninstall") {

    # Remove drivers from the Windows Repository
    # Query Driver Install
    $driverList = Get-InstalledDrivers

    if (!$driverList) {
        FatalExceptionError -value "Unable to retrieve the list of installed drivers from the Windows Driver Repository"
    }

    # Build a reference list of INF names to look for
    $driverReferenceList = $infFileList.Name

    $removedDriverCount = 0

    foreach ($driver in $driverList) {

        foreach ($driverReference in $driverReferenceList) {

            if ($driver.'Original Name' -ieq $driverReference) {
                $oemInfFilename = $driver.'Published Name'
                global:write-LogEntry -value "Found installed driver: $($driver.'Original Name')" -severity 1
                global:write-LogEntry -value "Attempting to unregister $($driver.'Original Name') ($oemInfFilename) from the Windows Driver Repository" -severity 1

                $appArguments = "/delete-driver $oemInfFilename /uninstall /force"
                Invoke-Executable -procName "pnputil.exe" -procArgs $appArguments

                $removedDriverCount++
                break
            }
        }
    }

    if ($removedDriverCount -eq 0) {
        global:write-LogEntry -value "No matching drivers found to uninstall." -severity 2
    }
}

#region End of Script
if ($global:exitCode -eq 0) {
    global:write-LogEntry -value "The $action of the application was successful." -severity 1
    Write-InstallTags
    exit 0
}

global:write-LogEntry -value "END - Exiting with Exit Code: $($global:exitCode)" -severity 1
Stop-Transcript

exit $global:exitCode

#end region