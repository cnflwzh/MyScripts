<#
.SYNOPSIS
Read/edit Monster Hunter Rise HR, MR and AR without CE (version 2.1).
.DESCRIPTION
Windows x64 / Windows PowerShell 5.1 or PowerShell 7. Supports only the verified
Steam 16.0.2.0 executable hash. No injection, driver, persistent patch or save
decryption. Writes only the selected rank and its cumulative experience in memory.
The player must save normally in-game and reload to persist and verify it.
.PARAMETER Action
Inspect reads ranks; SetAR300, SetHR and SetMR back up saves and edit one rank pair.
.PARAMETER TargetRank
Target HR (9-999) or MR (7-999). Omit or use 0 for an interactive prompt.
SetAR300 accepts only 0 or 300. Story and urgent quest flags are not modified.
.PARAMETER SaveDirectory
Optional full path to Steam userdata\<account>\1446780. If omitted, discover it.
.PARAMETER BackupDirectory
Backup root. Defaults to the backups folder beside this script.
.EXAMPLE
.\MHRise-AR300.ps1
.EXAMPLE
.\MHRise-AR300.ps1 -Action SetAR300
.NOTES
Pointer layout: Marcus101RR, Cheat Table Monster Hunter Rise 1.5.1 (Nexus mod 21).
This package contains independently written PowerShell code, not that table.
#>
[CmdletBinding()]
param(
    [ValidateSet('Inspect', 'SetAR300', 'SetHR', 'SetMR')][string]$Action = 'Inspect',
    [ValidateRange(0,999)][int]$TargetRank = 0,
    [string]$SaveDirectory,
    [string]$BackupDirectory
)

$ErrorActionPreference = 'Stop'
# Resolve paths in the script body, not while binding parameter defaults.
# Script-block/selection execution may not supply PSScriptRoot at all.
if ([string]::IsNullOrWhiteSpace($BackupDirectory)) {
    $scriptDirectory = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scriptDirectory) -and $PSCommandPath) {
        $scriptDirectory = Split-Path -Parent $PSCommandPath
    }
    if ([string]::IsNullOrWhiteSpace($scriptDirectory) -and $MyInvocation.MyCommand.Path) {
        $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    if ([string]::IsNullOrWhiteSpace($scriptDirectory)) {
        $location = Get-Location
        if ($location.Provider.Name -ne 'FileSystem') {
            throw '无法确定脚本目录，请通过 Start.cmd 启动，或用 -BackupDirectory 指定备份目录。'
        }
        $scriptDirectory = $location.Path
        Write-Warning '当前运行方式未提供脚本路径，备份将放在当前工作目录的 backups 文件夹。建议通过 Start.cmd 启动。'
    }
    $BackupDirectory = Join-Path -Path $scriptDirectory -ChildPath 'backups'
}
$supportedHash = '29FA23A9CE24613A9B05CE84F7EBFA3262AAF5053B377B43FD8DFC09071AA7FC'
$handle = [IntPtr]::Zero

# Access is limited to this game process; no debug privilege or code injection.
if (-not ('MHRiseAR300.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace MHRiseAR300 {
 public static class Native {
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool ReadProcessMemory(IntPtr h, IntPtr address, byte[] data, UIntPtr size, out UIntPtr count);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool WriteProcessMemory(IntPtr h, IntPtr address, byte[] data, UIntPtr size, out UIntPtr count);
  [DllImport("kernel32.dll")]
  public static extern bool CloseHandle(IntPtr h);
 }
}
'@
}

# Read exact byte counts; an invalid pointer fails before it can be used.
function Read-GameBytes([long]$Address, [int]$Length) {
    if ($Address -lt 65536) { throw '无效游戏指针。请载入角色，或检查游戏版本。' }
    $data = New-Object byte[] $Length
    $count = [UIntPtr]::Zero
    $ok = [MHRiseAR300.Native]::ReadProcessMemory($handle, [IntPtr]$Address, $data, [UIntPtr][uint64]$Length, [ref]$count)
    if (-not $ok -or $count.ToUInt64() -ne $Length) { throw ('无法读取游戏数据：0x{0:X}。尚未执行新的写入。' -f $Address) }
    return ,$data
}

# Writes only the caller-provided bytes and reports partial/failed writes.
function Write-GameBytes([long]$Address, [byte[]]$Data) {
    $count = [UIntPtr]::Zero
    $ok = [MHRiseAR300.Native]::WriteProcessMemory($handle, [IntPtr]$Address, $Data, [UIntPtr][uint64]$Data.Length, [ref]$count)
    if (-not $ok -or $count.ToUInt64() -ne $Data.Length) { throw '写入失败或只写入了部分字节。' }
}

# CE pointer lists are read from the outside in: [[module+RVA]+0x68]+field.
function Get-RankSnapshot([long]$ModuleBase) {
    $manager = [BitConverter]::ToInt64((Read-GameBytes ($ModuleBase + 0xF6FA348) 8), 0)
    $rank = [BitConverter]::ToInt64((Read-GameBytes ($manager + 0x68) 8), 0)
    $data = Read-GameBytes ($rank + 0x18) 24
    return [pscustomobject]@{
        Address = $rank
        HR = [BitConverter]::ToInt32($data, 0)
        HRExperience = [BitConverter]::ToInt32($data, 4)
        MR = [BitConverter]::ToInt32($data, 8)
        MRExperience = [BitConverter]::ToInt32($data, 12)
        AR = [BitConverter]::ToInt32($data, 16)
        ARExperience = [BitConverter]::ToInt32($data, 20)
        Bytes = $data
    }
}

function Show-Ranks($Snapshot) {
    Write-Host ('HR {0} / MR {1} / AR {2}' -f $Snapshot.HR, $Snapshot.MR, $Snapshot.AR) -ForegroundColor Cyan
    Write-Host ('HR经验 {0} / MR经验 {1} / AR累计经验 {2}' -f $Snapshot.HRExperience, $Snapshot.MRExperience, $Snapshot.ARExperience)
}

# Refuse title-screen defaults, locked anomaly research and implausible values.
function Assert-Ranks($Snapshot) {
    if ($Snapshot.HR -lt 9 -or $Snapshot.HR -gt 999 -or $Snapshot.MR -lt 0 -or $Snapshot.MR -gt 999 -or
        $Snapshot.AR -lt 0 -or $Snapshot.AR -gt 300 -or $Snapshot.HRExperience -lt 0 -or
        $Snapshot.MRExperience -lt 0 -or $Snapshot.ARExperience -lt 0 -or $Snapshot.ARExperience -gt 10000000) {
        throw '等级数据不符合预期。请载入已解锁 HR 经验升级、HR 至少 9 的角色，停在离线据点。不要在标题画面使用。'
    }
}

# Returns cumulative experience at the beginning of the requested rank.
# Rows describe arrival ranks, so include Target itself (not Target-1).
# HR: https://mhrise.com/data/4536.html
# MR: https://macarongamemo.com/entry/mhrsb-mrp
function Get-RankExperience([ValidateSet('HR','MR')][string]$Kind, [int]$Target) {
    $minimum = if ($Kind -eq 'HR') { 9 } else { 7 }
    if ($Target -lt $minimum -or $Target -gt 999) { throw "目标 $Kind 应为 $minimum 至 999。" }
    $total = 0
    for ($r = $minimum; $r -le $Target; $r++) {
        if ($Kind -eq 'HR') {
            $cost = if ($r -le 16) {400} elseif ($r -le 21) {500} elseif ($r -le 31) {620} elseif ($r -le 41) {760} elseif ($r -le 51) {860} elseif ($r -le 101) {980} elseif ($r -le 501) {1330 + 350 * [int][Math]::Floor(($r-102)/50)} else {4180 + 400 * [int][Math]::Floor(($r-502)/50)}
        } else {
            $cost = if ($r -le 20) {500} elseif ($r -le 25) {1000} elseif ($r -le 30) {1200} elseif ($r -le 51) {1240+40*($r-31)} elseif ($r -le 90) {2120+80*[int][Math]::Floor(($r-52)/10)} elseif ($r -le 101) {2440+80*($r-91)} else {3340+100*[int][Math]::Floor(($r-102)/50)}
        }
        $total += $cost
    }
    return [int]$total
}

# Return the complete app save directory, never infer a Steam account if several exist.
function Select-SaveDirectory {
    if ($SaveDirectory) {
        $selected = (Resolve-Path -LiteralPath $SaveDirectory).Path
    } else {
        $roots = @()
        $hkcu = Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
        $hklm = Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue
        if ($hkcu.SteamPath) { $roots += $hkcu.SteamPath }
        if ($hklm.InstallPath) { $roots += $hklm.InstallPath }
        $steam = Get-Process steam -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($steam -and $steam.Path) { $roots += Split-Path -Parent $steam.Path }
        $candidates = @(
            foreach ($root in ($roots | Sort-Object -Unique)) {
                $userdata = Join-Path $root 'userdata'
                if (Test-Path -LiteralPath $userdata) {
                    foreach ($account in (Get-ChildItem -LiteralPath $userdata -Directory)) {
                        $candidate = Join-Path $account.FullName '1446780'
                        if (Test-Path -LiteralPath (Join-Path $candidate 'remote\win64_save\data001Slot.bin')) {
                            (Resolve-Path -LiteralPath $candidate).Path
                        }
                    }
                }
            }
        ) | Sort-Object -Unique
        $candidates = @($candidates)
        if ($candidates.Count -eq 0) { throw '找不到 Steam 存档。请使用 -SaveDirectory 指定 userdata\账号\1446780 的完整路径。' }
        if ($candidates.Count -eq 1) { $selected = $candidates[0] }
        else {
            Write-Host '发现多个账号存档，请选择当前角色所属账号：'
            for ($i = 0; $i -lt $candidates.Count; $i++) { Write-Host ('{0}: {1}' -f ($i+1), $candidates[$i]) }
            $choice = 0
            if (-not [int]::TryParse((Read-Host '输入编号'), [ref]$choice) -or $choice -lt 1 -or $choice -gt $candidates.Count) { throw '选择无效，已取消。' }
            $selected = $candidates[$choice-1]
        }
    }
    if ((Split-Path -Leaf $selected) -ne '1446780' -or -not (Test-Path -LiteralPath (Join-Path $selected 'remote\win64_save\data001Slot.bin'))) {
        throw '存档目录不正确，应选择 1446780 文件夹，而不是 remote 或 win64_save。'
    }
    return $selected
}

function Get-SaveManifest([string]$Root) {
    return @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName | ForEach-Object {
        [pscustomobject]@{File=$_.FullName.Substring($Root.Length+1);Bytes=$_.Length;SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
    })
}

# Hash before copying, hash the copy, then hash the source again. Abort on an
# autosave/cloud-sync race rather than treating a changing save as a good backup.
function Backup-Saves([string]$Source) {
    $root = [IO.Path]::GetFullPath($BackupDirectory)
    if ($root.TrimEnd('\') -eq $Source.TrimEnd('\') -or $root.StartsWith($Source.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) {
        throw '备份位置不能位于原存档目录内部。'
    }
    $folder = Join-Path $root ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    [void](New-Item -ItemType Directory -Path $folder -Force)
    $before = Get-SaveManifest $Source
    Copy-Item -LiteralPath $Source -Destination $folder -Recurse
    $copy = Get-SaveManifest (Join-Path $folder '1446780')
    $after = Get-SaveManifest $Source
    $a = ConvertTo-Json -InputObject $before -Compress
    if ($a -ne (ConvertTo-Json -InputObject $copy -Compress) -or $a -ne (ConvertTo-Json -InputObject $after -Compress)) {
        throw ('备份期间存档发生变化或校验不一致，未修改等级。请停止游戏内操作并重试。备份位于：' + $folder)
    }
    $before | Export-Csv -LiteralPath (Join-Path $folder 'sha256-manifest.csv') -NoTypeInformation -Encoding UTF8
    Write-Host ('备份完成，{0} 个文件校验一致：{1}' -f $before.Count, $folder) -ForegroundColor Green
    return $folder
}

try {
    if (-not [Environment]::Is64BitProcess) { throw '必须使用 64 位 PowerShell；请通过附带的启动器运行。' }
    $games = @(Get-Process MonsterHunterRise -ErrorAction SilentlyContinue)
    if ($games.Count -ne 1) { throw '请只启动一个 MonsterHunterRise.exe，并载入需要修改的角色。' }
    $game = $games[0]
    $exe = $game.MainModule.FileName
    Write-Host ('游戏：' + $exe)
    Write-Host '正在校验游戏版本……'
    if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne $supportedHash) {
        throw '游戏文件与已验证的 Steam 16.0.2.0 版本不同。为防止写错地址，已停止；不要自行删除哈希检查。'
    }
    $access = if ($Action -ne 'Inspect') { 0x438 } else { 0x410 }
    $handle = [MHRiseAR300.Native]::OpenProcess($access, $false, $game.Id)
    if ($handle -eq [IntPtr]::Zero) { throw '无法访问游戏进程。如果游戏以管理员运行，脚本也需要相同权限；无需关闭安全软件。' }
    $moduleBase = $game.MainModule.BaseAddress.ToInt64()
    $before = Get-RankSnapshot $moduleBase
    Show-Ranks $before
    Assert-Ranks $before
    if ($Action -eq 'Inspect') {
        Write-Host '只读检查完成，没有修改游戏或存档。'
        return
    }
    $kind = switch ($Action) { 'SetHR' {'HR'} 'SetMR' {'MR'} default {'AR'} }
    $byteOffset = switch ($kind) { 'HR' {0} 'MR' {8} default {16} }
    $currentRank = $before.$kind
    if ($kind -eq 'AR') {
        if ($before.MR -lt 10 -or $before.AR -lt 1) { throw 'AR 修改要求已解锁怪异研究且 MR 至少 10。' }
        if ($TargetRank -ne 0 -and $TargetRank -ne 300) { throw 'AR 功能的目标固定为 300。' }
        $desiredRank = 300
        $desiredXP = 335200
    } else {
        $minimum = if ($kind -eq 'HR') {9} else {7}
        if ($currentRank -lt $minimum) { throw "$kind 尚未解锁经验升级，不能跳过主线剧情解锁。" }
        if ($TargetRank -eq 0) {
            if (-not [int]::TryParse((Read-Host "输入目标 $kind（$minimum 至 999）"), [ref]$TargetRank)) { throw '目标等级不是整数，已取消。' }
        }
        $desiredRank = $TargetRank
        $desiredXP = Get-RankExperience $kind $desiredRank
    }
    if ($currentRank -eq $desiredRank) {
        Write-Host "当前已是 $kind $desiredRank，无需修改。"
        return
    }
    Write-Host "即将修改 $kind：$currentRank -> $desiredRank，累计经验 -> $desiredXP；其他等级和经验不变。"
    if ($kind -ne 'AR') {
        Write-Host '目标等级的经验将设为该级起点。降低等级也会降低累计经验。' -ForegroundColor Yellow
        Write-Host '不会完成剧情/紧急任务或修改解锁标志；跨越未解锁的等级上限可能被游戏重新限制，仍需完成相应任务。' -ForegroundColor Yellow
    }
    $source = Select-SaveDirectory
    Write-Host ('即将备份的存档：' + $source)
    $backup = Backup-Saves $source
    $latest = Get-RankSnapshot $moduleBase
    if ($latest.Address -ne $before.Address -or [Convert]::ToBase64String($latest.Bytes) -ne [Convert]::ToBase64String($before.Bytes)) {
        throw '核对后角色数据发生变化，未写入。请停在据点重新运行。'
    }
    $recordPath = Join-Path $backup 'change-record.json'
    $record = [ordered]@{ScriptVersion='2.1';Timestamp=(Get-Date -Format o);GameSHA256=$supportedHash;ProcessId=$game.Id;SaveSource=$source;Kind=$kind;BeforeHR=$before.HR;BeforeHRExperience=$before.HRExperience;BeforeMR=$before.MR;BeforeMRExperience=$before.MRExperience;BeforeAR=$before.AR;BeforeARExperience=$before.ARExperience;TargetRank=$desiredRank;TargetExperience=$desiredXP;OriginalRankBytesBase64=[Convert]::ToBase64String($before.Bytes);MemoryVerified=$false}
    $record | ConvertTo-Json | Set-Content -LiteralPath $recordPath -Encoding UTF8
    [byte[]]$newBytes = [BitConverter]::GetBytes([int]$desiredRank) + [BitConverter]::GetBytes([int]$desiredXP)
    $writeAddress = $before.Address + 0x18 + $byteOffset
    $originalPair = [byte[]]$before.Bytes[$byteOffset..($byteOffset+7)]
    $expectedBytes = [byte[]]$before.Bytes.Clone()
    [Array]::Copy($newBytes, 0, $expectedBytes, $byteOffset, 8)
    try {
        Write-GameBytes $writeAddress $newBytes
        $after = Get-RankSnapshot $moduleBase
        if ($after.Address -ne $before.Address -or [Convert]::ToBase64String($after.Bytes) -ne [Convert]::ToBase64String($expectedBytes)) {
            throw '写入后读回校验失败。'
        }
    } catch {
        $reason = $_.Exception.Message
        # Best-effort rollback of the same eight bytes; never replace disk saves here.
        try {
            Write-GameBytes $writeAddress $originalPair
            $restored = Read-GameBytes $writeAddress 8
            if ([Convert]::ToBase64String($restored) -ne [Convert]::ToBase64String($originalPair)) { throw '回读不一致' }
            throw ('ROLLBACK_OK: ' + $reason)
        } catch {
            if ($_.Exception.Message.StartsWith('ROLLBACK_OK:')) { throw ('修改失败，原等级及经验字节已恢复。' + $reason) }
            throw ('修改失败且无法确认回滚，请不要保存，退出游戏后使用备份。原因：' + $reason)
        }
    }
    $record.MemoryVerified = $true
    $record | ConvertTo-Json | Set-Content -LiteralPath $recordPath -Encoding UTF8
    Show-Ranks $after
    Write-Host "$kind $desiredRank 已写入内存并校验，其他等级及经验未变。" -ForegroundColor Green
    Write-Host '现在请在游戏中手动保存，返回标题，再载入同一角色。'
    Write-Host '需要再次查看时，重新运行选 1。'
} catch {
    Write-Host ('停止：' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if ($handle -ne [IntPtr]::Zero) { [void][MHRiseAR300.Native]::CloseHandle($handle) }
}
