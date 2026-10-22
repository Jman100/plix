$version = "1.2.3"
$versionCode = 22
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
    [System.IO.File]::WriteAllText($manifestPath, $manifest, $utf8NoBom)
    Write-Host "Published plix_windows.exe and updated plix.json successfully to $networkPlixDir"
} else {
    Write-Warning "Network directory $networkPlixDir not reachable."
}

Write-Host "Windows build and publish completed successfully!"
