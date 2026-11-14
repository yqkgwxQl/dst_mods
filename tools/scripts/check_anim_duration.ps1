<#
.SYNOPSIS
    检查 mod 动画包（build.bin）里每个符号帧的 duration。

.DESCRIPTION
    DST 的“手持符号”是按时间播放的：override 到 swap_object 之后，引擎按帧时长取样。
    duration = 1 时这一帧几乎立即过期，表现为「override 明明挂上了，手上却什么都不显示」，
    而同一个 build 当“地面实体”显示完全正常（地面是静态画法，不随时间取样）。

    实测：DST Mod Tool 对“单关键帧”的动画会导出 duration = 1；
    原版所有 swap 包的 duration 都在 2~8。把 1 改成 8 即可正常显示。

    导出动画后跑一次这个脚本，发现 duration = 1 就回工具里把 Duration 改成 8 再导出。

.PARAMETER ModsRoot
    mods 目录，默认是仓库根下的 mods。

.EXAMPLE
    .\tools\scripts\check_anim_duration.ps1
#>
[CmdletBinding()]
param(
    [string]$ModsRoot
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ModsRoot)) {
    $ModsRoot = Join-Path $PSScriptRoot '..\..\mods'
}
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Read-String([byte[]]$Bytes, [int]$Offset) {
    $len = [BitConverter]::ToUInt32($Bytes, $Offset)
    $text = [Text.Encoding]::UTF8.GetString($Bytes, $Offset + 4, $len)
    return @{ Text = $text; Next = $Offset + 4 + $len }
}

function Get-FrameInfo([byte[]]$Bytes) {
    $p = 8
    $symbolCount = [BitConverter]::ToUInt32($Bytes, $p); $p += 4
    $p += 4                                   # 总帧数字段，这里用不到
    $name = Read-String $Bytes $p; $p = $name.Next
    $atlasCount = [BitConverter]::ToUInt32($Bytes, $p); $p += 4
    for ($a = 0; $a -lt $atlasCount; $a++) {
        $atlas = Read-String $Bytes $p; $p = $atlas.Next
    }

    $result = @()
    for ($s = 0; $s -lt $symbolCount; $s++) {
        $hash = [BitConverter]::ToUInt32($Bytes, $p); $p += 4
        $frameCount = [BitConverter]::ToUInt32($Bytes, $p); $p += 4
        for ($f = 0; $f -lt $frameCount; $f++) {
            $frameNum = [BitConverter]::ToUInt32($Bytes, $p); $p += 4
            $duration = [BitConverter]::ToUInt32($Bytes, $p); $p += 4
            $x = [BitConverter]::ToSingle($Bytes, $p)
            $y = [BitConverter]::ToSingle($Bytes, $p + 4)
            $w = [BitConverter]::ToSingle($Bytes, $p + 8)
            $h = [BitConverter]::ToSingle($Bytes, $p + 12)
            $p += 16
            $p += 8                            # alphaidx + alphacount
            $result += [pscustomobject]@{
                Symbol   = ('{0:x8}' -f $hash)
                Frame    = $frameNum
                Duration = $duration
                Size     = ('{0}x{1}' -f [int]$w, [int]$h)
            }
        }
    }
    return $result
}

$mods = Get-ChildItem -Path $ModsRoot -Directory -ErrorAction SilentlyContinue
if (-not $mods) { Write-Host "找不到 mods 目录：$ModsRoot" -ForegroundColor Red; exit 2 }

$bad = 0
$total = 0
foreach ($mod in $mods) {
    $animDir = Join-Path $mod.FullName 'anim'
    if (-not (Test-Path $animDir)) { continue }
    foreach ($zip in Get-ChildItem -Path $animDir -Filter '*.zip' -File) {
        try {
            $archive = [IO.Compression.ZipFile]::OpenRead($zip.FullName)
        } catch { continue }
        try {
            $entry = $archive.GetEntry('build.bin')
            if ($null -eq $entry) { continue }
            $stream = $entry.Open()
            $memory = New-Object IO.MemoryStream
            $stream.CopyTo($memory)
            $stream.Dispose()
            $bytes = $memory.ToArray()
            $memory.Dispose()
        } finally { $archive.Dispose() }

        $isSwap = (Split-Path $zip -Leaf) -match 'swap'
        $frames = Get-FrameInfo $bytes
        foreach ($fr in $frames) {
            $total++
            $flag = ''
            if ($fr.Duration -le 1) {
                if ($isSwap) {
                    $bad++
                    $flag = '  <-- 可疑（swap build 的 duration <= 1，手持会不显示）'
                } else {
                    $flag = '  （地面/静态 build，duration 1 通常正常）'
                }
            }
            Write-Host ('{0,-14} {1,-40} symbol {2} frame {3} duration {4} size {5}{6}' -f `
                    $mod.Name, (Split-Path $zip -Leaf), $fr.Symbol, $fr.Frame, $fr.Duration, $fr.Size, $flag)
        }
    }
}

Write-Host ''
if ($bad -eq 0) {
    Write-Host "OK：$total 个帧里没有 swap build 的 duration <= 1。" -ForegroundColor Green
    exit 0
} else {
    Write-Host "发现 $bad 个 swap build 的 duration <= 1（共 $total 帧）。回 DST Mod Tool 里把 Duration 改成 8 再导出。" -ForegroundColor Yellow
    exit 1
}
