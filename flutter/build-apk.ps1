# Builds the signed Android app into release/<version>/ at the project root:
#
#     powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1          the APK, for GitHub
#     powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1 -Aab     the bundle, for Google Play
#
# From 1.1.0 the app is Flutter (lib/, android/). The version is pubspec.yaml's.
#
# The APK (uwufix-<version>.apk) is for ARM phones, 32 and 64 bit, in one file, as the app's updater
# fetches the one file. The bundle (uwufix-<version>.aab) is the same app without its updater, as
# Play updates it (android/app/src/play/AndroidManifest.xml, --dart-define=FIXUP_PLAY=true).
#
# Both are made small and obfuscated the way Google Play measures it:
#   - R8 shrinks, optimises and renames the Java and its libraries (android/app/build.gradle,
#     proguard-rules.pro), and drops unused resources;
#   - the Dart code is obfuscated (--obfuscate) with its symbols split off (--split-debug-info),
#     kept beside the app as uwufix-<version>-symbols.zip for reading a crash's stack;
#   - the native libraries' debug symbols are stripped, and the bundle carries them, and R8's
#     mapping, in its metadata for Play's crash reports.
# R8's mapping is kept beside the app too (uwufix-<version>-mapping.txt). Neither goes on the
# GitHub release.
#
# Each build is checked before it's copied out: signed with the app's key (the one
# main-site/.well-known/assetlinks.json names, so phones can update to it and the site's links open
# in it), with no advertising ID, and the bundle with no updater.
#
# Needs Flutter on the PATH (or FLUTTER_ROOT), a JDK 21 or later and the Android SDK. It finds the
# JDK and SDK in JAVA_HOME and ANDROID_HOME if they're set, or else the newest JDK under Program
# Files and the SDK in %LOCALAPPDATA%\Android\Sdk.

param([switch]$Aab)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$fingerprint = 'B0:55:C6:AE:FD:D0:88:01:41:54:8E:94:39:80:D5:90:FC:C1:CF:79:4E:90:0A:9A:0A:49:F1:8E:E9:77:23:24'

if (-not (Test-Path "$here\keystore.properties") -or -not (Test-Path "$here\android.keystore")) {
    throw "android.keystore and keystore.properties are missing from $here. They're not in git: restore them from your backup."
}

# GitHub refuses a file over 100 MB, so any under release/ (an AAB, a mapping, a symbols zip) goes
# in .gitignore, and only on the GitHub release (or Play). Smaller ones stay committed.
function Ignore-Large {
    $limit = 100MB
    $ignore = "$root\.gitignore"
    $lines = @(Get-Content $ignore -ErrorAction SilentlyContinue)
    $marker = "# Over 100 MB, GitHub's limit for a file: only on the GitHub release (flutter/build-apk.ps1 adds them)."
    $added = @()
    Get-ChildItem "$root\release" -Recurse -File | Where-Object { $_.Length -gt $limit } | ForEach-Object {
        $rel = $_.FullName.Substring($root.Length + 1).Replace('\', '/')
        if ($lines -notcontains $rel) { $added += $rel }
    }
    if (-not $added.Count) { return }
    $text = ''
    if ($lines -notcontains $marker) { $text += "`n$marker`n" }
    $text += ($added -join "`n") + "`n"
    [IO.File]::AppendAllText($ignore, $text)
    $added | ForEach-Object { Write-Host "Over 100 MB, so ignored by git: $_" }
}

function Find-Jdk {
    # The JDK's version from its release file, as java -version writes to stderr, which Windows
    # PowerShell takes for an error.
    function Major($dir) {
        $release = "$dir\release"
        if (-not (Test-Path $release)) { return 0 }
        $m = [regex]::Match((Get-Content $release -Raw), 'JAVA_VERSION="(\d+)')
        if ($m.Success) { return [int]$m.Groups[1].Value } else { return 0 }
    }
    if ($env:JAVA_HOME -and (Test-Path "$env:JAVA_HOME\bin\java.exe") -and (Major $env:JAVA_HOME) -ge 21) { return $env:JAVA_HOME }
    $candidates = @('C:\Program Files\Eclipse Adoptium', 'C:\Program Files\Java', 'C:\Program Files\Microsoft') |
        Where-Object { Test-Path $_ } |
        ForEach-Object { Get-ChildItem $_ -Directory -Filter 'jdk*' } |
        Where-Object { (Test-Path "$($_.FullName)\bin\java.exe") -and (Major $_.FullName) -ge 21 } |
        Sort-Object { Major $_.FullName }
    if ($candidates) { return ($candidates | Select-Object -Last 1).FullName }
    throw 'No JDK 21 or later found. Install one (https://adoptium.net) or set JAVA_HOME to it.'
}

$env:JAVA_HOME = Find-Jdk
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
if (-not $env:ANDROID_HOME) {
    if (Test-Path "$env:LOCALAPPDATA\Android\Sdk") { $env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk" }
    else { throw 'No Android SDK found. Set ANDROID_HOME to it.' }
}
$buildTools = Get-ChildItem "$env:ANDROID_HOME\build-tools" -Directory | Sort-Object { [version]$_.Name } | Select-Object -Last 1

$pubspec = Get-Content "$here\pubspec.yaml" -Raw
$version = [regex]::Match($pubspec, '(?m)^version:\s*([0-9.]+)').Groups[1].Value
$flutter = if ($env:FLUTTER_ROOT) { "$env:FLUTTER_ROOT\bin\flutter.bat" } else { 'flutter' }
$out = "$root\release\$version"
$symbols = "$here\build\symbols-$version" + $(if ($Aab) { '-play' } else { '' })
Write-Host "Building uwuFix $version for Android$(if ($Aab) { ' (Google Play bundle)' }) (JDK: $env:JAVA_HOME)..."

if (-not (Test-Path "$here\android\app\google-services.json")) {
    Write-Warning 'google-services.json is missing: this build has no notifications (FIREBASE-SETUP.md).'
}

function Read-Zip($file) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($file)
    try {
        return @($zip.Entries | ForEach-Object { $_.FullName })
    } finally {
        $zip.Dispose()
    }
}

function Zip-Symbols($dest) {
    if (-not (Get-ChildItem $symbols -File -ErrorAction SilentlyContinue)) {
        throw "Flutter left no Dart symbols in $symbols. Run 'flutter clean' in flutter\ and build again."
    }
    if (Test-Path $dest) { Remove-Item $dest -Force }
    Compress-Archive -Path "$symbols\*" -DestinationPath $dest
}

New-Item -ItemType Directory -Force $out | Out-Null
# The symbols folder is kept between builds: when nothing's changed, Flutter doesn't compile the
# Dart again, or write its symbols again, and the ones there still match.

Push-Location $here
try {
    & $flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
    $common = @('--release', '--target-platform', 'android-arm,android-arm64', '--obfuscate', "--split-debug-info=$symbols")
    if ($Aab) {
        # Never an old one: with nothing changed, Gradle wouldn't write it again.
        $bundle = "$here\build\app\outputs\bundle\release\app-release.aab"
        Remove-Item $bundle -Force -ErrorAction SilentlyContinue
        & $flutter build appbundle @common --dart-define=FIXUP_PLAY=true --android-project-arg=fixupPlay=true
        $failed = $LASTEXITCODE -ne 0
    } else {
        & $flutter build apk @common
        if ($LASTEXITCODE -ne 0) { throw 'flutter build apk failed. Its messages are above.' }
    }
} finally {
    Pop-Location
}

if ($Aab) {
    # Flutter's last step looks for debug symbols with apkanalyzer, from the SDK's cmdline-tools, and
    # says it failed if that isn't installed. So a failure counts only if no bundle was made, or if
    # the same look, below, finds them missing.
    if (-not (Test-Path $bundle)) {
        if ($failed) { throw 'flutter build appbundle failed. Its messages are above.' }
        throw 'Gradle made no bundle.'
    }
    $ErrorActionPreference = 'Continue'
    $certs = & "$env:JAVA_HOME\bin\keytool.exe" -printcert -jarfile $bundle 2>&1 | Out-String
    $ErrorActionPreference = 'Stop'
    if ($certs -notmatch "SHA256:\s*$fingerprint") { throw "The bundle isn't signed with the app's key: is keystore.properties right?" }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($bundle)
    try {
        $reader = New-Object IO.StreamReader($zip.GetEntry('base/manifest/AndroidManifest.xml').Open(), [Text.Encoding]::GetEncoding(28591))
        $manifest = $reader.ReadToEnd()
        $reader.Dispose()
        $entries = @($zip.Entries | ForEach-Object { $_.FullName })
    } finally {
        $zip.Dispose()
    }
    if ($manifest -match 'REQUEST_INSTALL_PACKAGES|UpdateActivity') { throw 'The bundle still has the updater in its manifest.' }
    if ($manifest -match 'permission.AD_ID') { throw 'The bundle asks for the advertising ID.' }
    foreach ($lib in 'libflutter', 'libapp') {
        if (-not ($entries -match "^BUNDLE-METADATA/com\.android\.tools\.build\.debugsymbols/.*/$lib\.so\.(sym|dbg)$")) {
            throw "The bundle's $lib.so hasn't had its debug symbols stripped."
        }
    }
    # R8 ran, and Play gets its mapping, to read crashes and measure the code's optimisation.
    if (-not ($entries -contains 'BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map')) {
        throw 'The bundle has no R8 mapping: is minifyEnabled still on in android/app/build.gradle?'
    }
    $dest = "$out\uwufix-$version.aab"
    Copy-Item $bundle $dest -Force
    Zip-Symbols "$out\uwufix-$version-play-symbols.zip"
    Ignore-Large
    Write-Host "Done: $dest ($([math]::Round((Get-Item $dest).Length / 1MB, 1)) MB)"
    return
}

$signed = "$here\build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $signed)) { throw 'Gradle made no APK.' }
# Its warnings (META-INF/*.version "not protected by signature") come with every Android build and
# mean nothing here; only a failure matters. Windows PowerShell turns anything a program writes to
# stderr into an error, so only its exit code is looked at.
$ErrorActionPreference = 'Continue'
$check = & "$($buildTools.FullName)\apksigner.bat" verify --print-certs $signed 2>&1
$verified = $LASTEXITCODE -eq 0
$badging = & "$($buildTools.FullName)\aapt2.exe" dump permissions $signed 2>&1 | Out-String
$ErrorActionPreference = 'Stop'
if (-not $verified) { $check | Write-Host; throw 'The signed app failed its signature check.' }
# The same key as every version before, or phones can't update to it.
$sha = ($fingerprint -replace ':', '').ToLower()
if (($check | Out-String) -notmatch "SHA-256 digest: $sha") {
    throw "The APK is signed with a different key, so it can't update the app already installed."
}
if ($badging -match 'permission.AD_ID') { throw 'The APK asks for the advertising ID.' }
if ((Read-Zip $signed) -match '^lib/x86') { throw 'The APK carries x86 libraries, which no phone uses.' }

$dest = "$out\uwufix-$version.apk"
Copy-Item $signed $dest -Force
# What puts the names back in a crash: R8's for the Java, and the Dart symbols.
Copy-Item "$here\build\app\outputs\mapping\release\mapping.txt" "$out\uwufix-$version-mapping.txt" -Force
Zip-Symbols "$out\uwufix-$version-symbols.zip"
Ignore-Large
Write-Host "Done: $dest ($([math]::Round((Get-Item $dest).Length / 1MB, 1)) MB)"
