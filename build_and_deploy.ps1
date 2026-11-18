$ErrorActionPreference = "Stop"

$version = "1.10.1"
$versionCode = 53

$toolsDir = "$HOME\Documents\AISTUFF\tools"
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
$innoCompiler = "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
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
- Offline Content & Downloads: Full media downloading support with foreground notification service, local storage management, status badges, and offline launch detection
- TV Library Categories Focus Navigation: Fixed visual cursor movement and active item highlighting in categories modal and sort dialog with smooth D-pad scrolling
- Episode Detail Button Layout: Restored standard horizontal action buttons under the description on TV, removed duplicate buttons in landscape mobile view, and balanced left action buttons
- Mobile Theme Preservation: Prevented theme resets when navigating to server connection screens (such as Jellyfin), ensuring selected profile themes persist on back navigation
- Immersive Landscape Playback UI: Kept system status bar and navigation bars hidden when exiting video playback in landscape mobile orientation
- Mobile PiP & Settings Polish: Preserved continuous playback when entering PiP via swipe-home from portrait mode, preserved home row scroll position on return, and removed unneeded focus ring on mobile settings
- App Version Bump: v1.10.1 (versionCode 53)
"@

    $apkHash = (Get-FileHash -Path $apkSource -Algorithm SHA256).Hash.ToLower()
    $winHash = ""
    $installerSource = "build\installer\plix_windows.exe"
    if (Test-Path $installerSource) {
        $winHash = (Get-FileHash -Path $installerSource -Algorithm SHA256).Hash.ToLower()
    }

    $existingManifest = $null
    if (Test-Path "web_site\plix.json") {
        try {
            $existingManifest = (Get-Content "web_site\plix.json" -Raw | ConvertFrom-Json)
        } catch {}
    }

    $linuxSha = if ($existingManifest -and $existingManifest.linuxSha256) { $existingManifest.linuxSha256 } else { "" }
    $linuxArchSha = if ($existingManifest -and $existingManifest.linuxArchSha256) { $existingManifest.linuxArchSha256 } else { "" }
    $linuxTarballSha = if ($existingManifest -and $existingManifest.linuxTarballSha256) { $existingManifest.linuxTarballSha256 } else { "" }

    $manifest = [ordered]@{
        version = $version
        versionCode = $versionCode
        apkUrl = "https://github.com/Jman100/plix/releases/latest/download/plix_android.apk"
        apkSha256 = $apkHash
        windowsUrl = "https://github.com/Jman100/plix/releases/latest/download/plix_windows.exe"
        windowsArm64Url = "https://github.com/Jman100/plix/releases/latest/download/plix_windows.exe"
        windowsSha256 = $winHash
        linuxUrl = "https://github.com/Jman100/plix/releases/latest/download/plix_linux.deb"
        linuxSha256 = $linuxSha
        linuxArchUrl = "https://github.com/Jman100/plix/releases/latest/download/plix_linux_arch.pkg.tar.zst"
        linuxArchSha256 = $linuxArchSha
        linuxTarballUrl = "https://github.com/Jman100/plix/releases/latest/download/plix_linux_portable.tar.gz"
        linuxTarballSha256 = $linuxTarballSha
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

    # Automatically monitor CI, verify all release assets (Android, Windows, Linux), promote release to latest, sync checksums, and notify Discord
    Write-Host "`n=== Monitoring CI and Syncing Release Assets & Checksums ===" -ForegroundColor Cyan
    & python "scripts\monitor_release.py" "v$version"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Release monitoring or asset verification failed with code $LASTEXITCODE"
        exit $LASTEXITCODE
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
