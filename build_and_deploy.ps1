$ErrorActionPreference = "Stop"

$version = "1.9.2"
$versionCode = 52

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
- Profile-Specific Theme Customization: Redesigned theme selection directly into profile creation and editing workflows, ensuring profile theme isolation and preventing theme leakage onto Who's Watching
- Continue Watching Priority for New Episodes: Newly released and unplayed episodes of shows currently being watched now automatically prioritize to index 0 at the front of Continue Watching
- Arch Linux & Desktop Updater Detachment: Fully decoupled updater launches using systemd user units and process-group isolation, ensuring the updater terminal closes automatically and does not terminate Plix when exited
- TV & Mobile Navigation Polish: Unified left navigation top profile header into a single glowing interactive button; enabled mobile touch scrolling for theme selection in landscape orientation
- Virtual Keyboard & Focus Behavior: Gated profile name field auto-focus to TV only, preventing automatic virtual keyboard popup on mobile; added directional focus constraints on theme row and seamless upward traversal from Save Profile to the Theme option
- App Version Bump: v1.9.2 (versionCode 52)
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

    # Automatically verify and sync release manifest checksums from actual release assets
    Write-Host "`n=== Syncing Checksums Manifest with Live Release Assets ===" -ForegroundColor Cyan
    & python "scripts\sync_release_checksums.py" "v$version"

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
