$version = "1.2.2"
$versionCode = 21
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

Write-Host "Compiling Windows Installer with Inno Setup..."
& $innoCompiler "windows_installer.iss"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Inno Setup build failed"
    exit $LASTEXITCODE
}

$installerSource = "build\installer\plix_windows.exe"
$networkPlixDir = "\\192.168.0.200\appdata\apachephp8\html\plix"

if (Test-Path $networkPlixDir) {
    Write-Host "Publishing Windows installer to network folder $networkPlixDir..."
    Copy-Item $installerSource -Destination "$networkPlixDir\plix_windows.exe" -Force
    if (Test-Path "web_site\index.html") {
        Copy-Item "web_site\*" -Destination "$networkPlixDir" -Recurse -Force
    }

    $manifestPath = "$networkPlixDir\plix.json"
    $releaseNotes = @"
- Collapsed Sidebar: Library rows now show their movie or TV icons when the left navigation is collapsed
- Sidebar Header: The LIBRARIES label and reorder button are hidden while collapsed; a divider separates the library section instead
- TV Remote Navigation: The library reorder button can now be focused and selected with the D-pad on Android TV
- App Version Bump: Updated to v1.2.2 (versionCode 21)
"@

    $manifest = [ordered]@{
        version = $version
        versionCode = $versionCode
        apkUrl = "https://plix.jman100.com/plix_android_tv.apk?v=$version"
        windowsUrl = "https://plix.jman100.com/plix_windows.exe?v=$version"
        releaseNotes = $releaseNotes.Trim()
        releaseDate = (Get-Date -Format "yyyy-MM-dd")
    } | ConvertTo-Json -Depth 4

    Set-Content -Path $manifestPath -Value $manifest -Encoding UTF8
    Write-Host "Published plix_windows.exe and updated plix.json successfully to $networkPlixDir"
} else {
    Write-Warning "Network directory $networkPlixDir not reachable."
}

Write-Host "Windows build and publish completed successfully!"
