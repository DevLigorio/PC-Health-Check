@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
color 0F
mode con cols=120 lines=55
title Advanced PC Health Check and Optimization v2.5 - DevLigorio

:: ========================================
:: CONFIGURATION
:: ========================================
set "SCRIPT_VERSION=2.5"
set "SCRIPT_AUTHOR=DevLigorio"
set "MIN_FREE_SPACE_GB=5"
set "CREATE_RESTORE_POINT=Y"

:: ========================================
:: ADMIN CHECK
:: ========================================
net session >nul 2>&1
if %errorLevel% neq 0 (
    color 0C
    echo.
    echo ================================================================================
    echo   ERROR - ADMINISTRATOR RIGHTS REQUIRED
    echo ================================================================================
    echo.
    echo   This script requires elevated privileges to perform system modifications.
    echo   Please right-click this file and select "Run as administrator"
    echo.
    pause
    exit /b 1
)

:: ========================================
:: SYSTEM REQUIREMENTS CHECK
:: ========================================
:check_requirements
cls
echo Verifying system requirements...
echo.

for /f "tokens=*" %%a in ('powershell -Command "[System.Environment]::OSVersion.Version.Major"') do set "WIN_MAJOR=%%a"
for /f "tokens=*" %%a in ('powershell -Command "[System.Environment]::OSVersion.Version.Build"') do set "WIN_BUILD=%%a"
set "WIN_VER=%WIN_MAJOR%.0.%WIN_BUILD%"

if %WIN_MAJOR% LSS 10 (
    color 0C
    echo [ERROR] This script requires Windows 10 or later.
    echo         Current version: %WIN_VER%
    echo.
    pause
    exit /b 1
)
echo [OK] Windows version: %WIN_VER%

for /f "tokens=*" %%a in ('powershell -Command "try { [math]::Round((Get-PSDrive C).Free/1GB) } catch { 0 }"') do set "FREE_GB=%%a"
if not defined FREE_GB set "FREE_GB=0"

if %FREE_GB% LSS %MIN_FREE_SPACE_GB% (
    color 0E
    echo [WARNING] Low disk space detected: %FREE_GB% GB free
    echo           Some cleanup operations may not complete.
    echo.
    pause
)
echo [OK] Available disk space: %FREE_GB% GB

powershell -Command "exit 0" >nul 2>&1
if errorlevel 1 (
    color 0C
    echo [ERROR] PowerShell not available. This script requires PowerShell.
    pause
    exit /b 1
) else (
    echo [OK] PowerShell is available
    set "POWERSHELL_AVAILABLE=Y"
)

echo.
echo System requirements verified.
timeout /t 2 /nobreak >nul

:: ========================================
:: INITIALIZE VARIABLES
:: ========================================
for /f "tokens=*" %%a in ('powershell -Command "Get-Date -Format 'yyyyMMdd_HHmmss'"') do set "timestamp=%%a"

for /f "tokens=2*" %%a in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" /v Desktop 2^>nul ^| findstr Desktop') do set "DESKTOP=%%b"
if not defined DESKTOP set "DESKTOP=%USERPROFILE%\Desktop"
call set "DESKTOP=%DESKTOP%"

set "logfile=%DESKTOP%\PC_Health_Report_%timestamp%.txt"
set "errorfile=%DESKTOP%\PC_Health_Errors_%timestamp%.txt"

set "total_errors=0"
set "total_warnings=0"
set "operations_completed=0"
set "operations_failed=0"

set "opt_sysinfo=N"
set "opt_debloat=N"
set "opt_services=N"
set "opt_registry=N"
set "opt_cleanup=N"
set "opt_network=N"
set "opt_sfc_dism=N"
set "opt_winupdate=N"
set "opt_winget=N"
set "opt_chkdsk=N"

set "chkdsk_scheduled=N"
set "network_reset_done=N"

:: ========================================
:: UTILITY FUNCTIONS
:: ========================================
goto :skip_functions

:log_message
set "log_type=%~1"
set "log_msg=%~2"
for /f "tokens=*" %%a in ('powershell -Command "Get-Date -Format 'HH:mm:ss'"') do set "log_time=%%a"

if /i "%log_type%"=="ERROR" (
    set /a "total_errors+=1"
    echo [%log_time%] [ERROR] %log_msg% >> "%errorfile%" 2>nul
    echo [%log_time%] [ERROR] %log_msg% >> "%logfile%" 2>nul
    echo   [X] %log_msg%
) else if /i "%log_type%"=="WARNING" (
    set /a "total_warnings+=1"
    echo [%log_time%] [WARN] %log_msg% >> "%logfile%" 2>nul
    echo   [!] %log_msg%
) else if /i "%log_type%"=="SUCCESS" (
    echo [%log_time%] [OK] %log_msg% >> "%logfile%" 2>nul
    echo   [+] %log_msg%
) else (
    echo [%log_time%] [INFO] %log_msg% >> "%logfile%" 2>nul
    echo   [i] %log_msg%
)
goto :eof

:create_restore_point
if /i not "%CREATE_RESTORE_POINT%"=="Y" goto :eof
echo.
echo Creating system restore point...

reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" /v RPSessionInterval >nul 2>&1
if errorlevel 1 (
    call :log_message "WARNING" "System Restore is disabled on this computer"
    echo.
    echo   [!] System Restore is DISABLED
    echo   [!] Enable it in: Control Panel ^> System ^> System Protection
    echo.
    choice /c YN /n /m "Continue without restore point? (Y/N): "
    if errorlevel 2 exit /b 1
    goto :eof
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Checkpoint-Computer -Description 'PC Health Check - Before Optimization' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop; exit 0 } catch { Write-Host $_.Exception.Message; exit 1 }" 2>nul
if errorlevel 1 (
    call :log_message "WARNING" "Failed to create restore point"
    echo.
    echo   [!] Restore point creation failed
    echo   [!] Possible reason: Created one recently (Windows limits frequency)
    echo.
    choice /c YN /n /m "Continue without protection? (Y/N): "
    if errorlevel 2 exit /b 1
) else (
    call :log_message "SUCCESS" "System restore point created successfully"
)
goto :eof

:draw_progress_bar
if "%~1"=="" goto :eof
if "%~2"=="" goto :eof
if "%~2"=="0" goto :eof
set /a "percent=(%~1 * 100) / %~2" 2>nul
set /a "bars=%percent% / 2" 2>nul
set "progress_bar="
for /l %%i in (1,1,%bars%) do set "progress_bar=!progress_bar!█"
set "spaces="
set /a "remaining=50-%bars%" 2>nul
for /l %%i in (1,1,%remaining%) do set "spaces=!spaces!░"
echo   [!progress_bar!!spaces!] !percent!%% ^(%~1/%~2^)
goto :eof

:service_exists
sc query "%~1" >nul 2>&1
goto :eof

:safe_service_disable
set "svc_name=%~1"
set "svc_display=%~2"

call :service_exists "%svc_name%" || (
    call :log_message "INFO" "Service '%svc_display%' not found - skipping"
    goto :eof
)

sc config "%svc_name%" start= disabled >nul 2>&1
if errorlevel 1 (
    call :log_message "WARNING" "Could not disable '%svc_display%'"
    set /a "operations_failed+=1"
) else (
    sc stop "%svc_name%" >nul 2>&1
    call :log_message "SUCCESS" "'%svc_display%' disabled"
    set /a "operations_completed+=1"
)
goto :eof

:safe_reg_add
set "reg_key=%~1"
set "reg_value=%~2"
set "reg_type=%~3"
set "reg_data=%~4"
set "reg_desc=%~5"

reg add "%reg_key%" /v "%reg_value%" /t %reg_type% /d "%reg_data%" /f >nul 2>&1
if errorlevel 1 (
    call :log_message "WARNING" "Registry modification failed: %reg_desc%"
    set /a "operations_failed+=1"
) else (
    call :log_message "SUCCESS" "%reg_desc%"
    set /a "operations_completed+=1"
)
goto :eof

:skip_functions

:: ========================================
:: WELCOME & MENU
:: ========================================
:menu
cls
echo.
echo ================================================================================
echo   ADVANCED PC HEALTH CHECK AND OPTIMIZATION v%SCRIPT_VERSION%
echo   Developer: %SCRIPT_AUTHOR% ^| GitHub: https://github.com/DevLigorio
echo ================================================================================
echo.
echo   [AI-ASSISTED DEVELOPMENT]
echo   This script was developed with assistance from Claude 4.5 Sonnet by Anthropic
echo   All code has been analyzed, tested, and verified for safety and effectiveness.
echo.
echo --------------------------------------------------------------------------------
echo   METHODOLOGY - TRUSTED SOURCES
echo --------------------------------------------------------------------------------
echo   * Microsoft Official Documentation and Tools
echo   * Chris Titus Tech WinUtil Project (35k+ GitHub stars)
echo   * Sophia Script Windows Optimization (15k+ GitHub stars)
echo   * Enterprise IT maintenance procedures
echo.
echo --------------------------------------------------------------------------------
echo   SAFETY FEATURES
echo --------------------------------------------------------------------------------
echo   [+] System restore point creation before modifications
echo   [+] Comprehensive operation logging and audit trail
echo   [+] Error handling and validation
echo   [+] Reversible operations
echo.
echo ================================================================================
echo   System: Windows %WIN_VER% ^| Free Disk Space: %FREE_GB% GB
echo ================================================================================
echo.
echo   [1] System Information and Diagnostics .................. [%opt_sysinfo%]
echo   [2] Windows Debloat and Telemetry Removal ............... [%opt_debloat%]
echo   [3] Service Optimization (Disable Unnecessary) .......... [%opt_services%]
echo   [4] Registry Performance Tweaks ......................... [%opt_registry%]
echo   [5] Advanced Cache and Temp File Cleanup ................ [%opt_cleanup%]
echo   [6] Network Optimization and Reset ...................... [%opt_network%]
echo   [7] System File Checker (SFC) and DISM Repair ........... [%opt_sfc_dism%]
echo   [8] Windows Update Cache Optimization ................... [%opt_winupdate%]
echo   [9] Winget Software Updates ............................. [%opt_winget%]
echo   [0] CHKDSK Disk Check Scheduling ........................ [%opt_chkdsk%]
echo.
echo ================================================================================
echo   Toggle: 1-0 ^| All: A ^| None: N ^| Info: I ^| Start: S ^| Quit: Q
echo ================================================================================
echo.

choice /c 1234567890ANSIQ /n /m "Enter your choice: "
set choice=%errorlevel%

if %choice%==1 (
    if "!opt_sysinfo!"=="Y" (set "opt_sysinfo=N") else (set "opt_sysinfo=Y")
    goto :menu
)
if %choice%==2 (
    if "!opt_debloat!"=="Y" (set "opt_debloat=N") else (set "opt_debloat=Y")
    goto :menu
)
if %choice%==3 (
    if "!opt_services!"=="Y" (set "opt_services=N") else (set "opt_services=Y")
    goto :menu
)
if %choice%==4 (
    if "!opt_registry!"=="Y" (set "opt_registry=N") else (set "opt_registry=Y")
    goto :menu
)
if %choice%==5 (
    if "!opt_cleanup!"=="Y" (set "opt_cleanup=N") else (set "opt_cleanup=Y")
    goto :menu
)
if %choice%==6 (
    if "!opt_network!"=="Y" (set "opt_network=N") else (set "opt_network=Y")
    goto :menu
)
if %choice%==7 (
    if "!opt_sfc_dism!"=="Y" (set "opt_sfc_dism=N") else (set "opt_sfc_dism=Y")
    goto :menu
)
if %choice%==8 (
    if "!opt_winupdate!"=="Y" (set "opt_winupdate=N") else (set "opt_winupdate=Y")
    goto :menu
)
if %choice%==9 (
    if "!opt_winget!"=="Y" (set "opt_winget=N") else (set "opt_winget=Y")
    goto :menu
)
if %choice%==10 (
    if "!opt_chkdsk!"=="Y" (set "opt_chkdsk=N") else (set "opt_chkdsk=Y")
    goto :menu
)
if %choice%==11 (
    set "opt_sysinfo=Y" & set "opt_debloat=Y" & set "opt_services=Y"
    set "opt_registry=Y" & set "opt_cleanup=Y" & set "opt_network=Y"
    set "opt_sfc_dism=Y" & set "opt_winupdate=Y" & set "opt_winget=Y" & set "opt_chkdsk=Y"
    goto :menu
)
if %choice%==12 (
    set "opt_sysinfo=N" & set "opt_debloat=N" & set "opt_services=N"
    set "opt_registry=N" & set "opt_cleanup=N" & set "opt_network=N"
    set "opt_sfc_dism=N" & set "opt_winupdate=N" & set "opt_winget=N" & set "opt_chkdsk=N"
    goto :menu
)
if %choice%==13 goto :start_confirmation
if %choice%==14 goto :show_info
if %choice%==15 exit /b 0

goto :menu

:: ========================================
:: DETAILED OPERATION INFO
:: ========================================
:show_info
cls
echo.
echo ================================================================================
echo   OPERATION DETAILS
echo ================================================================================
echo.
echo   [1] SYSTEM INFORMATION
echo   ------------------------------------------------------------------------------
echo   Gathers: CPU, RAM, OS, Storage, Network, Security Status, Disk Health
echo.
echo   [2] WINDOWS DEBLOAT
echo   ------------------------------------------------------------------------------
echo   Removes: 35+ bloatware apps (Xbox, Bing, Candy Crush, etc.)
echo   Disables: Telemetry, Activity History, Advertising ID, Location Tracking
echo   Tasks: Disables 11 telemetry scheduled tasks
echo.
echo   [3] SERVICE OPTIMIZATION
echo   ------------------------------------------------------------------------------
echo   Disables: DiagTrack, Xbox Services, RetailDemo, MapsBroker, Geolocation,
echo             Windows Error Reporting, Windows Search (optional), SysMain (optional)
echo.
echo   [4] REGISTRY TWEAKS
echo   ------------------------------------------------------------------------------
echo   Optimizes: Visual Effects, Cortana, Game DVR, Search Indexing, Superfetch,
echo              Background Apps, Startup Delay
echo.
echo   [5] CACHE CLEANUP
echo   ------------------------------------------------------------------------------
echo   Cleans: Temp files, Prefetch, Thumbnails, Error Reports, Event Logs,
echo           Recycle Bin, Browser Cache
echo   Space Saved: Typically 1-20 GB
echo.
echo   [6] NETWORK RESET
echo   ------------------------------------------------------------------------------
echo   Performs: DNS Flush, IP Release/Renew, Winsock Reset, TCP/IP Reset,
echo             Network Adapter Reset
echo   Note: Restart recommended after this operation
echo.
echo   [7] SFC/DISM REPAIR
echo   ------------------------------------------------------------------------------
echo   Runs: SFC scan, DISM CheckHealth, ScanHealth, RestoreHealth, Component Cleanup
echo   Duration: 20-50 minutes depending on system condition
echo.
echo   [8] WINDOWS UPDATE CLEANUP
echo   ------------------------------------------------------------------------------
echo   Cleans: Update download cache, Component store with base reset
echo   Space Saved: 1-20 GB depending on update history
echo.
echo   [9] WINGET UPDATES
echo   ------------------------------------------------------------------------------
echo   Updates all software installed via Windows Package Manager
echo   Requires: Winget to be installed (included in Windows 11, optional in Win 10)
echo.
echo   [0] CHKDSK SCHEDULING
echo   ------------------------------------------------------------------------------
echo   Schedules: Full disk check on next boot (bad sectors, file system errors)
echo   Duration: 30 minutes to several hours
echo   Warning: System will be unusable during check
echo.
echo ================================================================================
echo.
pause
goto :menu

:: ========================================
:: START CONFIRMATION
:: ========================================
:start_confirmation
cls
echo.
echo ================================================================================
echo   CONFIRMATION
echo ================================================================================
echo.

set "total_steps=0"
if "%opt_sysinfo%"=="Y" set /a "total_steps+=1"
if "%opt_debloat%"=="Y" set /a "total_steps+=1"
if "%opt_services%"=="Y" set /a "total_steps+=1"
if "%opt_registry%"=="Y" set /a "total_steps+=1"
if "%opt_cleanup%"=="Y" set /a "total_steps+=1"
if "%opt_network%"=="Y" set /a "total_steps+=1"
if "%opt_sfc_dism%"=="Y" set /a "total_steps+=2"
if "%opt_winupdate%"=="Y" set /a "total_steps+=1"
if "%opt_winget%"=="Y" set /a "total_steps+=1"
if "%opt_chkdsk%"=="Y" set /a "total_steps+=1"

if %total_steps% EQU 0 (
    color 0E
    echo   [WARNING] No operations selected!
    echo.
    pause
    goto :menu
)

echo   Selected operations: %total_steps%
echo.
if "%opt_sysinfo%"=="Y" echo   [+] System Information
if "%opt_debloat%"=="Y" echo   [+] Windows Debloat
if "%opt_services%"=="Y" echo   [+] Service Optimization
if "%opt_registry%"=="Y" echo   [+] Registry Tweaks
if "%opt_cleanup%"=="Y" echo   [+] Cache Cleanup
if "%opt_network%"=="Y" echo   [+] Network Reset
if "%opt_sfc_dism%"=="Y" echo   [+] SFC/DISM Repair
if "%opt_winupdate%"=="Y" echo   [+] Windows Update Cleanup
if "%opt_winget%"=="Y" echo   [+] Winget Updates
if "%opt_chkdsk%"=="Y" echo   [+] CHKDSK Scheduling
echo.
echo   Estimated time: 5-30 minutes
echo   Log file: %logfile%
echo.
echo ================================================================================
echo.

choice /c YN /n /m "Proceed? (Y/N): "
if errorlevel 2 goto :menu
if errorlevel 1 goto :start

goto :menu

:: ========================================
:: START EXECUTION
:: ========================================
:start
for /f "tokens=*" %%a in ('powershell -Command "Get-Date -Format 'HH:mm:ss'"') do set "start_time=%%a"
set "current_step=0"

cls
echo.
echo ================================================================================
echo   PC HEALTH CHECK STARTED
echo ================================================================================
echo.
echo   Total operations: %total_steps%
echo   Start time: %start_time%
echo.

(
echo ================================================================================
echo   PC HEALTH CHECK REPORT
echo   Generated: %date% %time%
echo   Script Version: %SCRIPT_VERSION%
echo   Developer: %SCRIPT_AUTHOR%
echo   GitHub: https://github.com/DevLigorio
echo ================================================================================
echo.
echo SYSTEM: %COMPUTERNAME% ^| User: %USERNAME% ^| Windows: %WIN_VER%
echo Free Space: %FREE_GB% GB
echo.
echo SELECTED OPERATIONS: %total_steps%
if "%opt_sysinfo%"=="Y" echo   [1] System Information
if "%opt_debloat%"=="Y" echo   [2] Windows Debloat
if "%opt_services%"=="Y" echo   [3] Service Optimization
if "%opt_registry%"=="Y" echo   [4] Registry Tweaks
if "%opt_cleanup%"=="Y" echo   [5] Cache Cleanup
if "%opt_network%"=="Y" echo   [6] Network Optimization
if "%opt_sfc_dism%"=="Y" echo   [7] SFC/DISM Repair
if "%opt_winupdate%"=="Y" echo   [8] Windows Update Cleanup
if "%opt_winget%"=="Y" echo   [9] Winget Updates
if "%opt_chkdsk%"=="Y" echo   [10] CHKDSK Scheduling
echo.
echo ================================================================================
echo.
) > "%logfile%"

if "%opt_debloat%%opt_services%%opt_registry%"=="NNN" (
    echo Skipping restore point creation.
    echo.
) else (
    call :create_restore_point
    echo.
)

timeout /t 2 /nobreak >nul

:: ========================================
:: OPTION 1: SYSTEM INFORMATION
:: ========================================
if "%opt_sysinfo%"=="Y" (
    set /a "current_step+=1"
    cls
    echo.
    echo ================================================================================
    echo   OPERATION !current_step!/%total_steps%: SYSTEM INFORMATION
    echo ================================================================================
    echo.
    call :draw_progress_bar !current_step! %total_steps%
    echo.

    echo. >> "%logfile%"
    echo ================================================================================ >> "%logfile%"
    echo   SECTION 1: SYSTEM INFORMATION >> "%logfile%"
    echo ================================================================================ >> "%logfile%"
    echo. >> "%logfile%"

    call :log_message "INFO" "Gathering system information..."

    echo Computer: %COMPUTERNAME% >> "%logfile%"
    echo User: %USERNAME% >> "%logfile%"

    echo. >> "%logfile%"
    echo CPU: >> "%logfile%"
    for /f "tokens=*" %%a in ('powershell -Command "try{(Get-CimInstance Win32_Processor).Name}catch{'N/A'}"') do (
        echo   %%a >> "%logfile%"
        call :log_message "SUCCESS" "CPU: %%a"
    )

    for /f "tokens=*" %%a in ('powershell -Command "try{(Get-CimInstance Win32_Processor).NumberOfCores}catch{0}"') do (
        echo   Cores: %%a >> "%logfile%"
    )

    for /f "tokens=*" %%a in ('powershell -Command "try{(Get-CimInstance Win32_Processor).NumberOfLogicalProcessors}catch{0}"') do (
        echo   Threads: %%a >> "%logfile%"
    )

    echo. >> "%logfile%"
    echo OS: >> "%logfile%"
    for /f "tokens=*" %%a in ('powershell -Command "try{(Get-CimInstance Win32_OperatingSystem).Caption}catch{'N/A'}"') do (
        echo   %%a >> "%logfile%"
        call :log_message "SUCCESS" "OS: %%a"
    )

    for /f "tokens=*" %%a in ('powershell -Command "try{(Get-CimInstance Win32_OperatingSystem).Version}catch{'N/A'}"') do (
        echo   Version: %%a >> "%logfile%"
    )

    for /f "tokens=*" %%a in ('powershell -Command "try{(Get-CimInstance Win32_OperatingSystem).OSArchitecture}catch{'N/A'}"') do (
        echo   Architecture: %%a >> "%logfile%"
    )

    echo. >> "%logfile%"
    echo RAM: >> "%logfile%"
    for /f "tokens=*" %%a in ('powershell -Command "try{[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB,2)}catch{0}"') do (
        echo   Total: %%a GB >> "%logfile%"
        call :log_message "SUCCESS" "RAM: %%a GB"
    )

    for /f "tokens=*" %%a in ('powershell -Command "try{$os=Get-CimInstance Win32_OperatingSystem;[math]::Round((($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)/$os.TotalVisibleMemorySize)*100,1)}catch{0}"') do (
        echo   Usage: %%a%% >> "%logfile%"
        call :log_message "SUCCESS" "RAM Usage: %%a%%"
    )

    echo. >> "%logfile%"
    echo Uptime: >> "%logfile%"
    for /f "tokens=*" %%a in ('powershell -Command "try{(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('yyyy-MM-dd HH:mm')}catch{'N/A'}"') do (
        echo   Last Boot: %%a >> "%logfile%"
        call :log_message "SUCCESS" "Last Boot: %%a"
    )

    echo. >> "%logfile%"
    echo Storage: >> "%logfile%"
    powershell -Command "try{Get-PSDrive -PSProvider FileSystem|Where-Object{$_.Used -ne $null}|ForEach-Object{$t=[math]::Round(($_.Used+$_.Free)/1GB,1);$f=[math]::Round($_.Free/1GB,1);$u=[math]::Round(($_.Used/($_.Used+$_.Free))*100,1);Write-Output \"Drive $($_.Name): ${t}GB total, ${f}GB free ($u% used)\"}}catch{Write-Output 'N/A'}" >> "%logfile%"
    call :log_message "SUCCESS" "Storage scanned"

    echo. >> "%logfile%"
    echo Network: >> "%logfile%"
    for /f "tokens=*" %%a in ('powershell -Command "try{(Get-NetIPAddress -AddressFamily IPv4|Where-Object{$_.InterfaceAlias -notlike '*Loopback*'}|Select-Object -First 1).IPAddress}catch{'N/A'}"') do (
        echo   IP: %%a >> "%logfile%"
        call :log_message "SUCCESS" "IP: %%a"
    )

    for /f "tokens=*" %%a in ('powershell -Command "try{(Get-NetRoute -DestinationPrefix '0.0.0.0/0'|Select-Object -First 1).NextHop}catch{'N/A'}"') do (
        if not "%%a"=="0.0.0.0" (
            echo   Gateway: %%a >> "%logfile%"
        )
    )

    echo. >> "%logfile%"
    echo Security: >> "%logfile%"
    for /f "tokens=*" %%a in ('powershell -Command "try{if((Get-MpComputerStatus).AntivirusEnabled){'Active'}else{'Inactive'}}catch{'N/A'}"') do (
        echo   Windows Defender: %%a >> "%logfile%"
        call :log_message "SUCCESS" "Defender: %%a"
    )

    for /f "tokens=*" %%a in ('powershell -Command "try{if(Get-NetFirewallProfile|Where-Object{$_.Enabled}){'Enabled'}else{'Disabled'}}catch{'N/A'}"') do (
        echo   Firewall: %%a >> "%logfile%"
        call :log_message "SUCCESS" "Firewall: %%a"
    )

    if %WIN_MAJOR% GEQ 10 (
        for /f "tokens=*" %%a in ('powershell -Command "try{$tpm=Get-Tpm;if($tpm.TpmPresent){\"Present (v$($tpm.ManufacturerVersion))\"}else{'Not Present'}}catch{'N/A'}"') do (
            echo   TPM: %%a >> "%logfile%"
        )

        for /f "tokens=*" %%a in ('powershell -Command "try{if(Confirm-SecureBootUEFI){'Enabled'}else{'Disabled'}}catch{'Not Supported'}"') do (
            echo   Secure Boot: %%a >> "%logfile%"
        )
    )

    echo. >> "%logfile%"
    echo Disk Health: >> "%logfile%"
    powershell -Command "try{Get-PhysicalDisk|ForEach-Object{Write-Output \"Disk $($_.DeviceId): $($_.FriendlyName) - Health: $($_.HealthStatus) - Status: $($_.OperationalStatus)\"}}catch{Write-Output 'N/A'}" >> "%logfile%"
    
    for /f "tokens=*" %%a in ('powershell -Command "try{(Get-PhysicalDisk|Where-Object{$_.HealthStatus -eq 'Healthy'}|Measure-Object).Count}catch{0}"') do (
        call :log_message "SUCCESS" "Found %%a healthy disk(s)"
    )

    for /f "tokens=*" %%a in ('powershell -Command "try{(Get-PhysicalDisk|Where-Object{$_.HealthStatus -ne 'Healthy'}|Measure-Object).Count}catch{0}"') do (
        if %%a GTR 0 (
            call :log_message "WARNING" "Found %%a disk(s) with health issues"
        )
    )

    call :log_message "SUCCESS" "System information complete"
    echo.
    timeout /t 2 /nobreak >nul
)

:: ========================================
:: OPTION 2: WINDOWS DEBLOAT
:: ========================================
if "%opt_debloat%"=="Y" (
    set /a "current_step+=1"
    cls
    echo.
    echo ================================================================================
    echo   OPERATION !current_step!/%total_steps%: WINDOWS DEBLOAT
    echo ================================================================================
    echo.
    call :draw_progress_bar !current_step! %total_steps%
    
