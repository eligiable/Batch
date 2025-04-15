@echo off
:: =====================================================
:: mysqlbackup.cmd v2.0 for Windows
:: Enhanced version with error handling, logging, and more
:: =====================================================

:: Set console window title
title MySQL Backup Utility v2.0

:: Check for administrative privileges
NET FILE >nul 2>&1
if ERRORLEVEL 1 (
    echo ERROR: This script requires administrative privileges.
    echo Please run as Administrator.
    pause
    goto :EOF
)

:: Display help if requested or no parameters
if "%1"=="/?" goto :HELP
if "%1"=="--help" goto :HELP
if "%1"=="-help" goto :HELP
if "%1"=="-h" goto :HELP
if "%1"=="" goto :HELP
goto :CONFIG

:HELP
echo.
echo MySQL Backup Utility v2.0
echo ========================
echo.
echo Backup MySQL database(s) with optional compression and logging.
echo.
echo Syntax: mysqlbackup [options] ^<databaseName^|-all^> [^<zip^|gzip^|tar^|7z^>]
echo.
echo Options:
echo   /verbose    Enable detailed output during backup
echo   /log        Create a log file in the backup directory
echo   /noprompt   Run without confirmation prompts
echo.
echo Compression formats supported: zip, gzip, tar, 7z
echo.
echo Examples:
echo   mysqlbackup mydatabase
echo   mysqlbackup -all 7z /log
echo   mysqlbackup inventory zip /verbose
goto :EOF

:CONFIG
:: =====================================================
:: Configuration Section - Edit these values as needed
:: =====================================================
SETLOCAL EnableDelayedExpansion

:: MySQL Configuration
set dbHost=localhost
set dbUser=root
set dbPassword="Password"

:: Path Configuration
set backupRoot="D:\MySQL_Backups"
set mysql="C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"
set mysqldump="C:\Program Files\MySQL\MySQL Server 8.0\bin\mysqldump.exe"
set zip="C:\Program Files\7-Zip\7z.exe"

:: Backup Settings
set defaultRetentionDays=30
set excludeDatabases=information_schema performance_schema mysql sys

:: =====================================================
:: Validate Configuration
:: =====================================================
if "%dbUser%"=="" (
    echo ERROR: Database user not configured.
    goto :CONFIG_ERROR
)

if not exist %mysql% (
    echo ERROR: MySQL client not found at: %mysql%
    goto :CONFIG_ERROR
)

if not exist %mysqldump% (
    echo ERROR: MySQLDump not found at: %mysqldump%
    goto :CONFIG_ERROR
)

if not exist %backupRoot% (
    echo Creating backup root directory...
    mkdir %backupRoot%
    if ERRORLEVEL 1 (
        echo ERROR: Failed to create backup directory: %backupRoot%
        goto :CONFIG_ERROR
    )
)

if not exist %zip% (
    echo WARNING: 7-Zip not found. Compression will be disabled.
    set compressionAvailable=false
) else (
    set compressionAvailable=true
)

:: =====================================================
:: Parse Command Line Arguments
:: =====================================================
set verbose=false
set createLog=false
set noPrompt=false
set compressionFormat=

:ARG_LOOP
if "%1"=="" goto ARG_END
if /i "%1"=="/verbose" set verbose=true
if /i "%1"=="/log" set createLog=true
if /i "%1"=="/noprompt" set noPrompt=true
for %%A in (zip gzip tar 7z) do if /i "%1"=="%%A" set compressionFormat=%%A
shift
goto ARG_LOOP
:ARG_END

:: If compression was specified as the second parameter (old syntax)
if not defined compressionFormat if not "%2"=="" (
    for %%A in (zip gzip tar 7z) do if /i "%2"=="%%A" set compressionFormat=%2
)

:: Validate compression format if specified
if defined compressionFormat if "%compressionAvailable%"=="false" (
    echo ERROR: Compression requested but 7-Zip not available.
    goto :CONFIG_ERROR
)

:: =====================================================
:: Initialize Backup
:: =====================================================
:: Create timestamp for this backup session
for /f "tokens=2 delims==" %%G in ('wmic OS GET LocalDateTime /value') do set ldt=%%G
set backupDate=%ldt:~0,4%-%ldt:~4,2%-%ldt:~6,2%
set backupTime=%ldt:~8,2%-%ldt:~10,2%-%ldt:~12,2%
set backupDir=%backupRoot%\%backupDate%_%backupTime%

:: Create backup directory
if not exist "%backupDir%" (
    if "%verbose%"=="true" echo Creating backup directory: %backupDir%
    mkdir "%backupDir%"
    if ERRORLEVEL 1 (
        echo ERROR: Failed to create backup directory: %backupDir%
        goto :CONFIG_ERROR
    )
)

:: Initialize log file if requested
if "%createLog%"=="true" (
    set logFile=%backupDir%\backup_log_%backupDate%_%backupTime%.txt
    echo MySQL Backup Log > "%logFile%"
    echo =============== >> "%logFile%"
    echo Date: %backupDate% %backupTime% >> "%logFile%"
    echo Backup Directory: %backupDir% >> "%logFile%"
    echo. >> "%logFile%"
)

:: Display backup information
echo.
echo MySQL Backup Utility v2.0
echo ========================
echo Backup Directory: %backupDir%
if defined compressionFormat echo Compression: %compressionFormat%
if "%createLog%"=="true" echo Log File: %logFile%
echo.

:: Confirm operation if not in no-prompt mode
if "%noPrompt%"=="false" (
    set /p confirm="Proceed with backup? (Y/N) "
    if /i not "%confirm%"=="Y" goto :EOF
)

:: =====================================================
:: Backup Execution
:: =====================================================
if "%1"=="-all" goto :ALL_DATABASES
goto :SINGLE_DATABASE

:SINGLE_DATABASE
set dbName=%1
if "%verbose%"=="true" (
    echo Backing up single database: %dbName%
    if "%createLog%"=="true" (
        echo [%time%] Backing up single database: %dbName% >> "%logFile%"
    )
)

%mysqldump% --host=%dbHost% --user=%dbUser% --password=%dbPassword% --single-transaction --add-drop-table --databases %dbName% > "%backupDir%\%dbName%.sql"
if ERRORLEVEL 1 (
    echo ERROR: Failed to backup database %dbName%
    if "%createLog%"=="true" (
        echo [%time%] ERROR: Failed to backup database %dbName% >> "%logFile%"
    )
    goto :BACKUP_ERROR
)

if defined compressionFormat (
    if "%verbose%"=="true" (
        echo Compressing %dbName%.sql to %compressionFormat% format
        if "%createLog%"=="true" (
            echo [%time%] Compressing %dbName%.sql to %compressionFormat% format >> "%logFile%"
        )
    )
    "%zip%" a -t%compressionFormat% "%backupDir%\%dbName%.sql.%compressionFormat%" "%backupDir%\%dbName%.sql" >nul
    if ERRORLEVEL 1 (
        echo WARNING: Failed to compress %dbName%.sql
        if "%createLog%"=="true" (
            echo [%time%] WARNING: Failed to compress %dbName%.sql >> "%logFile%"
        )
    ) else (
        del "%backupDir%\%dbName%.sql"
        if "%verbose%"=="true" echo Compression complete
    )
)

goto :BACKUP_SUCCESS

:ALL_DATABASES
if "%verbose%"=="true" (
    echo Backing up all databases (except system databases)
    if "%createLog%"=="true" (
        echo [%time%] Backing up all databases (except system databases) >> "%logFile%"
    )
)

%mysql% --host=%dbHost% --user=%dbUser% --password=%dbPassword% --skip-column-names --execute="SHOW DATABASES" | findstr /V /I "%excludeDatabases%" > "%backupDir%\database_list.txt"

for /F "tokens=*" %%f in ('type "%backupDir%\database_list.txt"') do (
    if "%verbose%"=="true" (
        echo Backing up database: %%f
        if "%createLog%"=="true" (
            echo [%time%] Backing up database: %%f >> "%logFile%"
        )
    )
    
    %mysqldump% --host=%dbHost% --user=%dbUser% --password=%dbPassword% --single-transaction --add-drop-table --databases %%f > "%backupDir%\%%f.sql"
    if ERRORLEVEL 1 (
        echo ERROR: Failed to backup database %%f
        if "%createLog%"=="true" (
            echo [%time%] ERROR: Failed to backup database %%f >> "%logFile%"
        )
    ) else (
        if defined compressionFormat (
            if "%verbose%"=="true" (
                echo Compressing %%f.sql to %compressionFormat% format
                if "%createLog%"=="true" (
                    echo [%time%] Compressing %%f.sql to %compressionFormat% format >> "%logFile%"
                )
            )
            "%zip%" a -t%compressionFormat% "%backupDir%\%%f.sql.%compressionFormat%" "%backupDir%\%%f.sql" >nul
            if ERRORLEVEL 1 (
                echo WARNING: Failed to compress %%f.sql
                if "%createLog%"=="true" (
                    echo [%time%] WARNING: Failed to compress %%f.sql >> "%logFile%"
                )
            ) else (
                del "%backupDir%\%%f.sql"
                if "%verbose%"=="true" echo Compression complete
            )
        )
    )
)

del "%backupDir%\database_list.txt"
goto :BACKUP_SUCCESS

:BACKUP_SUCCESS
echo.
echo Backup completed successfully.
if "%createLog%"=="true" (
    echo [%time%] Backup completed successfully >> "%logFile%"
    echo. >> "%logFile%"
    echo Total backup size: >> "%logFile%"
    dir "%backupDir%" | find "File(s)" >> "%logFile%"
)
echo.
dir "%backupDir%"
goto :CLEANUP

:BACKUP_ERROR
echo.
echo Backup completed with errors.
if "%createLog%"=="true" (
    echo [%time%] Backup completed with errors >> "%logFile%"
)
goto :CLEANUP

:CONFIG_ERROR
echo.
echo Configuration error detected. Please check your settings.
goto :CLEANUP

:CLEANUP
:: Clean up old backups (retention policy)
if "%verbose%"=="true" (
    echo.
    echo Cleaning up backups older than %defaultRetentionDays% days...
)

forfiles /P "%backupRoot%" /M "*" /D -%defaultRetentionDays% /C "cmd /c if @isdir==TRUE (echo Deleting old backup @file & rd /s /q @path)"
if ERRORLEVEL 1 (
    if "%verbose%"=="true" (
        echo No old backups found or error during cleanup
    )
)

:: Final message
echo.
echo MySQL Backup Utility finished.
if "%createLog%"=="true" (
    echo Detailed log available at: %logFile%
)
echo.

pause
ENDLOCAL
goto :EOF