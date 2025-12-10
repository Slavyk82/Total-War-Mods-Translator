@echo off
REM TWMT Release Script - Simple batch wrapper
REM Usage: release.cmd [version]
REM Example: release.cmd 1.2.0

setlocal enabledelayedexpansion

echo.
echo ========================================
echo        TWMT Release Script
echo ========================================
echo.

REM Check if PowerShell is available
where powershell >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] PowerShell is required but not found
    exit /b 1
)

REM Get script directory
set "SCRIPT_DIR=%~dp0"

REM Run PowerShell script with arguments
if "%~1"=="" (
    powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%release.ps1"
) else (
    powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%release.ps1" -Version "%~1" %2 %3 %4 %5
)

exit /b %ERRORLEVEL%
