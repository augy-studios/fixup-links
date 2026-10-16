# Builds the signed Android app into release/<version>/ at the project root:
#
#     powershell -ExecutionPolicy Bypass -File android\build-apk.ps1
#
# Installs the Capacitor packages if they're missing, syncs them into the Android project
# (native/), then Gradle builds the release APK, signed with android.keystore using the
# passwords in keystore.properties (native/app/build.gradle), and the signature is checked
# against main-site/.well-known/assetlinks.json before it's copied out as
# release/<versionName>/uwufix-<versionName>.apk.
#
# The first time, with no signing key yet, it makes one (android.keystore, keystore.properties)
# and writes its fingerprint into assetlinks.json. Both files are kept out of git: back them up.
# Once assetlinks.json names a key, a missing keystore is an error, never a new key, as a
# different key can't update the app already on phones.
#
# Needs a JDK 21 or later and the Android SDK. It finds them in JAVA_HOME and ANDROID_HOME if
# they're set, or else the newest JDK under Program Files and the SDK in ~/.bubblewrap or
# %LOCALAPPDATA%\Android\Sdk. Gradle fetches any SDK platform it's missing on the first build.

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$package = 'org.uwuapps.fixup'
$assetLinks = "$root\main-site\.well-known\assetlinks.json"

function Find-Jdk {
    if ($env:JAVA_HOME -and (Test-Path "$env:JAVA_HOME\bin\java.exe")) {
        $v = & "$env:JAVA_HOME\bin\java.exe" -version 2>&1 | Out-String
        if ($v -match 'version "(\d+)' -and [int]$Matches[1] -ge 21) { return $env:JAVA_HOME }
    }
    $candidates = @('C:\Program Files\Eclipse Adoptium', 'C:\Program Files\Java', 'C:\Program Files\Microsoft') |
        Where-Object { Test-Path $_ } |
        ForEach-Object { Get-ChildItem $_ -Directory -Filter 'jdk*' } |
        Where-Object { $_.Name -match 'jdk-?(\d+)' -and [int]$Matches[1] -ge 21 -and (Test-Path "$($_.FullName)\bin\java.exe") } |
        Sort-Object { [int]([regex]::Match($_.Name, 'jdk-?(\d+)').Groups[1].Value) }
    if ($candidates) { return ($candidates | Select-Object -Last 1).FullName }
    throw 'No JDK 21 or later found. Install one (https://adoptium.net) or set JAVA_HOME to it.'
}

# A native tool's output, stderr and all, with only its exit code deciding success: Windows
# PowerShell turns anything a program writes to stderr into an error otherwise.
function Invoke-Tool([string]$exe, [string[]]$arguments) {
    $ErrorActionPreference = 'Continue'
    $out = & $exe @arguments 2>&1 | Out-String
    return @{ Ok = ($LASTEXITCODE -eq 0); Output = $out }
}

# The SHA-256 fingerprint assetlinks.json lists for this app, as 64 lowercase hex digits, or $null.
function Get-LinkedFingerprint {
    if (-not (Test-Path $assetLinks)) { return $null }
    $text = Get-Content $assetLinks -Raw
    if ($text -notmatch [regex]::Escape($package)) { return $null }
    $m = [regex]::Match($text, '([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){31})')
    if (-not $m.Success) { return $null }
    return $m.Groups[1].Value.Replace(':', '').ToLowerInvariant()
}

$env:JAVA_HOME = Find-Jdk
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
$keytool = "$env:JAVA_HOME\bin\keytool.exe"

# ---------- the signing key ----------

if (-not (Test-Path "$here\keystore.properties") -or -not (Test-Path "$here\android.keystore")) {
    if (Get-LinkedFingerprint) {
        throw "android.keystore and keystore.properties are missing from $here, and assetlinks.json already names this app's key. They're not in git: restore them from your backup. A new key couldn't update the app already installed on phones."
    }
    if ((Test-Path "$here\keystore.properties") -or (Test-Path "$here\android.keystore")) {
        throw "Only one of android.keystore and keystore.properties is in $here. Restore the other from your backup, or delete both to make a new key."
    }

    Write-Host 'No signing key yet: making one (android.keystore, keystore.properties)...'
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $password = ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '')
    $made = Invoke-Tool $keytool @('-genkeypair', '-keystore', "$here\android.keystore", '-storetype', 'PKCS12',
        '-alias', 'uwufix', '-keyalg', 'RSA', '-keysize', '4096', '-validity', '36500',
        '-storepass', $password, '-keypass', $password, '-dname', 'CN=uwuFix, O=UwU Apps')
    if (-not $made.Ok) { Write-Host $made.Output; throw 'keytool could not make the signing key.' }
    Set-Content -Path "$here\keystore.properties" -Encoding ASCII -Value @(
        '# The signing key''s passwords (android/README.md). Never in git: back this up with android.keystore.',
        'storeFile=android.keystore',
        "storePassword=$password",
        'keyAlias=uwufix',
        "keyPassword=$password"
    )

    $listed = Invoke-Tool $keytool @('-list', '-v', '-keystore', "$here\android.keystore", '-alias', 'uwufix', '-storepass', $password)
    $fp = [regex]::Match($listed.Output, 'SHA256:\s*([0-9A-F:]{95})').Groups[1].Value
    if (-not $fp) { Write-Host $listed.Output; throw 'Could not read the new key''s SHA-256 fingerprint.' }
    # Written whole: this app is the only one the site links to.
    Set-Content -Path $assetLinks -Encoding ASCII -Value @(
        '[{',
        '    "relation": ["delegate_permission/common.handle_all_urls"],',
        '    "target": {',
        '        "namespace": "android_app",',
        "        `"package_name`": `"$package`",",
        "        `"sha256_cert_fingerprints`": [`"$fp`"]",
        '    }',
        '}]'
    )
    Write-Host ''
    Write-Host 'Made a new signing key. Before anything else:' -ForegroundColor Yellow
    Write-Host "  1. Back up android\android.keystore and android\keystore.properties somewhere safe." -ForegroundColor Yellow
    Write-Host '     Lose them and no phone can ever update this app again.' -ForegroundColor Yellow
    Write-Host "  2. Commit and deploy main-site\.well-known\assetlinks.json (fingerprint $fp)," -ForegroundColor Yellow
    Write-Host '     so the site''s links open in the app.' -ForegroundColor Yellow
    Write-Host ''
}

$expected = Get-LinkedFingerprint
if (-not $expected) { throw "assetlinks.json doesn't list $package's key. Restore it from git." }

# ---------- the Android SDK ----------

if (-not $env:ANDROID_HOME) {
    $bw = "$env:USERPROFILE\.bubblewrap\config.json"
    if (Test-Path $bw) { $env:ANDROID_HOME = (Get-Content $bw -Raw | ConvertFrom-Json).androidSdkPath }
    elseif (Test-Path "$env:LOCALAPPDATA\Android\Sdk") { $env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk" }
    else { throw 'No Android SDK found. Install Android Studio, or set ANDROID_HOME to an SDK.' }
}
$buildTools = Get-ChildItem "$env:ANDROID_HOME\build-tools" -Directory | Sort-Object { [version]$_.Name } | Select-Object -Last 1
if (-not $buildTools) { throw "No build-tools in $env:ANDROID_HOME. Install them with Android Studio's SDK Manager." }

$gradleFile = Get-Content "$here\native\app\build.gradle" -Raw
$version = [regex]::Match($gradleFile, 'versionName "([^"]+)"').Groups[1].Value
$versionCode = [regex]::Match($gradleFile, 'versionCode (\d+)').Groups[1].Value
Write-Host "Building uwuFix $version (versionCode $versionCode) for Android (JDK: $env:JAVA_HOME)..."
if (Test-Path "$here\native\app\google-services.json") {
    Write-Host 'Firebase: google-services.json found, notifications included.'
} else {
    Write-Host 'Firebase: no google-services.json, so this build has no notifications (android\FIREBASE-SETUP.md).' -ForegroundColor Yellow
}

$dest = "$root\release\$version\uwufix-$version.apk"
if (Test-Path $dest) {
    Write-Host "release\$version already has an APK, which this replaces. For a new version, raise versionName and versionCode in android\native\app\build.gradle first, or phones won't take it as an update." -ForegroundColor Yellow
}

# ---------- build ----------

Push-Location $here
try {
    if (-not (Test-Path "$here\node_modules\@capacitor\android")) {
        & npm ci
        if ($LASTEXITCODE -ne 0) { throw 'npm ci failed.' }
    }
    & npx cap sync android
    if ($LASTEXITCODE -ne 0) { throw 'cap sync failed.' }
} finally {
    Pop-Location
}

$gradle = Start-Process -FilePath "$here\native\gradlew.bat" -ArgumentList 'assembleRelease', '--no-daemon', '-q' `
    -WorkingDirectory "$here\native" -NoNewWindow -Wait -PassThru
if ($gradle.ExitCode -ne 0) { throw "Gradle failed (exit $($gradle.ExitCode)). Its messages are above." }

$signed = "$here\native\app\build\outputs\apk\release\app-release.apk"
if (-not (Test-Path $signed)) { throw "Gradle made no signed APK: is keystore.properties's storeFile right?" }

# Its warnings (META-INF/*.version "not protected by signature") come with every Android build
# and mean nothing here; only a failure matters.
$check = Invoke-Tool "$($buildTools.FullName)\apksigner.bat" @('verify', '--print-certs', $signed)
if (-not $check.Ok) { Write-Host $check.Output; throw 'The signed app failed its signature check.' }
# The key assetlinks.json names, which is the key every version before was signed with, or
# phones can't update to it and the site's links won't open in it.
$sha = [regex]::Match($check.Output, 'SHA-256 digest: ([0-9a-f]{64})').Groups[1].Value
if ($sha -ne $expected) {
    throw "The APK is signed with a different key ($sha) from the one assetlinks.json names ($expected), so it can't update the app already installed."
}

# Each version in a folder of its own.
New-Item -ItemType Directory -Force "$root\release\$version" | Out-Null
Copy-Item $signed $dest -Force
Write-Host "Done: $dest" -ForegroundColor Green
