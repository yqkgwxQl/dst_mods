<#
  clean_scratch.ps1 —— 清理 _scratch\ 下的任务临时目录

  背景：仓库同时是工作区，临时产物只能落在 _scratch\。没有这个脚本，
        三个月后 _scratch 就会变成第二个 wd。

  用法：
    .\tools\clean_scratch.ps1                     预演：只列出，什么都不删
    .\tools\clean_scratch.ps1 -OlderThanDays 3    删除 3 天没动过的子目录
    .\tools\clean_scratch.ps1 -All -Force         全部清掉
    .\tools\clean_scratch.ps1 -All -Force -MoveToTrash   先移进 _trash\ 再删

  安全设计：
    * 无参数时一定是预演，不会误删
    * -All 必须配 -Force，防止手滑
    * 永远不删 _scratch 本身
    * -MoveToTrash 时先移动到 _trash\<原名>，保留可恢复性
#>
param(
    [int]$OlderThanDays = 0,
    [switch]$All,
    [switch]$MoveToTrash,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$repo    = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path $repo '_scratch'
$trash   = Join-Path $repo '_trash'

if (-not (Test-Path -LiteralPath $scratch)) {
    Write-Host "没有 _scratch\ 目录，无需清理。"
    return
}

function Get-DirSizeMB($path) {
    $bytes = (Get-ChildItem -LiteralPath $path -Recurse -File -ErrorAction SilentlyContinue |
              Measure-Object -Sum Length).Sum
    if (-not $bytes) { return 0 }
    return [math]::Round($bytes / 1MB, 2)
}

# ---- 违规检查：_scratch 根目录不该有散落文件 ----
$loose = Get-ChildItem -LiteralPath $scratch -File -Force -ErrorAction SilentlyContinue
if ($loose) {
    Write-Host ""
    Write-Host "[违规] _scratch\ 根目录下有散落文件，不符合工作区约定：" -ForegroundColor Yellow
    foreach ($f in $loose) {
        Write-Host ("   {0,-44} {1,8:N1} KB" -f $f.Name, ($f.Length / 1KB))
    }
    Write-Host "   约定要求：临时文件必须放在 _scratch\<日期>-<任务>\ 子目录里。" -ForegroundColor Yellow
}

# ---- 收集子目录 ----
$dirs = @(Get-ChildItem -LiteralPath $scratch -Directory -Force -ErrorAction SilentlyContinue)
if ($dirs.Count -eq 0) {
    Write-Host ""
    Write-Host "_scratch\ 下没有子目录，干净。"
    return
}

$rows = foreach ($d in $dirs) {
    $age = [int]((Get-Date) - $d.LastWriteTime).Days
    [pscustomobject]@{
        Name    = $d.Name
        SizeMB  = Get-DirSizeMB $d.FullName
        AgeDays = $age
        Modified = $d.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        FullPath = $d.FullName
    }
}

Write-Host ""
Write-Host "_scratch\ 下共 $($dirs.Count) 个任务目录：" -ForegroundColor Cyan
$rows | Sort-Object AgeDays -Descending |
    Format-Table Name, SizeMB, AgeDays, Modified -AutoSize | Out-String | Write-Host

$totalMB = [math]::Round(($rows | Measure-Object -Sum SizeMB).Sum, 2)
Write-Host "合计：$totalMB MB"

# ---- 选择目标 ----
if ($All) {
    if (-not $Force) {
        Write-Host ""
        Write-Host "-All 会删掉全部 $($dirs.Count) 个目录（$totalMB MB）。" -ForegroundColor Yellow
        Write-Host "确认要执行，请加 -Force：" -ForegroundColor Yellow
        Write-Host "   .\tools\clean_scratch.ps1 -All -Force" -ForegroundColor Yellow
        return
    }
    $targets = $rows
}
elseif ($OlderThanDays -gt 0) {
    $targets = @($rows | Where-Object { $_.AgeDays -ge $OlderThanDays })
}
else {
    Write-Host ""
    Write-Host "[预演] 什么都没有删。要真删请选一种：" -ForegroundColor Green
    Write-Host "   .\tools\clean_scratch.ps1 -OlderThanDays 3    # 删 3 天没动的"
    Write-Host "   .\tools\clean_scratch.ps1 -All -Force         # 全删"
    return
}

if ($targets.Count -eq 0) {
    Write-Host ""
    Write-Host "没有符合条件的目录。"
    return
}

# ---- 执行 ----
if (-not (Test-Path -LiteralPath $trash)) {
    New-Item -ItemType Directory -Force -Path $trash | Out-Null
}

$freed = 0
foreach ($t in $targets) {
    try {
        if ($MoveToTrash) {
            $dest = Join-Path $trash $t.Name
            if (Test-Path -LiteralPath $dest) { $dest = Join-Path $trash ("{0}_{1}" -f $t.Name, (Get-Date -Format 'HHmmss')) }
            Move-Item -LiteralPath $t.FullPath -Destination $dest
            Write-Host ("[移入 _trash] {0}  ({1} MB)" -f $t.Name, $t.SizeMB)
        }
        else {
            Remove-Item -LiteralPath $t.FullPath -Recurse -Force
            Write-Host ("[已删除]      {0}  ({1} MB)" -f $t.Name, $t.SizeMB)
        }
        $freed += $t.SizeMB
    }
    catch {
        Write-Host ("[失败]        {0}  {1}" -f $t.Name, $_.Exception.Message) -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "处理完成：$($targets.Count) 个目录，释放约 $([math]::Round($freed,2)) MB" -ForegroundColor Green
if ($MoveToTrash) {
    Write-Host "确认无误后清空 _trash\：Remove-Item '$trash' -Recurse -Force" -ForegroundColor Yellow
}
