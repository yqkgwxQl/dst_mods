# 改动盘点：列出工作区的新增 / 删除 / 修改，并按类别提示需要同步的文档
# 用法：powershell -ExecutionPolicy Bypass -File tools\scripts\check_changes.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Push-Location $root
try {
    $raw = git status --porcelain=v1 2>$null
    if (-not $raw) {
        Write-Host "工作区干净，没有需要盘点的改动。" -ForegroundColor Green
        return
    }

    $entries = @()
    foreach ($line in $raw) {
        if ($line.Length -lt 4) { continue }
        $code = $line.Substring(0, 2)
        $path = $line.Substring(3).Trim().Trim('"')
        $entries += [pscustomobject]@{ Code = $code; Path = $path }
    }

    function Show-Group($title, $items) {
        if ($items.Count -eq 0) { return }
        Write-Host ""
        Write-Host ("== {0}（{1}）==" -f $title, $items.Count) -ForegroundColor Cyan
        $items | ForEach-Object { Write-Host ("  {0}  {1}" -f $_.Code, $_.Path) }
    }

    $codeFiles = @($entries | Where-Object { $_.Path -match '\.lua$' -and $_.Path -notmatch '_annotated\.lua$' })
    $docFiles = @($entries | Where-Object { $_.Path -match '\.md$' })
    $assetFiles = @($entries | Where-Object { $_.Path -match '\.(zip|png|jpg|jpeg|tex|xml|scml|glb)$' -or $_.Path -match '(^|/)anim/' })
    $toolFiles = @($entries | Where-Object { $_.Path -match '^tools/' -and $_.Path -notmatch '\.(zip|png)$' })
    $deleted = @($entries | Where-Object { $_.Code -match 'D' })
    $added = @($entries | Where-Object { $_.Code -eq '??' })

    Show-Group "代码（.lua）" $codeFiles
    Show-Group "文档（.md）" $docFiles
    Show-Group "素材 / 构建（zip、png、scml 等）" $assetFiles
    Show-Group "工具脚本" $toolFiles
    Show-Group "删除的文件" $deleted
    Show-Group "未跟踪的新文件" $added

    Write-Host ""
    Write-Host "== 建议的同步动作 ==" -ForegroundColor Yellow
    if ($codeFiles.Count -gt 0) {
        Write-Host "  [代码] 跑 tools\scripts\sync_annotated.ps1；若改的是数值/机制，对照 mechanic_design.md"
    }
    if ($docFiles.Count -gt 0) {
        Write-Host "  [文档] 跑 tools\scripts\check_docs.ps1；检查链接、版本号、状态描述"
    }
    if ($assetFiles.Count -gt 0) {
        Write-Host "  [素材] 更新 setting_description.md 的素材清单与 README 的状态描述"
    }
    if ($toolFiles.Count -gt 0) {
        Write-Host "  [工具] 核对脚本头部注释，并同步本清单的「自动命令」一节"
    }
    if ($deleted.Count -gt 0) {
        Write-Host "  [删除] 用 git grep 搜索被删文件名，清理文档与代码里的引用："
        foreach ($d in $deleted) {
            $name = Split-Path $d.Path -Leaf
            Write-Host ("         git grep -n ""{0}""" -f $name)
        }
    }
    if ($added.Count -gt 0) {
        Write-Host "  [新增] 确认是否要入库；临时产物 / 备份目录应加入 .gitignore"
    }
    if (($codeFiles.Count + $docFiles.Count + $assetFiles.Count + $toolFiles.Count + $deleted.Count + $added.Count) -eq 0) {
        Write-Host "  未识别出需要同步的类别，人工过一遍 git status"
    }
}
finally {
    Pop-Location
}
