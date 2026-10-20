$toolsDir = "C:\Users\joshc\Documents\AISTUFF\tools"
$env:JAVA_HOME = "$toolsDir\jdk17"
$env:ANDROID_HOME = "$toolsDir\android-sdk"
$env:PATH = "$toolsDir\flutter\bin;$toolsDir\flutter\bin\cache\dart-sdk\bin;$toolsDir\git\cmd;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:ANDROID_HOME\cmdline-tools\latest\bin;$env:PATH"

Write-Host "Building Release APK (v1.1.2)..."
& "$toolsDir\flutter\bin\flutter.bat" build apk --release
if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed"
    exit $LASTEXITCODE
}

$apkSource = "build\app\outputs\flutter-apk\app-release.apk"
$networkPlixDir = "\\192.168.0.200\appdata\apachephp8\html\plix"

if (Test-Path $networkPlixDir) {
    Write-Host "Publishing APK to network folder $networkPlixDir..."
    Copy-Item $apkSource -Destination "$networkPlixDir\plix_android_tv.apk" -Force
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
        version = "1.1.2"
        versionCode = 18
        apkUrl = "https://plix.jman100.com/plix_android_tv.apk?v=1.1.2"
        windowsUrl = "https://plix.jman100.com/plix_windows.exe?v=1.1.2"
        releaseNotes = $releaseNotes.Trim()
        releaseDate = (Get-Date -Format "yyyy-MM-dd")
    } | ConvertTo-Json -Depth 4

    Set-Content -Path $manifestPath -Value $manifest -Encoding UTF8
    Write-Host "Published plix.json and plix_android_tv.apk successfully to $networkPlixDir"
    Write-Host "Ready for in-app update testing on Android TV (no automatic sideloading)."
} else {
    Write-Warning "Network directory $networkPlixDir not reachable."
}

Write-Host "Build and publish completed successfully!"
