param(
    [string]$InstallDir = $(if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }),
    [switch]$CheckOnly,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# For Windows PowerShell 5.1
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {}

function Normalize-DirPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $trimChars = [char[]]@([char]92, [char]47)

    try {
        $expanded = [Environment]::ExpandEnvironmentVariables($Path)
        return [System.IO.Path]::GetFullPath($expanded).TrimEnd($trimChars)
    } catch {
        return $Path.TrimEnd($trimChars)
    }
}

function Add-ToUserPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathToAdd
    )

    $normalizedPathToAdd = Normalize-DirPath -Path $PathToAdd
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")

    $alreadyInPath = $false

    if (-not [string]::IsNullOrWhiteSpace($userPath)) {
        $pathItems = $userPath -split ";"

        foreach ($item in $pathItems) {
            if ([string]::IsNullOrWhiteSpace($item)) {
                continue
            }

            $normalizedItem = Normalize-DirPath -Path $item

            if ($normalizedItem -ieq $normalizedPathToAdd) {
                $alreadyInPath = $true
                break
            }
        }
    }

    if (-not $alreadyInPath) {
        if ([string]::IsNullOrWhiteSpace($userPath)) {
            $newUserPath = $PathToAdd
        } else {
            $newUserPath = $userPath + ";" + $PathToAdd
        }

        [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
        Write-Host "Added to user PATH: $PathToAdd"
    } else {
        Write-Host "User PATH already contains install directory."
    }

    # Also update PATH for current PowerShell session
    $currentAlreadyHas = $false

    if (-not [string]::IsNullOrWhiteSpace($env:Path)) {
        $currentItems = $env:Path -split ";"

        foreach ($item in $currentItems) {
            if ([string]::IsNullOrWhiteSpace($item)) {
                continue
            }

            $normalizedItem = Normalize-DirPath -Path $item

            if ($normalizedItem -ieq $normalizedPathToAdd) {
                $currentAlreadyHas = $true
                break
            }
        }
    }

    if (-not $currentAlreadyHas) {
        $env:Path = $env:Path + ";" + $PathToAdd
    }
}

function Get-WindowsRuntimeId {
    $arch = $env:PROCESSOR_ARCHITECTURE

    if ($env:PROCESSOR_ARCHITEW6432) {
        $arch = $env:PROCESSOR_ARCHITEW6432
    }

    switch ($arch.ToUpperInvariant()) {
        "AMD64" { return "win-x64" }
        "ARM64" { return "win-arm64" }
        "X86" { return "win-NT6.0-x86" }
        default {
            throw "Unsupported architecture: $arch"
        }
    }
}

$Repo = "nilaoda/N_m3u8DL-RE"
$ApiUrl = "https://api.github.com/repos/$Repo/releases/latest"
$ExeName = "N_m3u8DL-RE.exe"
$StateFileName = ".install-state.json"

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
$InstallDir = (Resolve-Path $InstallDir).Path

$InstalledExe = Join-Path $InstallDir $ExeName
$StateFile = Join-Path $InstallDir $StateFileName

Write-Host "Install directory: $InstallDir"

$RuntimeId = Get-WindowsRuntimeId
Write-Host "Runtime ID: $RuntimeId"

$Headers = @{
    "User-Agent" = "PowerShell-N_m3u8DL-RE-Installer"
}

Write-Host "Checking latest release..."

$Release = Invoke-RestMethod -Uri $ApiUrl -Headers $Headers

if (-not $Release.tag_name) {
    throw "Failed to get latest release tag."
}

$LatestTag = $Release.tag_name

$escapedRuntimeId = [regex]::Escape($RuntimeId)
$assetPattern = "_" + $escapedRuntimeId + "(_\d+)?\.zip$"

$Asset = $Release.assets |
    Where-Object {
        $_.name -match $assetPattern
    } |
    Sort-Object created_at -Descending |
    Select-Object -First 1

if (-not $Asset) {
    $availableAssets = ($Release.assets | ForEach-Object { $_.name }) -join "`n - "
    throw "No matching asset found for runtime ID: $RuntimeId`nAvailable assets:`n - $availableAssets"
}

$AssetName = $Asset.name
$AssetUrl = $Asset.browser_download_url

Write-Host "Latest tag: $LatestTag"
Write-Host "Matched asset: $AssetName"

$CurrentTag = $null
$CurrentAsset = $null

if (Test-Path $StateFile) {
    try {
        $state = Get-Content $StateFile -Raw | ConvertFrom-Json
        $CurrentTag = $state.tag
        $CurrentAsset = $state.asset
    } catch {
        $CurrentTag = $null
        $CurrentAsset = $null
    }
}

if (-not $CurrentTag -and (Test-Path $InstalledExe)) {
    $CurrentTag = "unknown"
}

Write-Host "Current tag: $(if ($CurrentTag) { $CurrentTag } else { 'not installed' })"
Write-Host "Current asset: $(if ($CurrentAsset) { $CurrentAsset } else { 'not installed' })"

$isLatest = $false

if (($CurrentTag -eq $LatestTag) -and ($CurrentAsset -eq $AssetName)) {
    $isLatest = $true
}

if ($CheckOnly) {
    if ($isLatest) {
        Write-Host "Already up to date."
    } else {
        Write-Host "Update available."
    }

    exit 0
}

if ($isLatest -and (-not $Force)) {
    Write-Host "Already up to date. No update needed."
    Write-Host "Use -Force to reinstall latest version."

    Add-ToUserPath -PathToAdd $InstallDir

    exit 0
}

$TempRoot = Join-Path $env:TEMP "N_m3u8DL-RE-Install"
$ExtractDir = Join-Path $TempRoot "extract"
$ZipPath = Join-Path $TempRoot $AssetName

Remove-Item $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $ExtractDir -Force | Out-Null

try {
    Write-Host "Downloading..."
    Write-Host $AssetUrl

    Invoke-WebRequest -Uri $AssetUrl -OutFile $ZipPath -Headers $Headers

    try {
        Unblock-File -Path $ZipPath -ErrorAction SilentlyContinue
    } catch {}

    Write-Host "Extracting..."
    Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force

    $ExeFile = Get-ChildItem -Path $ExtractDir -Filter $ExeName -Recurse -File | Select-Object -First 1

    if (-not $ExeFile) {
        throw "Executable not found after extraction: $ExeName"
    }

    $SourceDir = $ExeFile.Directory.FullName

    Write-Host "Source directory: $SourceDir"

    if (Test-Path $InstalledExe) {
        $BackupDir = Join-Path $InstallDir "_backup_previous"

        Remove-Item $BackupDir -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

        Write-Host "Backing up previous version to: $BackupDir"

        $scriptName = $null
        if ($PSCommandPath) {
            $scriptName = Split-Path $PSCommandPath -Leaf
        }

        Get-ChildItem -Path $InstallDir -Force | Where-Object {
            $_.Name -ne "_backup_previous" -and
            $_.Name -ne $scriptName
        } | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $BackupDir -Recurse -Force
        }
    }

    Write-Host "Copying files..."

    Copy-Item -Path (Join-Path $SourceDir "*") -Destination $InstallDir -Recurse -Force

    if (-not (Test-Path $InstalledExe)) {
        throw "Install or update failed. Executable not found: $InstalledExe"
    }

    try {
        Unblock-File -Path (Join-Path $InstallDir "*") -ErrorAction SilentlyContinue
    } catch {}

    $newState = [PSCustomObject]@{
        tag = $LatestTag
        asset = $AssetName
        installed_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }

    $newState | ConvertTo-Json | Set-Content -Path $StateFile -Encoding ASCII

    Add-ToUserPath -PathToAdd $InstallDir

    Write-Host ""
    Write-Host "Done."
    Write-Host "Installed tag: $LatestTag"
    Write-Host "Installed asset: $AssetName"
    Write-Host "Executable: $InstalledExe"
    Write-Host ""
    Write-Host "Test command:"
    Write-Host "N_m3u8DL-RE"
    Write-Host ""
    Write-Host "If command is not recognized in a new terminal, restart PowerShell or Windows Terminal."
}
finally {
    Remove-Item $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}