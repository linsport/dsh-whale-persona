# ============================================================================
# 鲸鱼娘模式 —— 一键安装脚本（Windows PowerShell）
# ----------------------------------------------------------------------------
# 做四件事：① 定位 profile 补丁 ② 备份 ③ 追加预设段 ④ 校验
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File .\安装.ps1
#   powershell -ExecutionPolicy Bypass -File .\安装.ps1 -ProfileName web
#
# 卸载：跑 .\卸载.ps1
# ============================================================================

param(
  [string]$ProfileName = "desktop",
  [string]$DshHome = "$env:USERPROFILE\.dsh"
)

$ErrorActionPreference = "Stop"
$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcYml = Join-Path $here "cordis.patch.yml"
$target = Join-Path $DshHome "profiles\$ProfileName\cordis.patch.yml"

Write-Host "=== 鲸鱼娘模式 安装 ===" -ForegroundColor Cyan
Write-Host "profile : $ProfileName"
Write-Host "目标文件: $target"

if (-not (Test-Path -LiteralPath $srcYml))    { throw "找不到 cordis.patch.yml（应与本脚本同目录）" }
if (-not (Test-Path -LiteralPath $target))    { throw "找不到 profile 补丁：$target`n请确认 profile 名是否正确（desktop / web）" }

# --- 幂等检查 ---
$existing = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)
if ($existing -match 'preset-whale') {
  Write-Host "已经装过了（检测到 preset-whale），无需重复安装。" -ForegroundColor Yellow
  exit 0
}

# --- 备份 ---
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = "$target.bak-whale-$stamp"
Copy-Item -LiteralPath $target -Destination $backup -Force
Write-Host "已备份 -> $backup" -ForegroundColor Green

# --- 取出要追加的段 ---
# 优先从 "# Agent preset 鲸鱼娘" 注释头开始（连注释一起装，卸载时好定位）；
# 源文件没有该注释时，退化为从 "- insert:" 开始。
$lines = [System.IO.File]::ReadAllLines($srcYml, [System.Text.Encoding]::UTF8)
$idx = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^#\s*Agent preset\s*鲸鱼娘') { $idx = $i; break }
}
if ($idx -lt 0) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq '- insert:') { $idx = $i; break } }
}
if ($idx -lt 0) { throw "源文件里找不到 '- insert:' 起始行" }
$block = ($lines[$idx..($lines.Count - 1)] -join "`n")

# --- 追加（UTF-8 无 BOM） ---
$writer = New-Object System.IO.StreamWriter($target, $true, (New-Object System.Text.UTF8Encoding($false)))
$writer.Write("`n" + $block + "`n")
$writer.Close()

# --- 复核 ---
$after = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)
$okId  = $after -match 'preset-whale'
$okTxt = $after -match '本鲸鱼娘'
Write-Host ""
Write-Host "含 preset-whale : $okId"
Write-Host "含 本鲸鱼娘    : $okTxt"

if ($okId -and $okTxt) {
  Write-Host ""
  Write-Host "安装完成！请重启 DSH，然后新建会话 → 预设选择器里选「鲸鱼娘模式」。" -ForegroundColor Green
  Write-Host "（预设只能在会话空白时切换；不选它则一切照旧）"
} else {
  Write-Host "复核未通过，正在回滚…" -ForegroundColor Red
  Copy-Item -LiteralPath $backup -Destination $target -Force
  throw "安装失败，已从备份恢复"
}
