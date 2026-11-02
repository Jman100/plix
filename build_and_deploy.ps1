$ErrorActionPreference = "Stop"

$version = "1.6.0"
$versionCode = 39

$toolsDir = "C:\Users\joshc\Documents\AISTUFF\tools"
$env:JAVA_HOME = "$toolsDir\jdk17"
$env:ANDROID_HOME = "$toolsDir\android-sdk"
$env:PATH = "$toolsDir\flutter\bin;$toolsDir\flutter\bin\cache\dart-sdk\bin;$toolsDir\git\cmd;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:ANDROID_HOME\cmdline-tools\latest\bin;$env:PATH"

$networkPlixDir = $env:PLIX_LOCAL_DEPLOY_DIR

Write-Host "=== Building Stable Release APK (v$version, versionCode $versionCode) ===" -ForegroundColor Cyan
& "$toolsDir\flutter\bin\flutter.bat" build apk --release --build-name=$version --build-number=$versionCode
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
    & "$toolsDir\flutter\bin\flutter.bat" build windows --release --build-name=$version --build-number=$versionCode
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Flutter Windows build failed with code $LASTEXITCODE"
        exit $LASTEXITCODE
    }

    Write-Host "Compiling Unified Windows Installer (x64 & ARM64) with Inno Setup..." -ForegroundColor Cyan
    & $innoCompiler "/DMyAppVersion=$version" "/DMyAppOutputBaseFilename=plix_windows" "windows_installer.iss"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Inno Setup compiler failed with code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
} else {
    Write-Warning "Inno Setup compiler not found at $innoCompiler, skipping Windows installer compilation."
}

    # Generate and publish plix.json release manifest
    $releaseNotes = @"
- Unified Multi-Server & Favorite Libraries: Blend libraries and Continue Watching across multiple connected Plex and Jellyfin servers simultaneously; customizable Favorite Libraries manager with smart ownership defaulting and minimum library selection protection
- First-Time Install Welcome Tour: Introduced a streamlined, platform-tailored welcome walkthrough on TV, mobile, and desktop; TV edition features a 2x2 grid displaying all key features on screen at once with full remote cursor lock
- Four New Atmosphere Themes: Added Solar Flare, Neon Cyberpunk, Nordic Frost, and Emerald Forest to the visual styling collection (16 total presets plus custom themes)
- Crystal Liquid Glass Redesign: Overhauled the Liquid Glass atmosphere theme with transparent frosted glass surfaces, high-contrast borders, and clean button states
- Remote Navigation & TV Polish: Fixed playback overlay directional remote navigation, eliminated TV settings appearance header cutoff, refined TV reorder libraries button states, and optimized vertical row spacing
- Redesigned Sign Out Confirmation: Rebalanced modal with equal button weighting, increased vertical spacing, and default focus on cancel
- App Version Bump: v1.6.0 (versionCode 39)
"@

    $manifest = [ordered]@{
        version = $version
        versionCode = $versionCode
        apkUrl = "https://github.com/Jman100/plix/releases/latest/download/plix_android.apk"
        windowsUrl = "https://github.com/Jman100/plix/releases/latest/download/plix_windows.exe"
        windowsArm64Url = "https://github.com/Jman100/plix/releases/latest/download/plix_windows.exe"
        linuxUrl = "https://github.com/Jman100/plix/releases/latest/download/plix_linux.deb"
        linuxArchUrl = "https://github.com/Jman100/plix/releases/latest/download/plix_linux_arch.pkg.tar.zst"
        linuxTarballUrl = "https://github.com/Jman100/plix/releases/latest/download/plix_linux_portable.tar.gz"
        releaseNotes = $releaseNotes.Trim()
        releaseDate = (Get-Date -Format "yyyy-MM-dd")
    } | ConvertTo-Json -Depth 4

    # Write UTF-8 without a BOM so the app's jsonDecode can parse the manifest.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText("web_site\plix.json", $manifest, $utf8NoBom)
    Write-Host "Updated web_site\plix.json successfully!" -ForegroundColor Green

    # Publish to GitHub Releases
    Write-Host "`n=== Publishing to GitHub Releases (v$version) ===" -ForegroundColor Cyan
    $installerSource = "build\installer\plix_windows.exe"
    $filesToUpload = @(
        "$($apkSource):plix_android.apk",
        "web_site\plix.json:plix.json"
    )
    if (Test-Path $installerSource) {
        $filesToUpload += "$($installerSource):plix_windows.exe"
    }

    & python "scripts\github_release.py" "v$version" "Plix v$version" "web_site\plix.json" @filesToUpload
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "GitHub release upload exited with code $LASTEXITCODE"
    } else {
        Write-Host "Published to GitHub Releases successfully!" -ForegroundColor Green
    }

    # Optional local network mirror (if available)
    if ($networkPlixDir -and (Test-Path $networkPlixDir)) {
        Write-Host "`n=== Mirroring to Local Network Folder $networkPlixDir ===" -ForegroundColor Yellow
        Copy-Item $apkSource -Destination "$networkPlixDir\plix_android.apk" -Force
        if (Test-Path $installerSource) {
            Copy-Item $installerSource -Destination "$networkPlixDir\plix_windows.exe" -Force
            Copy-Item $installerSource -Destination "$networkPlixDir\plix_windows_arm64.exe" -Force
        }
        if (Test-Path "web_site\index.html") {
            Copy-Item "web_site\*" -Destination "$networkPlixDir" -Recurse -Force
        }
        [System.IO.File]::WriteAllText("$networkPlixDir\plix.json", $manifest, $utf8NoBom)
        Write-Host "Mirrored to local network folder successfully!" -ForegroundColor Green
    }

Write-Host "`n=== Stable Build and Deploy Complete (v$version, versionCode $versionCode) ===" -ForegroundColor Green
