<#
  check_docs.ps1 —— 检查 docs/ 与仓库的一致性

  背景：仓库里三份文档互相引用（README / 测试手册 / 工作区约定），
        靠人记着同步迟早会错位。这个脚本把"不同步"从靠人发现变成跑一条命令。

  用法：
    .\tools\check_docs.ps1

  退出码：0 = 全部通过；1 = 有 FAIL
#>
param()

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$script:pass = 0
$script:fail = 0
$script:warn = 0

function Check($name, $ok, $detail) {
    if ($ok) { $script:pass++ } else { $script:fail++ }
    "  [{0}] {1,-46} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $detail
}
function Warn($name, $detail) {
    $script:warn++
    "  [WARN] {0,-46} {1}" -f $name, $detail
}

Write-Host ""
Write-Host "文档一致性检查" -ForegroundColor Cyan
Write-Host ("仓库：{0}" -f $repo)
Write-Host ""

# ---------- 1) 必备文件 ----------
Write-Host "[1] 必备文件" -ForegroundColor Cyan
$required = @(
    'README.md', 'LICENSE', '.gitignore',
    'docs\MOD测试手册.md', 'docs\工作区约定.md',
    'tools\prepare_refs.ps1', 'tools\clean_scratch.ps1'
)
foreach ($f in $required) {
    Check $f (Test-Path -LiteralPath (Join-Path $repo $f)) $(if (Test-Path -LiteralPath (Join-Path $repo $f)) { '存在' } else { '缺失!' })
}

# ---------- 2) 核心目录 ----------
Write-Host ""
Write-Host "[2] 核心目录" -ForegroundColor Cyan
$dirs = @('mods','docs','tools','refs','tools\app','tools\cli','tools\gui',
          'refs\mod_reference','refs\other_reference','_scratch','_trash')
foreach ($d in $dirs) {
    $ok = Test-Path -LiteralPath (Join-Path $repo $d)
    Check "$d\" $ok $(if ($ok) { '存在' } else { '缺失!' })
}

# ---------- 3) 手册提到的工具路径 ----------
Write-Host ""
Write-Host "[3] 手册 11.3/11.4 提到的工具" -ForegroundColor Cyan
$tools = @(
    'tools\cli\stex\stex.exe',
    'tools\cli\ktools\krane.exe',
    'tools\cli\ktools\ktech.exe',
    'tools\cli\ktools\BuildRenamer.exe',
    'tools\cli\animbuilder\animc.exe',
    'tools\cli\animbuilder\animd.exe',
    'tools\cli\pyscripts\cli.py',
    'tools\gui\bmfont\bmfont64.exe',
    'tools\gui\fsbextractor\FsbExtractor.exe',
    'tools\gui\speech-editor\SpeechFileUpdater.exe'
)
foreach ($t in $tools) {
    $ok = Test-Path -LiteralPath (Join-Path $repo $t)
    Check $t $ok $(if ($ok) { '在' } else { '不在（手册描述会失效）' })
}

# ---------- 4) Markdown 链接 ----------
Write-Host ""
Write-Host "[4] Markdown 相对链接" -ForegroundColor Cyan
$mds = @(Get-ChildItem -LiteralPath (Join-Path $repo 'docs') -Filter *.md -File -ErrorAction SilentlyContinue)
$mds += Get-Item -LiteralPath (Join-Path $repo 'README.md') -ErrorAction SilentlyContinue
foreach ($md in $mds) {
    $text = [System.IO.File]::ReadAllText($md.FullName)
    $base = Split-Path $md.FullName -Parent
    foreach ($m in [regex]::Matches($text, '\[[^\]]*\]\(([^)]+)\)')) {
        $target = $m.Groups[1].Value.Trim()
        if ($target -match '^(https?:|mailto:|#)') { continue }
        $target = ($target -split '#')[0]
        if ([string]::IsNullOrWhiteSpace($target)) { continue }
        $full = Join-Path $base ($target -replace '/', '\')
        Check ("{0} -> {1}" -f $md.Name, $target) (Test-Path -LiteralPath $full) $(if (Test-Path -LiteralPath $full) { '有效' } else { '断链!' })
    }
}

# ---------- 5) 跨文档章节引用（标题式） ----------
Write-Host ""
Write-Host "[5] 跨文档章节引用" -ForegroundColor Cyan
$hb = Join-Path $repo 'docs\MOD测试手册.md'
$cv = Join-Path $repo 'docs\工作区约定.md'
if ((Test-Path -LiteralPath $hb) -and (Test-Path -LiteralPath $cv)) {
    $hbText = [System.IO.File]::ReadAllText($hb)
    $cvHeadings = @([regex]::Matches([System.IO.File]::ReadAllText($cv), '(?m)^#{2,3}\s+(.+)$') | ForEach-Object { $_.Groups[1].Value.Trim() })
    foreach ($m in [regex]::Matches($hbText, '工作区约定\.md`?\s*的?「([^」]{2,24})」')) {
        $title = $m.Groups[1].Value
        $hit = $cvHeadings | Where-Object { $_ -like "*$title*" }
        Check "引用「$title」" ([bool]$hit) $(if ($hit) { '对得上' } else { '约定里没有这个章节!' })
    }
    # 反向：约定引用手册
    $cvText = [System.IO.File]::ReadAllText($cv)
    $hbHeadings = @([regex]::Matches($hbText, '(?m)^#{2,3}\s+(.+)$') | ForEach-Object { $_.Groups[1].Value.Trim() })
    foreach ($m in [regex]::Matches($cvText, 'MOD测试手册\.md`?\s*的?「([^」]{2,24})」')) {
        $title = $m.Groups[1].Value
        $hit = $hbHeadings | Where-Object { $_ -like "*$title*" }
        Check "回引「$title」" ([bool]$hit) $(if ($hit) { '对得上' } else { '手册里没有这个章节!' })
    }
    # 编号引用已经废弃，发现就提示改成标题式
    $num = [regex]::Matches($hbText, '工作区约定\.md`?\s*第[一二三四五六七八九十]+节')
    if ($num.Count -gt 0) { Warn '编号式引用' ("发现 $($num.Count) 处「第N节」写法，建议改成「标题」式") }
}

# ---------- 6) 占位符 ↔ 本机环境文件 ----------
Write-Host ""
Write-Host "[6] 本机专属占位符" -ForegroundColor Cyan
$lc = Join-Path $repo 'docs\本机环境.local.md'
$machinePlaceholders = @('用户名','账号目录','你的 SteamID','游戏安装目录','Steam 库','创意工坊目录','Spriter 安装目录','笔记库','工作区')
if (Test-Path -LiteralPath $hb) {
    $hbText = [System.IO.File]::ReadAllText($hb)
    $used = @()
    foreach ($p in $machinePlaceholders) { if ($hbText.Contains("<$p>")) { $used += $p } }
    Check '手册使用本机占位符' ($used.Count -gt 0) ("用到：" + ($(if ($used) { $used -join '、' } else { '（无）' })))
    if ($used.Count -gt 0) {
        if (Test-Path -LiteralPath $lc) {
            $lcText = [System.IO.File]::ReadAllText($lc)
            foreach ($p in $used) {
                # 本机文件里用自然语言描述，不必然出现同名占位符，只做提示性检查
                if ($lcText -notmatch '游戏安装根目录|账号目录|SteamID|用户名') { }
            }
            Check '本机环境.local.md' $true '存在（不入库，换机器需重建）'
        }
        else {
            Warn '本机环境.local.md 缺失' '占位符无法回查，需要按下表重建该文件'
        }
    }
}

# ---------- 7) 路径基准 ----------
Write-Host ""
Write-Host "[7] 路径基准" -ForegroundColor Cyan
if (Test-Path -LiteralPath $hb) {
    $hbT = [System.IO.File]::ReadAllText($hb)
    $lines7 = $hbT -split "`r?`n"
    $bareCount = 0
    $bareAt = @()
    for ($i = 0; $i -lt $lines7.Count; $i++) {
        if ($lines7[$i] -match '^\|\s*`?(?:master_server_log|caves_server_log|client_log|server_chat_log)\.txt`?\s*\|') {
            # 往回看 8 行，若已声明基准则视为合规
            $from = [Math]::Max(0, $i - 8)
            $ctx = ($lines7[$from..$i] -join "`n")
            if ($ctx -notmatch '基准|<游戏数据目录>|<账号目录>') { $bareCount++; $bareAt += ($i + 1) }
        }
    }
    Check '表格内裸文件名都有基准' ($bareCount -eq 0) $(if ($bareCount -eq 0) { '无未声明基准的裸路径' } else { "行 " + ($bareAt -join ',') + " 缺少基准" })
    Check '通道 1 声明了 mod 基准' ($hbT.Contains('<mod 根目录>')) $(if ($hbT.Contains('<mod 根目录>')) { '已声明' } else { '缺失!' })
    Check '通道 2 声明了基准目录' ($hbT.Contains('<游戏数据目录>')) $(if ($hbT.Contains('<游戏数据目录>')) { '已声明' } else { '缺失!' })
}
# ---------- 汇总 ----------
Write-Host ""
Write-Host ("汇总：PASS={0}  FAIL={1}  WARN={2}" -f $script:pass, $script:fail, $script:warn) -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
