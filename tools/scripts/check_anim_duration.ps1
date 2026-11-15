<#
.SYNOPSIS
    检查 mod 动画包（zip）的结构、帧时长、build/symbol 名与锚点几何。

.DESCRIPTION
    检查内容：
    1. zip 条目：build.bin、atlas-0.tex（anim.bin 可选）
    2. build 名、symbol 名
    3. 每个 symbol 的 frame 坐标（x / y / w / h）与 duration
    4. atlas-0.tex 能否解码、尺寸
    5. swap build 的 duration <= 1 报警（手持会不显示）
    6. 可选：和参考 zip 对比 frame 几何（锚点是否一致）

    依赖：python（调用 cli.py）、tools/cli/stex/stex.exe。

.PARAMETER ModsRoot
    mods 目录，默认是仓库根下的 mods。

.PARAMETER Zip
    只检查指定的 zip；不传则扫描 ModsRoot 下所有 anim/*.zip。

.PARAMETER ExpectBuild
    期望的 build 名；传了会校验 build 名和第一个 symbol 名。

.PARAMETER RefZip
    参考 zip；传了会比较第一个 symbol 的 frame x/y/w/h。

.EXAMPLE
    .\tools\scripts\check_anim_duration.ps1

.EXAMPLE
    .\tools\scripts\check_anim_duration.ps1 -Zip mods\blade_of_the_ruined_king\anim\blade_glow_fx.zip -ExpectBuild blade_glow_fx
#>
[CmdletBinding()]
param(
    [string]$ModsRoot,
    [string]$Zip,
    [string]$ExpectBuild,
    [string]$RefZip
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ModsRoot)) {
    $ModsRoot = Join-Path $PSScriptRoot '..\..\mods'
}
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$cli = Join-Path $repo 'tools\cli\pyscripts\cli.py'
$stex = Join-Path $repo 'tools\cli\stex\stex.exe'
$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if ($null -eq $python) { Write-Host "找不到 python，无法调用 cli.py" -ForegroundColor Red; exit 2 }

Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:fail = 0
$script:warn = 0

function New-TempDir {
    $p = Join-Path $env:TEMP ('dsh_anim_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $p | Out-Null
    return $p
}

function Get-BuildXml([string]$zipPath, [string]$tempDir) {
    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entry = $archive.GetEntry('build.bin')
        if ($null -eq $entry) { return $null }
        $bin = Join-Path $tempDir 'build.bin'
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $bin, $true)
    } finally { $archive.Dispose() }

    & $python $cli $bin 2>&1 | Out-Null
    $xmlPath = Join-Path $tempDir 'build.xml'
    if (-not (Test-Path $xmlPath)) { return $null }
    return [xml](Get-Content $xmlPath -Raw)
}

function Get-AtlasSize([string]$zipPath, [string]$tempDir) {
    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entry = $archive.GetEntry('atlas-0.tex')
        if ($null -eq $entry) { return $null }
        $tex = Join-Path $tempDir 'atlas-0.tex'
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $tex, $true)
    } finally { $archive.Dispose() }

    $png = Join-Path $tempDir 'atlas.png'
    & $stex decompress -i $tex -o $png 2>&1 | Out-Null
    if (-not (Test-Path $png)) { return $null }

    $b = [IO.File]::ReadAllBytes($png)
    if ($b.Length -lt 24) { return $null }
    $wBytes = $b[16..19]; [Array]::Reverse($wBytes)
    $hBytes = $b[20..23]; [Array]::Reverse($hBytes)
    $w = [BitConverter]::ToUInt32($wBytes, 0)
    $h = [BitConverter]::ToUInt32($hBytes, 0)
    return "${w}x${h}"
}

function Get-FirstFrame($buildXml) {
    if ($null -eq $buildXml) { return $null }
    $symbols = @($buildXml.Build.Symbols.Symbol)
    if ($symbols.Count -eq 0) { return $null }
    $frames = @($symbols[0].Frame)
    if ($frames.Count -eq 0) { return $null }
    return $frames[0]
}

function Test-Zip([string]$zipPath, [string]$tempDir) {
    $name = Split-Path $zipPath -Leaf
    $entries = @()
    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try { $entries = @($archive.Entries | ForEach-Object { $_.FullName }) } finally { $archive.Dispose() }

    $problems = @()
    if ($entries -notcontains 'build.bin') { $problems += '缺 build.bin' }
    if ($entries -notcontains 'atlas-0.tex') { $problems += '缺 atlas-0.tex' }
    $hasAnim = $entries -contains 'anim.bin'

    $buildXml = Get-BuildXml $zipPath $tempDir
    $binPath = Join-Path $tempDir 'build.bin'
    $buildVersion = $null
    if (Test-Path $binPath) {
        $binBytes = [IO.File]::ReadAllBytes($binPath)
        if ($binBytes.Length -ge 8) { $buildVersion = [BitConverter]::ToUInt32($binBytes, 4) }
    }
    if ($buildVersion -ne 6) { $problems += "build 版本=$buildVersion，期望=6" }
    $buildName = $null
    $symbolName = $null
    $frame = $null
    $symbols = @()
    if ($null -ne $buildXml) {
        $buildName = $buildXml.Build.name
        $symbols = @($buildXml.Build.Symbols.Symbol)
        if ($symbols.Count -gt 0) {
            $symbolName = $symbols[0].name
            $frames = @($symbols[0].Frame)
            if ($frames.Count -gt 0) { $frame = $frames[0] }
        }
    } else {
        $problems += 'build.bin 无法解析'
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectBuild)) {
        if ($buildName -ne $ExpectBuild) { $problems += "build 名=$buildName，期望=$ExpectBuild" }
        if ($symbols.Count -eq 1 -and $symbolName -ne $ExpectBuild) {
            $problems += "symbol 名=$symbolName，期望=$ExpectBuild"
        }
    }

    $atlasSize = Get-AtlasSize $zipPath $tempDir
    if ($null -eq $atlasSize) { $problems += 'atlas-0.tex 无法解码' }

    $dur = $null
    $isSwap = $name -match 'swap'
    foreach ($sym in $symbols) {
        foreach ($fr in @($sym.Frame)) {
            $d = [int]$fr.duration
            if ($null -eq $dur -or $d -lt $dur) { $dur = $d }
            if ($d -le 1 -and $isSwap) {
                $problems += ("swap build 的 duration <= 1（symbol={0}）" -f $sym.name)
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($RefZip) -and $symbols.Count -gt 0) {
        $refTemp = New-TempDir
        try {
            $refXml = Get-BuildXml $RefZip $refTemp
            $refFrame = Get-FirstFrame $refXml
            if ($null -ne $refFrame) {
                $keys = 'x', 'y', 'w', 'h'
                foreach ($sym in $symbols) {
                    $fr = @($sym.Frame)[0]
                    if ($null -eq $fr) { continue }
                    foreach ($k in $keys) {
                        $a = [double]$fr.$k
                        $b = [double]$refFrame.$k
                        if ([math]::Abs($a - $b) -gt 0.01) {
                            $problems += ("symbol {0} frame {1}={2}，参考={3}" -f $sym.name, $k, $a, $b)
                        }
                    }
                }
            }
        } finally { Remove-Item $refTemp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    $status = 'OK'
    if ($problems.Count -gt 0) { $status = 'FAIL'; $script:fail++ }
    elseif ($null -eq $frame) { $status = 'WARN'; $script:warn++ }

    $frameText = 'none'
    if ($null -ne $frame) {
        $frameText = ('x={0} y={1} w={2} h={3}' -f $frame.x, $frame.y, $frame.w, $frame.h)
    }
    $symbolLabel = $symbolName
    if ($symbols.Count -gt 1) {
        $symbolLabel = ('{0} symbols: {1}' -f $symbols.Count, (($symbols | ForEach-Object { $_.name }) -join ','))
    }
    Write-Host ('{0,-40} build={1} ver={2} {3} dur={4} {5} atlas={6} anim={7} [{8}]' -f `
            $name, $buildName, $buildVersion, $symbolLabel, $dur, $frameText, $atlasSize, $(if ($hasAnim) { 'yes' } else { 'no' }), $status)
    foreach ($p in $problems) { Write-Host ("    - " + $p) -ForegroundColor Yellow }
}

$temp = New-TempDir
try {
    if (-not [string]::IsNullOrWhiteSpace($Zip)) {
        Test-Zip (Resolve-Path $Zip).Path $temp
    } else {
        $mods = Get-ChildItem -Path $ModsRoot -Directory -ErrorAction SilentlyContinue
        if (-not $mods) { Write-Host "找不到 mods 目录：$ModsRoot" -ForegroundColor Red; exit 2 }
        foreach ($mod in $mods) {
            $animDir = Join-Path $mod.FullName 'anim'
            if (-not (Test-Path $animDir)) { continue }
            foreach ($z in Get-ChildItem -Path $animDir -Filter '*.zip' -File) {
                Test-Zip $z.FullName $temp
            }
        }
    }
} finally {
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:fail -eq 0) {
    Write-Host ("OK：没有失败项（WARN={0}）" -f $script:warn) -ForegroundColor Green
    exit 0
} else {
    Write-Host ("发现 {0} 个失败项；按上面的逐条修复后重新导出。" -f $script:fail) -ForegroundColor Yellow
    exit 1
}
