$ErrorActionPreference = "Stop"

$version = "1.9.2"
$versionCode = 52
$toolsDir = "$HOME\Documents\AISTUFF\tools"
$innoCompiler = "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"

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
$networkPlixDir = $env:PLIX_LOCAL_DEPLOY_DIR

# Generate and update plix.json release manifest
$releaseNotes = @"
- Profile-Specific Theme Customization: Redesigned theme selection directly into profile creation and editing workflows, ensuring profile theme isolation and preventing theme leakage onto Who's Watching
- Continue Watching Priority for New Episodes: Newly released and unplayed episodes of shows currently being watched now automatically prioritize to index 0 at the front of Continue Watching
- Arch Linux & Desktop Updater Detachment: Fully decoupled updater launches using systemd user units and process-group isolation, ensuring the updater terminal closes automatically and does not terminate Plix when exited
- TV & Mobile Navigation Polish: Unified left navigation top profile header into a single glowing interactive button; enabled mobile touch scrolling for theme selection in landscape orientation
- Virtual Keyboard & Focus Behavior: Gated profile name field auto-focus to TV only, preventing automatic virtual keyboard popup on mobile; added directional focus constraints on theme row and seamless upward traversal from Save Profile to the Theme option
- App Version Bump: v1.9.2 (versionCode 52)
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
& python "scripts\github_release.py" "v$version" "Plix v$version" "web_site\plix.json" "$($installerSource):plix_windows.exe" "web_site\plix.json:plix.json"
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
