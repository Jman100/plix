$version = "1.3.2"
$versionCode = 31
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

Write-Host "Compiling Windows x64 Installer with Inno Setup..."
& $innoCompiler "/DMyAppVersion=$version" "/DMyAppArch=x64" "/DMyAppSourceDir=build\windows\x64\runner\Release" "/DMyAppOutputBaseFilename=plix_windows" "windows_installer.iss"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Inno Setup x64 build failed"
    exit $LASTEXITCODE
}

$armSourceDir = "build\windows\arm64\runner\Release"
if (Test-Path $armSourceDir) {
    Write-Host "Compiling Windows ARM64 Installer with Inno Setup..."
    & $innoCompiler "/DMyAppVersion=$version" "/DMyAppArch=arm64" "/DMyAppSourceDir=$armSourceDir" "/DMyAppOutputBaseFilename=plix_windows_arm64" "windows_installer.iss"
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Inno Setup ARM64 build failed"
    }
}

$installerSource = "build\installer\plix_windows.exe"
$armInstallerSource = "build\installer\plix_windows_arm64.exe"
$networkPlixDir = "\\192.168.0.200\appdata\apachephp8\html\plix"

if (Test-Path $networkPlixDir) {
    Write-Host "Publishing Windows installer to network folder $networkPlixDir..."
    Copy-Item $installerSource -Destination "$networkPlixDir\plix_windows.exe" -Force
    if (Test-Path $armInstallerSource) {
        Copy-Item $armInstallerSource -Destination "$networkPlixDir\plix_windows_arm64.exe" -Force
        $armWinSize = (Get-Item "$networkPlixDir\plix_windows_arm64.exe").Length
        Write-Host "Published plix_windows_arm64.exe ($armWinSize bytes) successfully!"
    }
    if (Test-Path "web_site\index.html") {
        Copy-Item "web_site\*" -Destination "$networkPlixDir" -Recurse -Force
    }

    $manifestPath = "$networkPlixDir\plix.json"
    $releaseNotes = @"
- MPV Player for iOS: Integrated libmpv media_kit video player on iOS for native direct play of MKV, DTS, TrueHD, and advanced codecs
- iOS Playback UI: Fully resolved playback UI visibility and touch responsiveness in portrait and landscape
- Landscape Library Reordering: Added draggable grip handles on mobile landscape (Android, iOS) and Windows when reorder mode is active
- iPhone Duo Support: Added tabletop, book, and fold-clearance layouts for iPhone Duo hardware
- Version Bump: v1.3.2 (versionCode 31)
"@

    $manifest = [ordered]@{
        version = $version
        versionCode = $versionCode
        apkUrl = "https://plix.jman100.com/plix_android_tv.apk?v=$version"
        windowsUrl = "https://plix.jman100.com/plix_windows.exe?v=$version"
        windowsArm64Url = "https://plix.jman100.com/plix_windows_arm64.exe?v=$version"
        releaseNotes = $releaseNotes.Trim()
        releaseDate = (Get-Date -Format "yyyy-MM-dd")
    } | ConvertTo-Json -Depth 4

    # Write UTF-8 without a BOM so the app's jsonDecode can parse the manifest.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($manifestPath, $manifest, $utf8NoBom)
    Write-Host "Published plix_windows.exe and updated plix.json successfully to $networkPlixDir"
} else {
    Write-Warning "Network directory $networkPlixDir not reachable."
}

Write-Host "Windows build and publish completed successfully!"
