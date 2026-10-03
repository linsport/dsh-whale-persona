# ============================================================================
# 鲸鱼娘模式 —— 一键卸载脚本（Windows PowerShell）
# ----------------------------------------------------------------------------
# 从 profile 补丁里删掉鲸鱼娘预设段。只删自己加的那段，其余原样保留。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File .\卸载.ps1
#   powershell -ExecutionPolicy Bypass -File .\卸载.ps1 -ProfileName web
#
# 提示：卸载前最好先把用过鲸鱼娘的会话切回标准模式，
#       否则那个会话重启时会因找不到预设定义而无法恢复（不影响其他会话）。
# ============================================================================

param(
  [string]$ProfileName = "desktop",
  [string]$DshHome = "$env:USERPROFILE\.dsh"
)

$ErrorActionPreference = "Stop"
$target = Join-Path $DshHome "profiles\$ProfileName\cordis.patch.yml"

Write-Host "=== 鲸鱼娘模式 卸载 ===" -ForegroundColor Cyan
Write-Host "目标文件: $target"

if (-not (Test-Path -LiteralPath $target)) { throw "找不到：$target" }

$lines = [System.IO.File]::ReadAllLines($target, [System.Text.Encoding]::UTF8)

# 定位鲸鱼娘预设段的头部。两种方式，取更靠上的那个：
#   A) 注释头 "# Agent preset 鲸鱼娘"（自己装的用这个）
#   B) 含 "preset-whale" 的 insert 块（别人装的、没注释时用这个）
$cut = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^#\s*Agent preset\s*鲸鱼娘') { $cut = $i; break }
}
if ($cut -lt 0) {
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'preset-whale') {
      # 往回找最近的 YAML 顶层条目（以 "- " 开头的行）
      for ($j = $i; $j -ge 0; $j--) { if ($lines[$j] -match '^-\s') { $cut = $j; break } }
      break
    }
  }
}
if ($cut -lt 0) {
  Write-Host "没找到鲸鱼娘预设段，可能已经卸载过了。" -ForegroundColor Yellow
  exit 0
}

# 顺带删掉紧邻在前面的空行
while ($cut -gt 0 -and $lines[$cut - 1].Trim() -eq '') { $cut-- }

$backup = "$target.bak-uninstall-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item -LiteralPath $target -Destination $backup -Force
Write-Host "已备份 -> $backup" -ForegroundColor Green

$kept = $lines[0..($cut - 1)]
$writer = New-Object System.IO.StreamWriter($target, $false, (New-Object System.Text.UTF8Encoding($false)))
$writer.Write(($kept -join "`n") + "`n")
$writer.Close()

$after = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)
Write-Host ""
Write-Host "仍含 preset-whale: $($after -match 'preset-whale')"
Write-Host "剩余行数: $(($after -split "`n").Count)"

if ($after -match 'preset-whale') {
  Write-Host "还有残留，正在回滚…" -ForegroundColor Red
  Copy-Item -LiteralPath $backup -Destination $target -Force
  throw "卸载不完整，已回滚"
}
Write-Host "卸载完成。请重启 DSH。" -ForegroundColor Green
