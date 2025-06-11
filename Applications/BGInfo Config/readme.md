# BGInfo Configuration Installer

This PowerShell script automates the deployment and management of BGInfo configuration files and startup shortcuts for Windows systems. It's designed for enterprise deployment through Microsoft Intune or similar management systems, but can also be used standalone.

## Table of Contents

- Overview
- Requirements
- Usage
- Script Components
  - Key Functions
  - Process Flow
- Configuration
- Logging
- Troubleshooting

## Overview

The SCC-BGInfo-Config-Install.ps1 script provides a robust solution for deploying and managing BGInfo configurations across multiple systems. It handles the installation of configuration files, creates necessary folders, and sets up automatic startup shortcuts with proper icons and arguments.

## Requirements

- Windows 10/11 or Windows Server 2016+
- PowerShell 5.1 or later
- Administrative privileges
- BGInfo must be pre-installed in the standard Program Files location

## Usage

The script accepts one mandatory parameter:

```powershell
.\SCC-BGInfo-Config-Install.ps1 -action <Action>
```

Where `<Action>` is one of:
- `Install`: Deploys configuration files and creates shortcuts
- `Uninstall`: Removes configuration files and shortcuts
- `Update`: Updates existing configuration (behaves like Install)

### Examples

```powershell
# Install BGInfo configuration
.\SCC-BGInfo-Config-Install.ps1 -action Install

# Remove BGInfo configuration
.\SCC-BGInfo-Config-Install.ps1 -action Uninstall
```

### Using with Intune

For Microsoft Intune deployment:

**Install command:**
```
powershell.exe -executionpolicy bypass -file SCC-BGInfo-Config-Install.ps1 -action Install
```

**Uninstall command:**
```
powershell.exe -executionpolicy bypass -file SCC-BGInfo-Config-Install.ps1 -action Uninstall
```

## Script Components

### Key Functions

| Function | Description |
|----------|-------------|
| `global:write-LogEntry` | Creates standardized log entries with timestamp and severity |
| `FatalExceptionError` | Logs critical errors and terminates script execution |
| `Invoke-Executable` | Safely executes external processes with output logging |
| `Write-InstallTags` | Creates marker files for installation detection |
| `Delete-File` | Safely removes files with proper error handling |
| `Delete-Folder` | Removes folders and their contents |
| `Create-Folder` | Creates directories with proper permissions |
| `Copy-File` | Copies files with overwrite capability |
| `Create-Shortcut` | Creates Windows shortcuts with custom properties |

#### Create-Shortcut Function

The `Create-Shortcut` function is a key component that creates the Windows shortcut to launch BGInfo with the specified configuration. It handles:

- Custom icon selection (including executable icons with indexes)
- Command-line arguments
- Working directory configuration
- Automatic cleanup of existing shortcuts

```powershell
Create-Shortcut -shortcutName "BGInfo" `
               -shortcutIconPath "C:\Program Files\BGinfo\Bginfo64.exe,0" `
               -shortcutPath "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp" `
               -shortcutExePath "C:\Program Files\BGinfo\Bginfo64.exe" `
               -shortcutExeArgs "C:\ProgramData\BGinfo\BGInfoConfig.bgi /silent /timer:0 /nolicprompt" `
               -shortcutExeWorkingDir "C:\ProgramData\BGinfo"
```

### Process Flow

#### Installation Process

1. **Preparation**
   - Script creates log and installation directories
   - Validates BGInfo is installed at expected location

2. **Configuration Deployment**
   - Creates configuration directory if needed
   - Removes existing configuration files if present
   - Copies new configuration file from source location

3. **Shortcut Creation**
   - Removes existing shortcut if present
   - Creates new shortcut in Windows startup folder
   - Configures shortcut with proper icon, arguments, and working directory

4. **Finalization**
   - Creates installation tag for detection
   - Logs completion status

#### Uninstallation Process

1. **Cleanup**
   - Removes configuration files
   - Removes shortcuts from startup folder

2. **Finalization**
   - Logs completion status

## Configuration

The script uses the following default paths that can be modified in the script variables section:

```powershell
$rootInstallPath = [System.Environment]::GetFolderPath("CommonApplicationData") + "\BGinfo" 
$configInstallPath = "$rootInstallPath\BGInfoConfig_2025_QLD.bgi"
$rootBGInfoInstallPath = [System.Environment]::GetFolderPath("ProgramFiles") + "\BGinfo\Bginfo64.exe"
$shortcutInstallPath = [System.Environment]::GetFolderPath("CommonApplicationData") + 
                       "\Microsoft\Windows\Start Menu\Programs\StartUp"
```

## Logging

The script creates detailed logs in three forms:

1. **Main Log**: Records all operations with timestamps and severity levels
   - Location: `C:\Windows\Temp\Intune\SCC_BGInfo_Config_Install_QLD\1.00\Logs\[action]-SCC_BGInfo_Config_Install_QLD.log`

2. **Transcript Log**: Full PowerShell transcript
   - Location: `C:\Windows\Temp\Intune\SCC_BGInfo_Config_Install_QLD\1.00\Logs\[action]-SCC_BGInfo_Config_Install_QLD-Transcript.log`

3. **Installation Tag**: Simple marker file for installation detection
   - Location: `C:\Windows\Temp\Intune\SCC_BGInfo_Config_Install_QLD\1.00\Install\Installed.tag`

The logs are formatted to be compatible with CMTrace for easy viewing and filtering.

## Troubleshooting

### Common Issues

1. **Error: "Value does not fall within the expected range"**
   - Issue: Typically occurs with shortcut creation when icon paths are incorrectly formatted
   - Solution: Ensure icon path uses the format "path\to\file.exe,0" for executable icons

2. **Error: "The file does not exist"**
   - Issue: BGInfo is not installed or not in the expected location
   - Solution: Verify BGInfo installation at `C:\Program Files\BGinfo\Bginfo64.exe`

3. **BGInfo doesn't start automatically**
   - Issue: Shortcut may not be created in the startup folder
   - Solution: Check the shortcut exists in `C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp`

### Exit Codes

- **0**: Success
- **1**: Fatal error (check logs for details)