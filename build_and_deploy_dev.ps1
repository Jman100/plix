$ErrorActionPreference = "Stop"

$toolsDir = "C:\Users\joshc\Documents\AISTUFF\tools"
$env:JAVA_HOME = "$toolsDir\jdk17"
$env:ANDROID_HOME = "$toolsDir\android-sdk"
$env:PATH = "$toolsDir\flutter\bin;$toolsDir\flutter\bin\cache\dart-sdk\bin;$toolsDir\git\cmd;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:ANDROID_HOME\cmdline-tools\latest\bin;$env:PATH"

$networkPlixDir = "\\192.168.0.200\appdata\apachephp8\html\plix"

Write-Host "=== Building Android APK for Dev (Phone & TV support) ===" -ForegroundColor Cyan
& "$toolsDir\flutter\bin\flutter.bat" build apk --release
if ($LASTEXITCODE -ne 0) {
    Write-Error "Flutter APK build failed with code $LASTEXITCODE"
    exit $LASTEXITCODE
}

$apkSource = "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apkSource)) {
    Write-Error "APK output file not found at $apkSource"
    exit 1
}

if (Test-Path $networkPlixDir) {
    $destApk = "$networkPlixDir\plix_android_dev.apk"
    Write-Host "Publishing Dev APK to $destApk..." -ForegroundColor Green
    Copy-Item $apkSource -Destination $destApk -Force
    $size = (Get-Item $destApk).Length
    Write-Host "Published plix_android_dev.apk ($size bytes) successfully!" -ForegroundColor Green
} else {
    Write-Warning "Network directory $networkPlixDir is not reachable."
}

# Also build Windows Dev installer
$innoCompiler = "C:\Users\joshc\AppData\Local\Programs\Inno Setup 6\ISCC.exe"
if (Test-Path $innoCompiler) {
    Write-Host "=== Building Windows Release for Dev ===" -ForegroundColor Cyan
    & "$toolsDir\flutter\bin\flutter.bat" build windows --release
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Compiling Windows Dev Installer with Inno Setup..." -ForegroundColor Cyan
        & $innoCompiler "/Fplix_windows_dev" "windows_installer.iss"
        if ($LASTEXITCODE -eq 0 -and (Test-Path "build\installer\plix_windows_dev.exe")) {
            if (Test-Path $networkPlixDir) {
                $destWin = "$networkPlixDir\plix_windows_dev.exe"
                Copy-Item "build\installer\plix_windows_dev.exe" -Destination $destWin -Force
                $winSize = (Get-Item $destWin).Length
                Write-Host "Published plix_windows_dev.exe ($winSize bytes) successfully!" -ForegroundColor Green
            }
        } else {
            Write-Warning "Inno Setup compilation for Windows Dev failed or installer missing."
        }
    } else {
        Write-Warning "Flutter Windows build failed."
    }
}

Write-Host "`n=== Dev build and deploy complete! ===" -ForegroundColor Green
Write-Host "Stable builds (plix_android_tv.apk, plix_windows.exe, plix.json) remained untouched." -ForegroundColor Yellow
