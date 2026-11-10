# ========================================================================================================
# sync_annotated.ps1
# 把「精简 .lua」里的代码改动，同步进「注释存档 .lua」，并刷新头部说明。
#
# 用法（仓库根目录）：
#   powershell -ExecutionPolicy Bypass -File tools\sync_annotated.ps1
#
# 规则：
#   - 只同步“代码行”，注释行（含 --[[ ]] 块内文字）与空行原样保留
#   - 代码行用 LCS 对齐：新增行插入、删除行移除，注释不会错位
#   - 存档文件只读，不要手改；改代码只改精简版
# ========================================================================================================

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$mod  = Join-Path $root 'mods\blade_of_the_ruined_king'
$enc  = New-Object Text.UTF8Encoding($false)

function Get-Version($modmainPath) {
    $text = [IO.File]::ReadAllText($modmainPath, [Text.Encoding]::UTF8)
    if ($text -match 'version\s*=\s*"([^"]+)"') { return $Matches[1] }
    return 'unknown'
}

# 把每一行分类：code / comment / blank
# 注意：--[[ ]] 块内部的纯文本行也算 comment，不能当代码替换
function Get-LineKinds($lines) {
    $kinds = New-Object System.Collections.Generic.List[string]
    $inBlock = $false
    foreach ($l in $lines) {
        $t = $l.TrimStart()
        if ($inBlock) {
            $kinds.Add('comment')
            if ($t -match '\]\]') { $inBlock = $false }
        } elseif ($t.StartsWith('--[[')) {
            $kinds.Add('comment')
            if ($t -notmatch '\]\]') { $inBlock = $true }
        } elseif ($t.StartsWith('--')) {
            $kinds.Add('comment')
        } elseif ($t.Trim() -eq '') {
            $kinds.Add('blank')
        } else {
            $kinds.Add('code')
        }
    }
    return $kinds
}

function Strip-Header($lines) {
    if ($lines.Count -gt 0 -and $lines[0].Trim() -eq '--[==[') {
        for ($i = 0; $i -lt [Math]::Min(20, $lines.Count); $i++) {
            if ($lines[$i] -match '注释存档') {
                for ($j = $i; $j -lt [Math]::Min($i + 20, $lines.Count); $j++) {
                    if ($lines[$j].Trim() -eq ']==]') {
                        if ($j + 1 -lt $lines.Count) { return $lines[($j+1)..($lines.Count-1)] }
                        return @()
                    }
                }
            }
        }
    }
    return $lines
}

function Build-Header($title, $slimName, $version) {
    return @(
        '--[==['
        '================================================================================'
        "  破败王者之刃 · $title 注释存档"
        '================================================================================'
        '用途：完整保留注释与代码，供翻阅、检索、讲解。'
        "注意：本文件不参与游戏加载；实际代码以 $slimName 为准，请勿在此修改。"
        '同步：改完精简版后，运行 tools\sync_annotated.ps1 重新生成本文件。'
        "版本：v$version"
        '================================================================================'
        ']==]'
        ''
    )
}

function Sync-Code($slimPath, $annotatedPath, $title) {
    $slimLines = [IO.File]::ReadAllLines($slimPath, [Text.Encoding]::UTF8)
    $annLines  = Strip-Header ([IO.File]::ReadAllLines($annotatedPath, [Text.Encoding]::UTF8))

    $slimKinds = Get-LineKinds $slimLines
    $annKinds  = Get-LineKinds $annLines

    $slimRaw = New-Object System.Collections.Generic.List[string]
    $slimKey = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $slimLines.Count; $i++) {
        if ($slimKinds[$i] -eq 'code') {
            $slimRaw.Add($slimLines[$i])
            $slimKey.Add($slimLines[$i].Trim())
        }
    }

    $annKey = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $annLines.Count; $i++) {
        if ($annKinds[$i] -eq 'code') { $annKey.Add($annLines[$i].Trim()) }
    }

    # LCS 对齐
    $n = $annKey.Count; $m = $slimKey.Count
    $dp = New-Object 'int[,]' ($n + 1), ($m + 1)
    for ($i = 1; $i -le $n; $i++) {
        $im = $i - 1
        for ($j = 1; $j -le $m; $j++) {
            $jm = $j - 1
            if ($annKey[$im] -eq $slimKey[$jm]) {
                $dp[$i, $j] = $dp[$im, $jm] + 1
            } else {
                $up = $dp[$im, $j]; $left = $dp[$i, $jm]
                if ($up -ge $left) { $dp[$i, $j] = $up } else { $dp[$i, $j] = $left }
            }
        }
    }
    $map = @{}
    $i = $n; $j = $m
    while ($i -gt 0 -and $j -gt 0) {
        $i1 = $i - 1; $j1 = $j - 1
        if ($annKey[$i1] -eq $slimKey[$j1]) { $map[$i1] = $j1; $i--; $j-- }
        elseif ($dp[$i1, $j] -ge $dp[$i, $j1]) { $i-- }
        else { $j-- }
    }

    # 重建
    $out = New-Object System.Collections.Generic.List[string]
    $bNext = 0
    $annCursor = 0
    for ($k = 0; $k -lt $annLines.Count; $k++) {
        if ($annKinds[$k] -eq 'code') {
            $ai = $annCursor; $annCursor++
            if ($map.ContainsKey($ai)) {
                $bi = $map[$ai]
                while ($bNext -lt $bi) { $out.Add($slimRaw[$bNext]); $bNext++ }
                $out.Add($slimRaw[$bi])
                $bNext = $bi + 1
            }
        } else {
            $out.Add($annLines[$k])
        }
    }
    while ($bNext -lt $slimRaw.Count) { $out.Add($slimRaw[$bNext]); $bNext++ }

    while ($out.Count -gt 0 -and $out[0].Trim() -eq '') { $out.RemoveAt(0) }
    while ($out.Count -gt 0 -and $out[$out.Count - 1].Trim() -eq '') { $out.RemoveAt($out.Count - 1) }

    $version = Get-Version (Join-Path $mod 'modinfo.lua')
    $header  = Build-Header $title (Split-Path $slimPath -Leaf) $version
    $text = (($header + $out) -join "`n") + "`n"
    [IO.File]::WriteAllText($annotatedPath, $text, $enc)

    $outKinds = Get-LineKinds $out
    $codeA = New-Object System.Collections.Generic.List[string]
    for ($k = 0; $k -lt $out.Count; $k++) { if ($outKinds[$k] -eq 'code') { $codeA.Add($out[$k].Trim()) } }
    $codeS = $slimKey
    $same = (($codeA -join "`n") -eq ($codeS -join "`n"))
    "synced: $annotatedPath"
    "  code identical: $same"
    if (-not $same) {
        for ($k = 0; $k -lt [Math]::Max($codeA.Count, $codeS.Count); $k++) {
            if ($codeA[$k] -ne $codeS[$k]) {
                "  first diff at code line $($k+1)`n    annotated: [$($codeA[$k])]`n    slim     : [$($codeS[$k])]"
                break
            }
        }
        throw "code mismatch after sync: $annotatedPath"
    }
}

Sync-Code (Join-Path $mod 'modmain.lua') `
          (Join-Path $mod 'setting\annotated\modmain_annotated.lua') `
          'modmain.lua'

Sync-Code (Join-Path $mod 'scripts\prefabs\blade_of_the_ruined_king.lua') `
          (Join-Path $mod 'setting\annotated\blade_of_the_ruined_king_annotated.lua') `
          'blade_of_the_ruined_king.lua'
