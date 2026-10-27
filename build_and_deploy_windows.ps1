$ErrorActionPreference = "Stop"

$version = "1.3.3"
$versionCode = 32
$toolsDir = "C:\Users\joshc\Documents\AISTUFF\tools"
$innoCompiler = "C:\Users\joshc\AppData\Local\Programs\Inno Setup 6\ISCC.exe"

$env:PATH = "$toolsDir\flutter\bin;$toolsDir\flutter\bin\cache\dart-sdk\bin;$toolsDir\git\cmd;$env:PATH"

Write-Host "Building Flutter Windows Release (v$version)..."
& "$toolsDir\flutter\bin\flutter.bat" build windows --release
if ($LASTEXITCODE -ne 0) {
    Write-Error "Flutter Windows build failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

if (-not (Test-Path $innoCompiler)) {
    Write-Error "Inno Setup compiler not found at $innoCompiler"
    exit 1
}

Write-Host "Compiling Unified Windows Installer (x64 & ARM64) with Inno Setup..."
& $innoCompiler "/DMyAppVersion=$version" "/DMyAppOutputBaseFilename=plix_windows" "windows_installer.iss"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Inno Setup compilation failed"
    exit $LASTEXITCODE
}

$installerSource = "build\installer\plix_windows.exe"
$networkPlixDir = "\\192.168.0.200\appdata\apachephp8\html\plix"

# Generate and update plix.json release manifest
$releaseNotes = @"
- MPV Player for iOS: Integrated libmpv media_kit video player on iOS for native direct play of MKV, DTS, TrueHD, and advanced codecs
- iOS Playback UI: Fully resolved playback UI visibility and touch responsiveness in portrait and landscape
- Landscape Library Reordering: Added draggable grip handles on mobile landscape (Android, iOS) and Windows when reorder mode is active
- iPhone Duo Support: Added tabletop, book, and fold-clearance layouts for iPhone Duo hardware
- Windows Native ARM64: Redesigned Windows build with native ARM64 support and unified dual-architecture installer
- Windows on ARM Playback: Fixed black screen on Windows for ARM (Direct3D 12_1/12_0 & updated ANGLE swapchain rendering pipeline)
- Episode HDR Badges: Specific HDR format display (HDR10, HDR10+, Dolby Vision, HLG) on episodes across all views
- Continue Watching Hero Duration: Added media content runtime length to the hero detail section
- Version Bump: v1.3.3 (versionCode 32)
"@

$manifest = [ordered]@{
    version = $version
    versionCode = $versionCode
    apkUrl = "https://github.com/Jman100/plix/releases/latest/download/plix_android.apk"
    windowsUrl = "https://github.com/Jman100/plix/releases/latest/download/plix_windows.exe"
    windowsArm64Url = "https://github.com/Jman100/plix/releases/latest/download/plix_windows.exe"
    releaseNotes = $releaseNotes.Trim()
    releaseDate = (Get-Date -Format "yyyy-MM-dd")
} | ConvertTo-Json -Depth 4

# Write UTF-8 without a BOM so the app's jsonDecode can parse the manifest.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText("web_site\plix.json", $manifest, $utf8NoBom)
Write-Host "Updated web_site\plix.json successfully!" -ForegroundColor Green

# Publish to GitHub Releases
Write-Host "`n=== Publishing to GitHub Releases (v$version) ===" -ForegroundColor Cyan
& python "scripts\github_release.py" "v$version" "Plix v$version" "web_site\plix.json" "$installerSource:plix_windows.exe" "web_site\plix.json:plix.json"
if ($LASTEXITCODE -ne 0) {
    Write-Warning "GitHub release upload exited with code $LASTEXITCODE"
} else {
    Write-Host "Published Windows installer to GitHub Releases successfully!" -ForegroundColor Green
}

# Optional local network mirror (if available)
if (Test-Path $networkPlixDir) {
    Write-Host "Mirroring to local network folder $networkPlixDir..."
    Copy-Item $installerSource -Destination "$networkPlixDir\plix_windows.exe" -Force
    Copy-Item $installerSource -Destination "$networkPlixDir\plix_windows_arm64.exe" -Force
    if (Test-Path "web_site\index.html") {
        Copy-Item "web_site\*" -Destination "$networkPlixDir" -Recurse -Force
    }
    [System.IO.File]::WriteAllText("$networkPlixDir\plix.json", $manifest, $utf8NoBom)
    Write-Host "Mirrored to local network folder successfully!" -ForegroundColor Green
}

Write-Host "Windows build and publish completed successfully!" -ForegroundColor Green
