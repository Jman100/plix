$version = "1.1.2"
$versionCode = 18
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
- Watchlist from Episode Details: Pressing "Add to Watchlist" on an episode details page now adds the entire show to the Watchlist across both Plex and Jellyfin servers, and correctly reflects the "In Watchlist" state
- Recently Added Shows Tile Text: Show name is prominently displayed on the top line under each tile; the bottom line shows the episode title if a single episode was added, "Season X" if an entire season was added, or remains clean/blank if multiple seasons were added
- HDR Badges on Jellyfin: Restored missing HDR icons and badges on Jellyfin servers for Continue Watching hero preview cards and all episodes under season listings
- App Version Bump: Updated to v1.1.2 (versionCode 18)
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
