param(
    [string]$InstallDir = $(if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }),
    [switch]$CheckOnly,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Add-ToUserPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathToAdd
    )

    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")

    $PathItems = @()
    if ($UserPath) {
        $PathItems = $UserPath -split ";" | Where-Object { $_ -and $_.Trim() }
    }

    $NormalizedPathToAdd = ([System.IO.DirectoryInfo]$PathToAdd).FullName.TrimEnd("\")

    $AlreadyInPath = $false

    foreach ($Item in $PathItems) {
        try {
            $ExpandedItem = [Environment]::ExpandEnvironmentVariables($Item)
            $NormalizedItem = ([System.IO.DirectoryInfo]$ExpandedItem).FullName.TrimEnd("\")

            if ($NormalizedItem -ieq $NormalizedPathToAdd) {
                $AlreadyInPath = $true
                break
            }
        } catch {
            if ($Item.TrimEnd("\") -ieq $PathToAdd.TrimEnd("\")) {
                $AlreadyInPath = $true
                break
            }
        }
    }

    if (-not $AlreadyInPath) {
        if ([string]::IsNullOrWhiteSpace($UserPath)) {
            $NewUserPath = $PathToAdd
        } else {
            $NewUserPath = "$UserPath;$PathToAdd"
        }

        [Environment]::SetEnvironmentVariable("Path", $NewUserPath, "User")
        Write-Host "已添加到用户 Path: $PathToAdd"
    } else {
        Write-Host "用户 Path 中已存在该目录，无需重复添加。"
    }

    $CurrentPathItems = $env:Path -split ";" | Where-Object { $_ -and $_.Trim() }
    $CurrentAlreadyHas = $false

    foreach ($Item in $CurrentPathItems) {
        try {
            $ExpandedItem = [Environment]::ExpandEnvironmentVariables($Item)
            $NormalizedItem = ([System.IO.DirectoryInfo]$ExpandedItem).FullName.TrimEnd("\")

            if ($NormalizedItem -ieq $NormalizedPathToAdd) {
                $CurrentAlreadyHas = $true
                break
            }
        } catch {
            if ($Item.TrimEnd("\") -ieq $PathToAdd.TrimEnd("\")) {
                $CurrentAlreadyHas = $true
                break
            }
        }
    }

    if (-not $CurrentAlreadyHas) {
        $env:Path += ";$PathToAdd"
    }
}

$Repo = "nilaoda/N_m3u8DL-RE"
$ApiUrl = "https://api.github.com/repos/$Repo/releases/latest"
$ExeName = "N_m3u8DL-RE.exe"
$VersionFileName = ".installed_version"

Write-Host "安装目录: $InstallDir"

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
$InstallDir = (Resolve-Path $InstallDir).Path

$VersionFile = Join-Path $InstallDir $VersionFileName
$InstalledExe = Join-Path $InstallDir $ExeName

$Arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()

switch ($Arch) {
    "X64"   { $AssetName = "win-x64.zip" }
    "Arm64" { $AssetName = "win-arm64.zip" }
    "X86"   { $AssetName = "win-NT6.0-x86.zip" }
    default {
        throw "不支持的系统架构: $Arch"
    }
}

Write-Host "检测到架构: $Arch"
Write-Host "匹配资产: $AssetName"

$Headers = @{
    "User-Agent" = "PowerShell-N_m3u8DL-RE-Installer"
}

Write-Host "正在检查 GitHub 最新版本..."

$Release = Invoke-RestMethod -Uri $ApiUrl -Headers $Headers
$LatestVersion = $Release.tag_name

if (-not $LatestVersion) {
    throw "无法从 GitHub release 获取最新版本号。"
}

$EscapedRid = [regex]::Escape($AssetRid)

$Asset = $Release.assets | Where-Object {
    $_.name -match "_$EscapedRid" -and
    $_.name -match "\.zip$"
} | Sort-Object created_at -Descending | Select-Object -First 1

if (-not $Asset) {
    $AvailableAssets = ($Release.assets | ForEach-Object { $_.name }) -join "`n - "
    throw "没有找到匹配平台的资产: $AssetRid`n当前 release 可用资产:`n - $AvailableAssets"
}

$AssetName = $Asset.name
Write-Host "匹配到资产: $AssetName"

$CurrentVersion = $null

if (Test-Path $VersionFile) {
    $CurrentVersion = (Get-Content $VersionFile -Raw).Trim()
}

if (-not $CurrentVersion -and (Test-Path $InstalledExe)) {
    $CurrentVersion = "未知版本"
}

Write-Host "本地版本: $(if ($CurrentVersion) { $CurrentVersion } else { '未安装' })"
Write-Host "最新版本: $LatestVersion"

if ($CheckOnly) {
    if ($CurrentVersion -eq $LatestVersion) {
        Write-Host "当前已经是最新版本。"
    } else {
        Write-Host "发现新版本，可以运行本脚本进行更新。"
    }

    exit 0
}

if (($CurrentVersion -eq $LatestVersion) -and (-not $Force)) {
    Write-Host "当前已经是最新版本，无需更新。"
    Write-Host "如果想强制重装，请加参数: -Force"

    Add-ToUserPath -PathToAdd $InstallDir

    exit 0
}

$TempRoot = Join-Path $env:TEMP "N_m3u8DL-RE-Install"
$ExtractDir = Join-Path $TempRoot "extract"
$ZipPath = Join-Path $TempRoot $AssetName

Remove-Item $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $ExtractDir -Force | Out-Null

try {
    Write-Host "正在下载: $($Asset.browser_download_url)"
    Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $ZipPath -Headers $Headers

    Write-Host "正在解压..."
    Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force

    $ExeFile = Get-ChildItem -Path $ExtractDir -Filter $ExeName -Recurse -File | Select-Object -First 1

    if (-not $ExeFile) {
        throw "解压后没有找到 $ExeName"
    }

    $SourceDir = $ExeFile.Directory.FullName

    Write-Host "程序文件目录: $SourceDir"

    if (Test-Path $InstalledExe) {
        $BackupDir = Join-Path $InstallDir "_backup_previous"

        Remove-Item $BackupDir -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

        Write-Host "正在备份当前版本到: $BackupDir"

        Get-ChildItem -Path $InstallDir -Force | Where-Object {
            $_.Name -ne "_backup_previous" -and
            $_.Name -ne (Split-Path $PSCommandPath -Leaf)
        } | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $BackupDir -Recurse -Force
        }
    }

    Write-Host "正在复制新版本文件..."

    Copy-Item -Path (Join-Path $SourceDir "*") -Destination $InstallDir -Recurse -Force

    if (-not (Test-Path $InstalledExe)) {
        throw "安装/更新失败，目标目录中没有找到 $ExeName"
    }

    $LatestVersion | Set-Content -Path $VersionFile -Encoding UTF8

    Add-ToUserPath -PathToAdd $InstallDir

    Write-Host ""
    Write-Host "完成。"
    Write-Host "当前版本: $LatestVersion"
    Write-Host "可执行文件: $InstalledExe"
    Write-Host ""
    Write-Host "你可以运行下面命令测试:"
    Write-Host "N_m3u8DL-RE"
    Write-Host ""
    Write-Host "如果新开的终端中仍无法识别，请重新打开 PowerShell / Windows Terminal。"
}
finally {
    Remove-Item $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}