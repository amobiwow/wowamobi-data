# 阿莫比自動上傳：刪掉這台電腦的排程（程式、紀錄、存檔都不動）
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
try {
  Unregister-ScheduledTask -TaskName '阿莫比自動上傳' -Confirm:$false -ErrorAction Stop
  Write-Host '已經刪掉排程「阿莫比自動上傳」，之後不會再自動上傳。（程式和紀錄還在，要的話可以整個資料夾刪掉）' -ForegroundColor Green
} catch {
  Write-Host '這台電腦沒有排程「阿莫比自動上傳」（可能已經刪過了）。'
}
