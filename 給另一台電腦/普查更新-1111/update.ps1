# 阿莫比自動上傳：普查更新（11/11 兩隻收資料的角色都在這台）
# 1. 換成新版自動上傳程式（紀錄、設定、金鑰都不動）：一個陣營會蓋掉網站上另一台傳的資料時，只擋那個陣營，另一個陣營照傳
# 2. 讓普查重新檢查一次（23:33 那次整段被擋，存檔沒變就不會再看），馬上跑一次自動上傳
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$env:PYTHONIOENCODING = 'utf-8'
$dst = Join-Path $env:USERPROFILE '阿莫比自動上傳'
Write-Host '阿莫比自動上傳：普查更新（11/11）' -ForegroundColor Cyan
if (-not (Test-Path (Join-Path $dst 'tools\auto_upload.py'))) {
  Write-Host "找不到 $dst，這台還沒裝過阿莫比自動上傳。" -ForegroundColor Red
  exit 1
}
robocopy (Join-Path $PSScriptRoot 'files') $dst /E /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { Write-Host "複製失敗（robocopy $LASTEXITCODE）" -ForegroundColor Red; exit 1 }
$global:LASTEXITCODE = 0
Write-Host '1. 新版程式已經換好。' -ForegroundColor Green
Set-Location $dst
& python -c "import sys; sys.path.insert(0, 'tools'); import auto_upload as a; s = a.load_state(); c = s.get('census', {}); c.pop('hash', None); c.pop('stat', None); a.save_state(s)"
if ($LASTEXITCODE -ne 0) { Write-Host '重設普查狀態失敗（新程式已經換好，下次存檔有變就會照新規則傳）。' -ForegroundColor Yellow; exit 1 }
Write-Host '2. 普查會重新檢查一次，現在跑一次自動上傳……'
& python (Join-Path $dst 'tools\auto_upload.py')
Write-Host ''
Write-Host '紀錄最後 25 行：'
Get-Content (Join-Path $dst '資料\自動上傳\紀錄.txt') -Encoding UTF8 -Tail 25
Write-Host ''
Write-Host '完成，可以關掉這個視窗。' -ForegroundColor Green
