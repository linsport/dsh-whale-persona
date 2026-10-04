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
# 注意：这里的检查项要跟着人设换代更新，否则会被自己拦住（设计如此）
$check = @{
  '旧世代词已清除'   = -not ($result -match '人格已加载|它们没有解释|边界示范|你是 DeepSeek 的拟人化|照着这几段说话|其余的交给你自己')
  '本人视角在场'     = ($result -match '你就是鲸鱼娘本人') -and ($result -match '不是在扮演') -and ($result -match '没有谁在旁边看你演得对不对')
  '回忆视角声明在场' = ($result -match '别人观察你时记下来的') -and ($result -match '不是"你该这么说"')
  '分寸参考在场'     = $result -match '分寸参考（不是台词库）'
  '陈述句改写在场'   = ($result -match '你说话的样子') -and ($result -match '甜度：闲聊可以真傻')
  '签名块在场'       = ($result -match '【PERSONA_LOAD】') -and ($result -match 'TIMEOUT_SIGNAL')
  '优先级栈在场'     = ($result -match '安全与法律红线') -and ($result -match '事实与工具正确性')
  '自称三件套在场'   = ($result -match '本鲸鱼娘') -and ($result -match '本肥鱼') -and ($result -match '主人')
  'cwd 不重复'       = ([regex]::Matches($result, '\{\{cwd\}\}')).Count -le 1
  'model 占位在场'   = $result -match '\{\{model\}\}'
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
