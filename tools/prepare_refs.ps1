<#
  prepare_refs.ps1 —— 从游戏包重建 refs\other_reference\scripts

  为什么需要它：
    refs\ 不进 git（约 270 MB，且是 Klei 的游戏源码，涉及版权），
    所以换机器 clone 下来 refs\ 是空的。跑这个脚本从游戏包重新解压即可。

  用法：
    powershell -ExecutionPolicy Bypass -File .\prepare_refs.ps1
    .\prepare_refs.ps1 -Force                         覆盖已有的 refs\other_reference\scripts
    .\prepare_refs.ps1 -GameDir "D:\Games\Don't Starve Together"

  说明：
    脚本只重建 scripts 这一项。refs 下的其他内容（mod_reference、Wilson_sample、
    notes、modtemplate）是人工整理的东西，不在这里重建。
#>
param(
    [string]$GameDir = "",
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($GameDir)) {
    throw "请用 -GameDir 指定游戏安装目录。`n例：.\prepare_refs.ps1 -GameDir ""D:\SteamLibrary\steamapps\common\Don't Starve Together"""
}


# tools\ 的父目录就是仓库根
$repo = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $repo 'refs\other_reference\scripts'
$zip  = Join-Path $GameDir 'data\databundles\scripts.zip'
$ver  = Join-Path $GameDir 'version.txt'

# ---- 前置检查 ----
if (-not (Test-Path -LiteralPath $zip)) {
    throw "找不到游戏源码包：$zip`n如果游戏不在默认位置，用 -GameDir 指定安装目录。"
}

$version = if (Test-Path -LiteralPath $ver) { (Get-Content -LiteralPath $ver -Raw).Trim() } else { 'unknown' }

# 首 4 字节必须是 PK\x03\x04 —— 不是所有 .zip 都是标准 zip（踩过这个坑）
$fs = [System.IO.File]::OpenRead($zip)
$buf = New-Object byte[] 4
$null = $fs.Read($buf, 0, 4)
$fs.Close()
if (-not ($buf[0] -eq 0x50 -and $buf[1] -eq 0x4B -and $buf[2] -eq 0x03 -and $buf[3] -eq 0x04)) {
    throw "不是标准 zip 格式，无法解压：$zip"
}

if (Test-Path -LiteralPath $dest) {
    if (-not $Force) {
        throw "目标已存在：$dest`n确认要覆盖请加 -Force。"
    }
    Write-Host "删除旧副本：$dest"
    Remove-Item -LiteralPath $dest -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $dest | Out-Null

# ---- 解压（只取 scripts/ 前缀，剥掉它） ----
Add-Type -AssemblyName System.IO.Compression.FileSystem
Write-Host "解压中：$zip"
$z = [System.IO.Compression.ZipFile]::OpenRead($zip)
$n = 0
foreach ($e in $z.Entries) {
    if (-not $e.FullName.StartsWith('scripts/')) { continue }
    $rel = $e.FullName.Substring('scripts/'.Length)
    if ([string]::IsNullOrWhiteSpace($rel)) { continue }
    $out = Join-Path $dest ($rel -replace '/', '\')
    $dir = Split-Path $out -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $out, $true)
    $n++
}
$z.Dispose()

# ---- 校验与报告 ----
$count = (Get-ChildItem -LiteralPath $dest -Recurse -File).Count
if ($count -lt 3000) {
    Write-Warning "只解出 $count 个文件，明显偏少（正常约 4100 个），请检查游戏包是否完整。"
}

Write-Host ""
Write-Host "完成：$count 个文件"
Write-Host "  目标：$dest"
Write-Host "  游戏版本：$version"
Write-Host ""
Write-Host "提醒：游戏更新后本目录就会过期。查 API 前先确认 version.txt 与上面这个版本号一致。"
