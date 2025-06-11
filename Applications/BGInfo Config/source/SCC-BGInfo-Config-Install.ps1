
Param
(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('Install', 'Uninstall', 'Update')]
    [string] $action
)


<#
.SYNOPSIS
    This function writes a log entry to the log file.

.DESCRIPTION
    This function writes a log entry to the log file. The log entry will contain the value, severity, time, date, component, context, and thread.

.PARAMETER value
    The value that will be written to the log file.

.PARAMETER severity
    The severity of the log entry. 1 for Informational, 2 for Warning, and 3 for Error.

.PARAMETER fileName
    The name of the log file that the entry will be written to. The default value is the global variable $logFile.

.PARAMETER component
    The name of the component that is being monitored. The default value is the script package.

.EXAMPLE
    write-LogEntry -value "This is an informational log entry." -severity 1

    write-LogEntry -value "This is an informational log entry." -severity 1 -fileName "C:\Logs\log.txt"

    write-LogEntry -value "This is an informational log entry." -severity 1 -component "ComponentName"

#>
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
        [string]$fileName = $global:logFile,

        [parameter(Mandatory = $false, HelpMessage = "Specify the name of the component that is being monitored.")]
        [string]$component = $script:package
    )

    if (!([System.IO.File]::Exists($fileName))) {
        [System.IO.File]::Create($fileName).close() | Out-Null
    }

    $Time = Get-Date -Format "HH:mm:ss.fff"
    $Date = Get-Date -Format "MM-dd-yyyy"
    $LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""$($component)"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"

    Add-Content -Value $LogText -Path $fileName

    Write-Host "$($date) - $($time) $value"

}

<#
.SYNOPSIS
    This function writes a log entry to the log file and exits the script with an exit code of 1.

.DESCRIPTION
    This function writes a log entry to the log file and exits the script with an exit code of 1. The log entry will contain the value, severity, time, date, component, context, and thread.

.PARAMETER value
    The value that will be written to the log file.

.EXAMPLE
    FatalExceptionError -value "This is a fatal error."

#>
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

<#
.SYNOPSIS
    This function executes an executable with arguments and returns the exit code.

.DESCRIPTION
    This function executes an executable with arguments and returns the exit code. The function will also write the output and error streams to the log file.

.PARAMETER procName
    The name of the executable that will be executed.

.PARAMETER procArgs
    The arguments that will be passed to the executable. This parameter is optional.

.EXAMPLE
    Invoke-Executable -procName "C:\Windows\System32\cmd.exe" -procArgs "/c echo Hello World"

    Invoke-Executable -procName "C:\Windows\System32\cmd.exe"
#>
function Invoke-Executable() {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$procName,

        [Parameter()]
        [string]$procArgs

    )
    #Clear any Errors
    $Error.Clear()

    $procInfo = New-Object System.Diagnostics.ProcessStartInfo
    $procInfo.FileName = $procName
    $procInfo.Arguments = $procArgs
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

    $msg = "Attempting to execute '$procName' with paramters: '$procArgs'"

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
        $msg = "The execution of '$procName' with paramters: '$procArgs has failed with error: $errorMessage `nExit Code: $procExitCode `nFull Exception Error:`n $FullErrorMessage "
        
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

<#
    .SYNOPSIS
    Deletes a file from the specified file path.

    .DESCRIPTION
    The Delete-File function deletes a file from the specified file path. It uses the System.IO.File.Delete method to delete the file.

    .PARAMETER filePath
    The path of the file to be deleted.

    .EXAMPLE
    Delete-File -filePath "C:\path\to\file.txt"
    Deletes the file located at "C:\path\to\file.txt".

#>
function Delete-File() {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$filePath
    )

    try {
        [System.IO.File]::Delete($filePath)
    }
    catch {
        $msg = "Unable to delete folder $filePath. The reported error: $error"
        global:write-LogEntry -value $msg -severity 3

        return $false
    }

    $msg = "Successfully deleted the file $filePath."
    global:write-LogEntry -value $msg -severity 1

    return $true
}

<#
    .SYNOPSIS
    Deletes a folder.

    .DESCRIPTION
    This function deletes a folder specified by the folderPath parameter. It uses the System.IO.Directory.Delete method to delete the folder. If the deletion is successful, it writes a log entry with severity 1. If an error occurs during deletion, it writes a log entry with severity 3 and returns $false.

    .PARAMETER folderPath
    Specifies the path of the folder to be deleted.

    .EXAMPLE
    Delete-Folder -folderPath "C:\Temp\MyFolder"
    Deletes the folder "C:\Temp\MyFolder".

#>
function Delete-Folder {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$folderPath
    )

    try {
        [System.IO.Directory]::Delete($folderPath, $true)
    }
    catch {
        $msg = "Unable to delete folder $folderPath. The reported error: $error"
        global:write-LogEntry -value $msg -severity 3

        return $false
    }

    $msg = "Successfully deleted the folder $folderPath."
    global:write-LogEntry -value $msg -severity 1

    return $true
}


function Create-Folder {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$folderPath
    )

    try {
        [System.IO.Directory]::CreateDirectory($folderPath) | Out-Null
    }
    catch {
        $msg = "Unable to create folder $folderPath. The reported error: $error"
        global:write-LogEntry -value $msg -severity 3

        return $false
    }

    $msg = "Successfully created the folder $folderPath."
    global:write-LogEntry -value $msg -severity 1

    return $true
}

function Copy-File {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$sourcePath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$destinationPath
    )

    try {
        [System.IO.File]::Copy($sourcePath, $destinationPath, $true) # Overwrite if exists
    }
    catch {
        $msg = "Unable to copy file from $sourcePath to $destinationPath. The reported error: $error"
        global:write-LogEntry -value $msg -severity 3

        return $false
    }

    $msg = "Successfully copied file from $sourcePath to $destinationPath."
    global:write-LogEntry -value $msg -severity 1

    return $true
}

function Create-Shortcut {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $shortcutName,
        [string] $shortcutIconPath,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $shortcutPath,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $shortcutExePath,
        [string] $shortcutExeArgs,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $shortcutExeWorkingDir
    )

    $error.Clear()

    $shortcutFullPath = "$shortcutPath\$shortcutName" + ".lnk"

    if ([System.IO.File]::Exists($shortcutFullPath)) {
        $msg = "Have found an existing shortcut `"$shortcutFullPath`", attempting to delete"
        global:write-LogEntry -value $msg -severity 1
        
        try {
            Remove-Item -Path $shortcutFullPath -Force -ErrorAction Stop
        }
        catch {
            $msg = "Have found an existing shortcut `"$shortcutFullPath`", but deletion failed. The reported error: $error"
            global:write-LogEntry -value $msg -severity 3

            return
        }
    }

    if (![System.IO.File]::Exists($shortcutExePath)) {
        $msg = "The specified executable $shortcutExePath cannot be found"
        global:write-LogEntry -value $msg -severity 3

        return
    }

    if ($shortcutIconPath -eq $null -or $shortcutIconPath -eq "") {
        $msg = "The icon path has not been specified. Using icon from executable $shortcutExePath instead."
        global:write-LogEntry -value $msg -severity 2
       
        $shortcutIconPath = "$shortcutExePath,0" # Use the executable's icon if no specific icon is provided
    }

    # Fix the validation to handle the icon index in the path
    $iconPathOnly = $shortcutIconPath -split ',' | Select-Object -First 1
    if (![System.IO.File]::Exists($iconPathOnly)) {
        $msg = "The specified icon path $iconPathOnly cannot be found."
        global:write-LogEntry -value $msg -severity 3
        return
    }

    if (![System.IO.File]::Exists($shortcutIconPath)) {
        $msg = "The specified icon path $shortcutIconPath cannot be found."
        global:write-LogEntry -value $msg -severity 3

        return
    }

    if (![System.IO.Directory]::Exists($shortcutExeWorkingDir)) {
        $msg = "The specified working directory $shortcutExeWorkingDir does not exist"
        global:write-LogEntry -value $msg -severity 3

        return
    }

  

    if (![System.IO.Directory]::Exists($shortcutPath)) {
        $msg = "The shortcut path $shortcutPath does not exist"
        global:write-LogEntry -value $msg -severity 3

        return
    }

 
    $msg = "Attempting to create shortcut $shortcutFullPath."
    global:write-LogEntry -value $msg -severity 1

    try {

        $WshShell = New-Object -comObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($shortcutFullPath)
        $Shortcut.TargetPath = $shortcutExePath

        if ($shortcutExeArgs) {
            $Shortcut.Arguments = $shortcutExeArgs
        }

        $Shortcut.IconLocation = $shortcutIconPath
        $Shortcut.WorkingDirectory = $shortcutExeWorkingDir
        
        $Shortcut.Save()
        
    }
    catch {
        $msg = "Failed to create the shortcut $shortcutFullPath. The reported error is: $error"
        global:write-LogEntry -value $msg -severity 3

        return
    }

    return $true
}

################################ SCRIPT VARIABLES #######################################
$script:package = "SCC_BGInfo_Config_Install_QLD"                                         #Name of the package should be descriptive, but short, no special characters and no spaces
$version = "1.00"                                                           #Should be the version of the application - not the installer version which could be different
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
################################ AAPLICATION INSTALLER LOGIC VARIABLES #######################################

$rootInstallPath = [System.Environment]::GetFolderPath("CommonApplicationData") + "\BGinfo" # This is the default installation path for BGInfo Configuration
$configInstallPath = "$rootInstallPath\BGInfoConfig_2025_QLD.bgi" # This is the default executable path for BGInfo
$configSourcePath = "$PSScriptRoot\BGInfoConfig_2025_QLD.bgi" # This is the source path for BGInfo

$rootBGInfoInstallPath = [System.Environment]::GetFolderPath("ProgramFiles") + "\BGinfo\Bginfo64.exe" # This is the default installation path for BGInfo
#$shortcutArguments = "C:\ProgramData\BGinfo\BGInfoConfig_2025.bgi /silent /timer:0 /nolicprompt" # This is the arguments that will be passed to BGInfo when it is executed

$shortcutName = "BGInfo" # This is the name of the shortcut that will be created
$shortcutExePath = $rootBGInfoInstallPath # This is the path to the BGInfo executable
$shortcutExeArgs = "$configInstallPath /silent /timer:0 /nolicprompt" # This is the arguments that will be passed to BGInfo when it is executed
$shortcutExeWorkingDir = $rootInstallPath # This is the working directory for the BGInfo executable
$shortcutInstallPath = [System.Environment]::GetFolderPath("CommonApplicationData") +"\Microsoft\Windows\Start Menu\Programs\StartUp" # This is the path where the shortcut will be created

$shortcutFullPath = "$shortcutInstallPath\$shortcutName.lnk" # This is the full path to the shortcut that will be created

##############################################################################################################
#end region

#Application Installer Logic Starts Here
global:write-LogEntry -value "Starting the $action of the application." -severity 1

#region Install
if ($action -eq "Install") {

    #Check if BGInfo is installed
    if ([System.IO.File]::Exists($rootBGinfoInstallPath)) {
        global:write-LogEntry -value "The file $rootBGinfoInstallPath exists." -severity 1
    }
    else {
        FatalExceptionError -value "The file $rootBGinfoInstallPath does not exist. The reported error is: $error"
    }

    #Check if the folder exists
    if (![System.IO.Directory]::Exists($rootInstallPath)) {
        global:write-LogEntry -value "The folder $rootInstallPath exists. Deleting the folder." -severity 1
        
        #Create the folder
        $isCreated = Create-Folder -folderPath $rootInstallPath

        if ($isCreated -eq $false) {
            FatalExceptionError -value "Unable to create the folder $rootInstallPath. The reported error is: $error"
        }
    }
    else {
        global:write-LogEntry -value "The folder $rootInstallPath already exists. No action required." -severity 1
    }

    #Check if the file exists
    if ([System.IO.File]::Exists($configInstallPath)) {
        global:write-LogEntry -value "The file $configInstallPath exists. Deleting the file." -severity 1
        
        #Delete the file
        $isDeleted = Delete-File -filePath $configInstallPath

        if ($isDeleted -eq $false) {
            FatalExceptionError -value "Unable to delete the file $configInstallPath. The reported error is: $error"
        }
    }
    else {
        global:write-LogEntry -value "The file $configInstallPath does not exist." -severity 1
    }


    #Copy the file
    $isCopied = Copy-File -sourcePath $configSourcePath -destinationPath $configInstallPath

    if ($isCopied -eq $false) {
        FatalExceptionError -value "Unable to copy the file from $configSourcePath to $configInstallPath. The reported error is: $error"
    }

    #Check if the file exists
    if ([System.IO.File]::Exists($configInstallPath)) {
        global:write-LogEntry -value "The file $configInstallPath exists." -severity 1
    }
    else {
        FatalExceptionError -value "The file $configInstallPath does not exist. The reported error is: $error"
    }

    #Check if the shortcut exists
    if ([System.IO.File]::Exists($shortcutFullPath)) {
        global:write-LogEntry -value "The file $shortcutFullPath exists. Deleting the file." -severity 1
        
        #Delete the file
        $isDeleted = Delete-File -filePath $shortcutFullPath

        if ($isDeleted -eq $false) {
            FatalExceptionError -value "Unable to delete the file $shortcutFullPath. The reported error is: $error"
        }
    }
    else {
        global:write-LogEntry -value "The file $shortcutFullPath does not exist." -severity 1
    }

    #Create the shortcut
    $isShortcutCreated = Create-Shortcut -shortcutName $shortcutName -shortcutIconPath $rootBGInfoInstallPath -shortcutPath $shortcutInstallPath -shortcutExePath $shortcutExePath -shortcutExeArgs $shortcutExeArgs -shortcutExeWorkingDir $shortcutExeWorkingDir


    if (!$isShortcutCreated) {
        FatalExceptionError -value "Unable to create the shortcut $shortcutInstallPath. The reported error is: $error"
    }

}
#end region

#region Uninstall
if ($action -eq "Uninstall") {

    #Check if the file exists
    if ([System.IO.File]::Exists($configInstallPath)) {
        global:write-LogEntry -value "The file $configInstallPath exists. Deleting the file." -severity 1
        
        #Delete the file
        $isDeleted = Delete-File -filePath $configInstallPath

        if ($isDeleted -eq $false) {
            FatalExceptionError -value "Unable to delete the file $configInstallPath. The reported error is: $error"
        }
    }
    else {
        global:write-LogEntry -value "The file $configInstallPath does not exist." -severity 1
    }

    #Check if the shortcut exists
    if ([System.IO.File]::Exists($shortcutFullPath)) {
        global:write-LogEntry -value "The file $shortcutFullPath exists. Deleting the file." -severity 1
        
        #Delete the file
        $isDeleted = Delete-File -filePath $shortcutFullPath

        if ($isDeleted -eq $false) {
            FatalExceptionError -value "Unable to delete the file $shortcutFullPath. The reported error is: $error"
        }
    }
    else {
        global:write-LogEntry -value "The file $shortcutFullPath does not exist." -severity 1
    }

}

#end region

#region End of Script
if ($global:exitCode -eq 0) {
    global:write-LogEntry -value "The $action of the application was successful." -severity 1
    Write-InstallTags
}

global:write-LogEntry -value "END - Exiting with Exit Code: $($global:exitCode)" -severity 1
Stop-Transcript

exit $global:exitCode

#end region