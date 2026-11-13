# 阿莫比自動上傳：普查更新（11/12 老闆不再手動普查，地城與練功改成也算玩家的小幫手看到的位置）
# 只把新版程式複製到 %USERPROFILE%\阿莫比自動上傳（紀錄、設定、金鑰都不動），下次上傳深度數據就照新規則算
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$dst = Join-Path $env:USERPROFILE '阿莫比自動上傳'
Write-Host '阿莫比自動上傳：普查更新（11/12）' -ForegroundColor Cyan
if (-not (Test-Path (Join-Path $dst 'tools\auto_upload.py'))) {
  Write-Host "找不到 $dst，這台還沒裝過阿莫比自動上傳。" -ForegroundColor Red
  exit 1
}
robocopy (Join-Path $PSScriptRoot 'files') $dst /E /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { Write-Host "複製失敗（robocopy $LASTEXITCODE）" -ForegroundColor Red; exit 1 }
$global:LASTEXITCODE = 0
Write-Host '新版程式已經換好，可以關掉這個視窗。' -ForegroundColor Green
