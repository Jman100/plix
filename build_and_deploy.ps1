$ErrorActionPreference = "Stop"

$version = "1.2.3"
$versionCode = 22

$toolsDir = "C:\Users\joshc\Documents\AISTUFF\tools"
$env:JAVA_HOME = "$toolsDir\jdk17"
$env:ANDROID_HOME = "$toolsDir\android-sdk"
$env:PATH = "$toolsDir\flutter\bin;$toolsDir\flutter\bin\cache\dart-sdk\bin;$toolsDir\git\cmd;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:ANDROID_HOME\cmdline-tools\latest\bin;$env:PATH"

$networkPlixDir = "\\192.168.0.200\appdata\apachephp8\html\plix"

Write-Host "=== Building Stable Release APK (v$version, versionCode $versionCode) ===" -ForegroundColor Cyan
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

# Build Windows Release Installer
$innoCompiler = "C:\Users\joshc\AppData\Local\Programs\Inno Setup 6\ISCC.exe"
if (Test-Path $innoCompiler) {
    Write-Host "`n=== Building Stable Windows Release (v$version) ===" -ForegroundColor Cyan
    & "$toolsDir\flutter\bin\flutter.bat" build windows --release
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Flutter Windows build failed with code $LASTEXITCODE"
        exit $LASTEXITCODE
    }

    Write-Host "Compiling Windows Installer with Inno Setup..." -ForegroundColor Cyan
    & $innoCompiler "windows_installer.iss"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Inno Setup compiler failed with code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
} else {
    Write-Warning "Inno Setup compiler not found at $innoCompiler, skipping Windows installer compilation."
}

if (Test-Path $networkPlixDir) {
    Write-Host "`n=== Publishing to Network Folder $networkPlixDir ===" -ForegroundColor Green

    # Publish Android APK (both plix_android_tv.apk and plix_android.apk for compatibility)
    Copy-Item $apkSource -Destination "$networkPlixDir\plix_android_tv.apk" -Force
    Copy-Item $apkSource -Destination "$networkPlixDir\plix_android.apk" -Force
    $apkSize = (Get-Item "$networkPlixDir\plix_android_tv.apk").Length
    Write-Host "Published plix_android_tv.apk ($apkSize bytes) successfully!" -ForegroundColor Green

    # Publish Windows Installer
    $installerSource = "build\installer\plix_windows.exe"
    if (Test-Path $installerSource) {
        Copy-Item $installerSource -Destination "$networkPlixDir\plix_windows.exe" -Force
        $winSize = (Get-Item "$networkPlixDir\plix_windows.exe").Length
        Write-Host "Published plix_windows.exe ($winSize bytes) successfully!" -ForegroundColor Green
    }

    # Publish Website
    if (Test-Path "web_site\index.html") {
        Copy-Item "web_site\*" -Destination "$networkPlixDir" -Recurse -Force
        Write-Host "Published website index.html and assets successfully!" -ForegroundColor Green
    }

    # Generate and publish plix.json release manifest
    $releaseNotes = @"
- Cast & Crew: Movie and episode details now show cast and crew, with actor pages listing other media from the same server
- Sidebar Reordering: Select a library to pick it up, move it with the D-pad, then select again to drop it
- Search & Metadata: Improved Jellyfin search, fixed season titles in Recently Added, and expanded Plex TV Recently Added to 50 items
- Playback: Fixed Jellyfin playback speed changes and capped oversized PGS subtitles
- Show Playback: The Play button now shows the target episode, such as Play "S8:E11"
- Home: The Continue Watching hero refreshes after playback
- Jellyfin Client Name: Plix now reports its platform name, such as Plix for Android TV
- App Version Bump: Updated to v1.2.3 (versionCode 22)
"@

    $manifest = [ordered]@{
        version = $version
        versionCode = $versionCode
        apkUrl = "https://plix.jman100.com/plix_android_tv.apk?v=$version"
        windowsUrl = "https://plix.jman100.com/plix_windows.exe?v=$version"
        releaseNotes = $releaseNotes.Trim()
        releaseDate = (Get-Date -Format "yyyy-MM-dd")
    } | ConvertTo-Json -Depth 4

    # Write UTF-8 without a BOM so the app's jsonDecode can parse the manifest.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText("$networkPlixDir\plix.json", $manifest, $utf8NoBom)
    Write-Host "Published plix.json release manifest successfully!" -ForegroundColor Green

} else {
    Write-Warning "Network directory $networkPlixDir not reachable."
}

Write-Host "`n=== Stable Build and Deploy Complete (v$version, versionCode $versionCode) ===" -ForegroundColor Green
