@echo off
echo ========================================================
echo   Setting up Windows Prerequisites for Flutter Desktop
echo ========================================================
echo.

:: Check for Administrator privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] This script must be run as Administrator!
    echo Please right-click setup_windows_prerequisites.bat and select "Run as administrator".
    echo.
    pause
    exit /b 1
)

echo [1/2] Enabling Windows Developer Mode (for plugin symlinks)...
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v "AllowDevelopmentWithoutDevLicense" /d 1
if %errorlevel% equ 0 (
    echo Developer Mode enabled successfully!
) else (
    echo Failed to enable Developer Mode.
)
echo.

echo [2/2] Installing Visual Studio 2022 C++ Build Tools (required for Flutter Windows)...
set "INSTALLER=%LOCALAPPDATA%\Temp\WinGet\Microsoft.VisualStudio.2022.BuildTools.17.14.42\vs_BuildTools.exe"

if not exist "%INSTALLER%" (
    echo Downloading vs_BuildTools.exe...
    curl -L "https://aka.ms/vs/17/release/vs_buildtools.exe" -o "%TEMP%\vs_BuildTools.exe"
    set "INSTALLER=%TEMP%\vs_BuildTools.exe"
)

echo Running Visual Studio Build Tools installer (this will install C++ build tools)...
echo A progress dialog may appear while components download and install.
"%INSTALLER%" --passive --wait --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended

echo.
echo ========================================================
echo   Setup completed! You can now close this window.
echo ========================================================
pause
