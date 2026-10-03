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

$head = $profileText.Substring(0, $idx)
$old  = $profileText.Substring($idx)

# ---- 拼新内容：头部原样 + 新 yml（确保以换行结尾，不多不少）----
$newText = $newText.TrimEnd("`r", "`n") + "`n"
$result  = $head + $newText

# ---- 校验 ----
$check = @{
  '旧压制词已清除' = -not ($result -match '轻微口癖|宁可没有|正文里也要克制|降浓度|情感度归零')
  '新放松条款在场' = ($result -match '收的是污染') -and ($result -match '正文口吻正常保留') -and ($result -match '口吻照常')
  'preset-whale 在场' = $result -match 'preset-whale'
  '插件数 19 行'   = ([regex]::Matches($result, '- id: tool-(fs|bash|pwsh|jobs|skill|goal|todo|web|subagent|workflow|ralph|ask-user)')).Count -gt 0
  '头部完整保留'   = $result.StartsWith($head)
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
