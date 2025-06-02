# Brother MFC-L2820DW Printer Driver Installation

This repository contains PowerShell scripts to manage the installation and deployment of Brother MFC-L2820DW printer drivers on Windows systems. These scripts are designed for enterprise deployment scenarios but can also be used in standalone environments.

## Repository Structure

```
Printer_Drivers/
└── Brother MFC-L2820DW Printer Driver/
    ├── commands.md                       # Quick reference for installation commands
    ├── Detect-MFCL2820DW-DriverStore.ps1 # Detection script for driver presence
    ├── output/
    │   └── MFC-L2820DW_Driver-Install.intunewin  # Packaged installer for Intune
    └── source/
        ├── MFC-L2820DW_Driver-Install.ps1 # Main installation script
        └── payload/                     # Driver files
            ├── *.inf files              # Driver information files
            ├── *.dl_ files              # Compressed driver libraries
            ├── *.da_ files              # Compressed driver data
            └── dpinst.xml               # Driver installation configuration
```

## How It Works

The main PowerShell script (MFC-L2820DW_Driver-Install.ps1) handles three primary actions:

1. **Install**: Registers and installs printer drivers with the Windows Driver Repository
2. **Uninstall**: Removes driver files from the Windows Driver Repository 
3. **Update**: Updates existing drivers (extension of install process)

## Key Functions

### Logging and Error Handling

#### `global:write-LogEntry()`
Creates standardized log entries with timestamp, severity level, and contextual information.
- Parameters:
  - `$value`: Message to log
  - `$severity`: Log level (1=Info, 2=Warning, 3=Error)
  - `$fileName`: Target log file (defaults to global logFile)
- Creates proper log file format compatible with CMTrace
- Outputs logs to console and log file

#### `FatalExceptionError()`
Handles critical errors, logs them, and terminates script execution.
- Parameters:
  - `$value`: Error message to log before terminating
- Stops transcript logging and exits with code 1
- Used for unrecoverable error conditions

### Process Management

#### `Invoke-Executable()`
Safely executes external processes with proper output capture and error handling.
- Parameters:
  - `$procName`: Executable name to run
  - `$procArgs`: Command line arguments 
  - `$workingDirectory`: Directory context for execution
- Captures and logs both standard output and error streams
- Tracks exit codes and properly terminates on failures
- Ensures clean execution of system tools like pnputil.exe

### Driver Management

#### `Get-InstalledDrivers()`
Queries the Windows driver repository to identify installed drivers.
- Executes `pnputil.exe /enum-drivers` to list all drivers
- Parses output into structured PSCustomObject array
- Returns comprehensive driver information including:
  - Published Name (OEM#.inf)
  - Original Name (manufacturer.inf)
  - Provider Name
  - Class
  - Version
  - Date

#### `Write-InstallTags()`
Creates marker files to indicate successful installation.
- Creates tag files at specified paths for detection mechanisms
- Provides a lightweight method for installation verification

#### `Detect-CIMInstalled()`
Checks for application installation using Windows Management Instrumentation.
- Parameters:
  - `$appName`: Application name to search for
  - `$appVersion`: Target version to validate
- Compares installed version with required version
- Used for application-level installation checks

#### `String-Formatter()`
Utility function to parse and format strings, particularly for driver information.
- Parameters:
  - `$stringInput`: String to format
- Extracts information after colons and removes extraneous spaces
- Used for parsing command output

## Usage

### Manual Installation

```powershell
# Install the driver
.\MFC-L2820DW_Driver-Install.ps1 -action Install

# Uninstall the driver
.\MFC-L2820DW_Driver-Install.ps1 -action Uninstall

# Update the driver
.\MFC-L2820DW_Driver-Install.ps1 -action Update
```

### Installation Process Flow

1. **Initialization**
   - Script validates required parameters
   - Creates directory structure for logs and detection tags
   - Sets up transcript logging
   - Identifies driver files in the payload directory

2. **Driver Registration**
   - Scans the payload directory for INF files
   - Uses `pnputil.exe /add-driver` to register each driver with Windows
   - Waits for system to register drivers properly
   - Verifies successful installation by querying driver store
   - Creates installation tags for detection

3. **Verification**
   - Checks that all expected drivers have been registered
   - Logs success/failure information
   - Sets appropriate exit code

### Uninstallation Process Flow

1. **Driver Identification**
   - Queries current driver store using `pnputil.exe /enum-drivers`
   - Maps original INF files to their OEM-renamed equivalents
   - Identifies target drivers for removal

2. **Driver Removal**
   - For each matching driver, executes `pnputil.exe /delete-driver` with appropriate flags
   - Uses `/force` and `/uninstall` flags to ensure complete removal
   - Tracks removal counts to verify operation

3. **Cleanup**
   - Removes installation markers
   - Sets appropriate exit code

## Logging and Troubleshooting

Logs are stored at:
```terminal
C:\Windows\Temp\Intune\Brother_MFC-L2820DW_Driver\2.1.0.0\Logs\
```

Three log files are created:
- **[action]-Brother_MFC-L2820DW_Driver.log**: Primary log file with all operations
- **[action]-Brother_MFC-L2820DW_Driver-Transcript.log**: Complete PowerShell transcript with detailed execution flow
- **[action]-Brother_MFC-L2820DW_Driver-Application.log**: Application-specific logs

### Reading Logs

The main log file uses CMTrace format for easy parsing. Each entry includes:
- Timestamp with millisecond precision
- Operation date
- Component name
- Severity level
- Process ID

For troubleshooting issues:
1. Check the exit code from the script execution
2. Review the main log file for error messages (severity 3)
3. Check the transcript log for more detailed execution flow
4. Verify driver registration using `pnputil.exe /enum-drivers`

## Detection Methods

The script creates a tag file at:
```terminal
C:\Windows\Temp\Intune\Brother_MFC-L2820DW_Driver\2.1.0.0\Install\Installed.tag
```

For more reliable detection in enterprise environments:
- Use the included detection script (`Detect-MFCL2820DW-DriverStore.ps1`)
- This script checks the Windows Driver Store for specific driver files
- Returns appropriate exit codes for Intune and other management platforms

## Requirements

- Windows 10 or later
- PowerShell 5.1 or later
- Administrative privileges

## Deployment via Intune

The package includes an `.intunewin` file for deployment via Microsoft Intune with the following parameters:

**Install Command:**
```terminal
%systemroot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -executionpolicy bypass -file .\MFC-L2820DW_Driver-Install.ps1 -action Install
```

**Uninstall Command:**
```terminal
%systemroot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -executionpolicy bypass -file .\MFC-L2820DW_Driver-Install.ps1 -action Uninstall
```

**Detection Method:**
Use the included `Detect-MFCL2820DW-DriverStore.ps1` script as a custom detection script in Intune.

## Notes

- This script requires administrative privileges to run
- Drivers are installed at the system level (not user level)
- The script properly handles both 32-bit and 64-bit environments
- Exit codes:
  - 0: Success
  - Non-zero: Failure (check logs for details)
- Microsoft PnP utilities are used for driver operations to ensure compatibility
- Supports automated deployment through Intune and other management platforms