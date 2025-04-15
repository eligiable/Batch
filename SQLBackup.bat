@echo off
cls
setlocal enabledelayedexpansion

:: ************************************
:: * Database Backup Script           *
:: * Enhanced with error handling and *
:: * logging capabilities             *
:: ************************************

:: Configuration Section - Set these variables to the desired values
set SqlServer=Server_Name
set InstanceName=MSSQLSERVER
set Username=sa
set Password=Password
set Database=DB_Name
set LocalFolder=D:\Temp
set NetworkFolder=\\Server\SQL Server Backup\
set LogFolder=D:\BackupLogs
set RetentionDays=30

:: ************************************
:: * Don't modify below this line    *
:: * unless you know what you're doing*
:: ************************************

:: Initialize variables
set ScriptName=%~n0
set Timestamp=%date%_%time%
set Timestamp=%Timestamp:/=-%
set Timestamp=%Timestamp::=-%
set Timestamp=%Timestamp: =_%
set LogFile=%LogFolder%\%ScriptName%_%Timestamp%.log

:: Create log folder if it doesn't exist
if not exist "%LogFolder%" (
    mkdir "%LogFolder%"
    if errorlevel 1 (
        echo ERROR: Failed to create log folder %LogFolder%
        exit /b 1
    )
)

:: Redirect output to log file
>> "%LogFile%" (
    echo *******************************************************
    echo * Backup Script Started: %date% %time%
    echo *******************************************************

    :: Verify SQL Server connection
    echo Testing SQL Server connection...
    sqlcmd -S %SqlServer% -U %Username% -P %Password% -Q "SELECT GETDATE() AS 'ConnectionTest'" -b
    if errorlevel 1 (
        echo ERROR: Failed to connect to SQL Server
        exit /b 1
    )
    echo SQL Server connection successful.
    echo.

    :: Get current datetime
    echo Getting current date and time...
    for /f %%a in ('sqlcmd -S %SqlServer% -U %Username% -P %Password% -Q "SET NOCOUNT ON; SELECT CONVERT(VARCHAR(10), GETDATE(), 120)" -h -1') do set CurrentDate=%%a
    for /f %%a in ('sqlcmd -S %SqlServer% -U %Username% -P %Password% -Q "SET NOCOUNT ON; SELECT RIGHT('0' + CAST(DATEPART(HOUR, GETDATE()) AS VARCHAR(2)), 2)" -h -1') do set CurrentHour=%%a
    for /f %%a in ('sqlcmd -S %SqlServer% -U %Username% -P %Password% -Q "SET NOCOUNT ON; SELECT RIGHT('0' + CAST(DATEPART(MINUTE, GETDATE()) AS VARCHAR(2)), 2)" -h -1') do set CurrentMinute=%%a
    for /f %%a in ('sqlcmd -S %SqlServer% -U %Username% -P %Password% -Q "SET NOCOUNT ON; SELECT RIGHT('0' + CAST(DATEPART(SECOND, GETDATE()) AS VARCHAR(2)), 2)" -h -1') do set CurrentSecond=%%a

    set BackupFile=%Database%-%CurrentDate%_%CurrentHour%%CurrentMinute%%CurrentSecond%.bak
    set LocalBackupPath=%LocalFolder%\%BackupFile%
    set NetworkBackupPath=%NetworkFolder%\%BackupFile%

    echo Current timestamp: %CurrentDate% %CurrentHour%:%CurrentMinute%:%CurrentSecond%
    echo Backup file name: %BackupFile%
    echo.

    :: Verify local folder exists
    if not exist "%LocalFolder%" (
        echo Creating local folder %LocalFolder%...
        mkdir "%LocalFolder%"
        if errorlevel 1 (
            echo ERROR: Failed to create local folder %LocalFolder%
            exit /b 1
        )
    )

    :: Perform database backup
    echo Backing up database %Database% to %LocalBackupPath%
    sqlcmd -S %SqlServer% -U %Username% -P %Password% -Q "BACKUP DATABASE [%Database%] TO DISK='%LocalBackupPath%' WITH COMPRESSION, STATS=10, CHECKSUM"
    if errorlevel 1 (
        echo ERROR: Database backup failed
        exit /b 1
    )
    echo Backup completed successfully.
    echo.

    :: Verify backup file was created
    if not exist "%LocalBackupPath%" (
        echo ERROR: Backup file not found at %LocalBackupPath%
        exit /b 1
    )

    :: Verify network folder is accessible
    echo Verifying network folder access...
    dir "%NetworkFolder%" >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Cannot access network folder %NetworkFolder%
        exit /b 1
    )
    echo Network folder accessible.
    echo.

    :: Copy backup to network location
    echo Copying backup to network location %NetworkBackupPath%
    copy /Y "%LocalBackupPath%" "%NetworkBackupPath%"
    if errorlevel 1 (
        echo ERROR: Failed to copy backup to network location
        exit /b 1
    )
    echo Backup copied to network location successfully.
    echo.

    :: Verify network copy
    echo Verifying network copy...
    dir "%NetworkBackupPath%" >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Backup file not found at network location %NetworkBackupPath%
        exit /b 1
    )
    echo Network copy verified successfully.
    echo.

    :: Clean up local backup
    echo Cleaning up local backup file...
    del "%LocalBackupPath%"
    if exist "%LocalBackupPath%" (
        echo WARNING: Failed to delete local backup file
    ) else (
        echo Local backup file cleaned up successfully.
    )
    echo.

    :: Clean up old log files
    echo Cleaning up log files older than %RetentionDays% days...
    forfiles /P "%LogFolder%" /M "%ScriptName%_*.log" /D -%RetentionDays% /C "cmd /c echo Deleting @file... && del @file"
    echo Log cleanup completed.
    echo.

    :: Script completed successfully
    echo *******************************************************
    echo * Backup Script Completed Successfully: %date% %time%
    echo *******************************************************
)

:: Display log file contents
type "%LogFile%"

endlocal