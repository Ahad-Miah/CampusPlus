param(
    [string]$Device = "emulator-5554",
    [string]$CloudinaryCloudName = "be4i3h7e",
    [string]$CloudinaryUploadPreset = "campusplus_preset"
)

if ([string]::IsNullOrWhiteSpace($CloudinaryCloudName) -or
    [string]::IsNullOrWhiteSpace($CloudinaryUploadPreset)) {
    throw "Pass both -CloudinaryCloudName and -CloudinaryUploadPreset."
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$asciiRoot = Join-Path $env:TEMP 'campus_plus_android_build'

if ($root -match '[^\u0000-\u007F]') {
    Write-Host "Detected a non-ASCII project path. Copying the app to $asciiRoot to avoid Java/Gradle path issues."
    New-Item -ItemType Directory -Force -Path $asciiRoot | Out-Null
    Get-ChildItem -LiteralPath $root -Force |
        Copy-Item -Destination $asciiRoot -Recurse -Force
    $root = $asciiRoot
}

Set-Location $root

$javaHome = $env:JAVA_HOME
if (-not $javaHome -or -not (Test-Path $javaHome)) {
    $candidate = 'C:\Program Files\Android\Android Studio\jbr'
    if (Test-Path $candidate) {
        $javaHome = $candidate
    }
}

if (-not $javaHome -or -not (Test-Path $javaHome)) {
    throw "JAVA_HOME is not configured. Install Android Studio with the bundled JDK or set JAVA_HOME to a valid JDK path."
}

$env:JAVA_HOME = $javaHome
$env:PATH = "$javaHome\bin;$env:PATH"

Write-Host "Using JAVA_HOME=$env:JAVA_HOME"
Write-Host "Launching the app on $Device..."
flutter pub get
if ($LASTEXITCODE -ne 0) {
    throw "flutter pub get failed with exit code $LASTEXITCODE."
}

$runArguments = @(
    "run",
    "-d",
    $Device,
    "--dart-define=CLOUDINARY_CLOUD_NAME=$CloudinaryCloudName",
    "--dart-define=CLOUDINARY_UPLOAD_PRESET=$CloudinaryUploadPreset"
)
flutter @runArguments
