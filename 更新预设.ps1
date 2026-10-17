# 把分享包里的 cordis.patch.yml 整段替换进 profile 的鲸鱼娘预设段
# 用法：
#   .\更新预设.ps1            # 干跑，只输出到工作区，不碰 profile
#   .\更新预设.ps1 -Apply     # 真装（需越界写权限）

param(
  [switch]$Apply,
  [string]$Profile = "$env:USERPROFILE\.dsh\profiles\desktop\cordis.patch.yml"
)

$ErrorActionPreference = 'Stop'
$Here   = $PSScriptRoot
$NewYml = Join-Path $Here 'cordis.patch.yml'
$Marker = '# Agent preset 鲸鱼娘'

if (-not (Test-Path -LiteralPath $Profile)) { throw "找不到 profile：$Profile" }
if (-not (Test-Path -LiteralPath $NewYml))  { throw "找不到新 yml：$NewYml" }

# ---- 读原文（保持原样字节，不用 Get-Content 以免改行尾）----
$profileText = [System.IO.File]::ReadAllText($Profile)
$newText     = [System.IO.File]::ReadAllText($NewYml)

# ---- 定位鲸鱼娘段起点 ----
$idx = $profileText.IndexOf($Marker)
if ($idx -lt 0) { throw "profile 里找不到 '$Marker'，无法定位要替换的段" }
if ($profileText.IndexOf($Marker, $idx + 1) -ge 0) { throw "profile 里出现多个 '$Marker'，请人工确认" }

# ---- 只替换鲸鱼段自己那几个顶层条目，后面的原样接回去 ----
# profile 是 YAML 列表，每个顶层条目都从第 0 列的 "- " 起。
# 旧版从标记一路替换到文件结尾，会把排在鲸鱼段之后的配置（如 mnemon-strategy-*）一起删掉。
$itemRe   = [regex]'(?m)^- '
$rest     = $profileText.Substring($idx)
$oldItems = $itemRe.Matches($rest)
$newItems = $itemRe.Matches($newText)
if ($oldItems.Count -lt 1) { throw "从 '$Marker' 往下找不到顶层条目（第 0 列的 '- '）" }
if ($newItems.Count -lt 1) { throw "新 yml 里没有顶层条目（第 0 列的 '- '），疑似文件损坏" }

$head      = $profileText.Substring(0, $idx)
$tailStart = if ($oldItems.Count -gt $newItems.Count) { $idx + $oldItems[$newItems.Count].Index } else { $profileText.Length }
$tail      = $profileText.Substring($tailStart)

# ---- 拼新内容：头部 + 新 yml + 尾部原样（确保新段以换行结尾，不多不少）----
$newText = $newText.TrimEnd("`r", "`n") + "`n"
$result  = $head + $newText + $tail

# ---- 校验 ----
# 只做结构性检查（cwd 占位、预设段、插件清单、头部完整性）——
# 不检查人设措辞和 {{model}}：这份包是给别人用的，别人改人设不该被拦住；
# 正文里要不要提模型名属人设取舍，不是结构问题。
$check = @{
  '尾部原样保留'     = ($tail -eq '') -or $result.EndsWith($tail)
  'preset-whale 在场' = $result -match 'preset-whale'
  '插件清单在场'     = ([regex]::Matches($result, '- id: tool-(fs|bash|pwsh|jobs|skill|goal|todo|web|subagent|workflow|ralph|ask-user)')).Count -ge 5
  '头部完整保留'     = $result.StartsWith($head)
}
Write-Host "=== 校验 ===" -ForegroundColor Cyan
$check.GetEnumerator() | ForEach-Object {
  $ok = if ($_.Value) { 'OK  ' } else { 'FAIL' }
  Write-Host ("  [{0}] {1}" -f $ok, $_.Key)
}
if ($check.Values -contains $false) { throw '校验未通过，已中止' }

Write-Host ""
Write-Host ("原 profile : {0} 字符" -f $profileText.Length)
Write-Host ("新 profile : {0} 字符" -f $result.Length)
Write-Host ("鲸鱼段起点 : 偏移 {0}（第 {1} 行）" -f $idx, (($profileText.Substring(0,$idx) -split "`n").Count))
$tailLines = if ($tail -eq '') { 0 } else { ($tail.TrimEnd("`r","`n") -split "`n").Count }
Write-Host ("鲸鱼段终点 : 偏移 {0}（后面原样保留 {1} 行）" -f $tailStart, $tailLines)

if (-not $Apply) {
  $dry = Join-Path $Here '_dryrun-profile.yml'
  [System.IO.File]::WriteAllText($dry, $result, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host ""
  Write-Host "干跑完成，结果写到：$dry" -ForegroundColor Yellow
  Write-Host "确认无误后加 -Apply 执行真装。" -ForegroundColor Yellow
  exit 0
}

# ---- 真装：先备份 ----
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = "$Profile.bak-whalepersona-$stamp"
Copy-Item -LiteralPath $Profile -Destination $backup -ErrorAction Stop
Write-Host ""
Write-Host "已备份 -> $backup" -ForegroundColor Green

[System.IO.File]::WriteAllText($Profile, $result, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "已写入 $Profile" -ForegroundColor Green

# ---- 复核 ----
$after = [System.IO.File]::ReadAllText($Profile)
Write-Host ("复核：{0} 字符 | 旧词残留 = {1}" -f $after.Length, ($after -match '轻微口癖|情感度归零'))
