# 阿莫比自動上傳：另一台電腦的安裝（安裝自動上傳.bat 會跑這支；tools/build_auto_upload_kit.py 產生）
param([string]$Target = (Join-Path $env:USERPROFILE '阿莫比自動上傳'), [string]$Game = '', [switch]$Yes, [switch]$SkipTask)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$src = Split-Path -Parent $PSScriptRoot

Write-Host '阿莫比自動上傳：安裝到這台電腦' -ForegroundColor Cyan
Write-Host ''
if (-not (Test-Path (Join-Path $src 'tools\auto_upload.py'))) {
  Write-Host '找不到程式檔：請先把整個「阿莫比自動上傳」資料夾複製（或解壓縮）出來，再雙擊裡面的 安裝自動上傳.bat。' -ForegroundColor Red
  exit 1
}

function Ask([string]$q) {
  if ($Yes) { return $true }
  $a = Read-Host "$q [Y/n]"
  return ($a -eq '' -or $a -match '^[yY]')
}

# 1. 複製到固定的位置（隨身碟拔掉也能跑；原本的 資料\ 紀錄、設定都保留）
$full = [IO.Path]::GetFullPath($Target).TrimEnd('\')
if ((Resolve-Path $src).Path.TrimEnd('\') -ne $full) {
  New-Item -ItemType Directory -Force $full | Out-Null
  robocopy $src $full /E /XD (Join-Path $src '資料') /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { Write-Host "複製到 $full 失敗（robocopy $LASTEXITCODE）" -ForegroundColor Red; exit 1 }
  $global:LASTEXITCODE = 0
  Write-Host "程式放在：$full"
}

# 2. Python 3.9 以上（排程用它的 pythonw 跑，看不到視窗）
function Find-Python {
  $c = @()
  foreach ($cmd in @('py -3', 'python')) {
    try {
      $parts = $cmd -split ' '; $exe = $parts[0]; $pre = @($parts | Select-Object -Skip 1)
      $p = & $exe @pre -c "import sys;print(sys.executable if sys.version_info>=(3,9) else '')" 2>$null
      if ($LASTEXITCODE -eq 0 -and $p) { $c += "$p".Trim() }
    } catch {}
  }
  $c += @(Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe", 'C:\Python3*\python.exe', "$env:ProgramFiles\Python3*\python.exe" -ErrorAction SilentlyContinue |
          Sort-Object FullName -Descending | ForEach-Object { $_.FullName })
  foreach ($x in $c) { if ($x -and (Test-Path $x) -and (Test-Path (Join-Path (Split-Path $x) 'pythonw.exe'))) { return $x } }
  return $null
}
function Find-Node {
  $c = @()
  $n = Get-Command node -ErrorAction SilentlyContinue
  if ($n) { $c += $n.Source }
  $c += @("$env:ProgramFiles\nodejs\node.exe", "${env:ProgramFiles(x86)}\nodejs\node.exe", "$env:LOCALAPPDATA\Programs\nodejs\node.exe")
  foreach ($x in $c) {
    if ($x -and (Test-Path $x)) {
      try { & $x -e "process.exit(+process.versions.node.split('.')[0]>=18?0:1)" 2>$null; if ($LASTEXITCODE -eq 0) { return $x } } catch {}
    }
  }
  return $null
}
function Install-With-Winget([string]$id, [string]$name, [string]$url) {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "這台電腦沒有 winget：請到 $url 下載安裝 $name，裝好再雙擊一次 安裝自動上傳.bat。" -ForegroundColor Yellow
    exit 1
  }
  Write-Host "用 winget 安裝 $name（第一次用 winget 會問你同不同意使用條款，請輸入 Y）…"
  if ($id -like 'Python*') { winget install -e --id $id --scope user } else { winget install -e --id $id }
}

$py = Find-Python
if (-not $py) {
  if (Ask '這台電腦沒有 Python（3.9 以上）。要用 Windows 內建的 winget 從微軟的套件庫安裝 Python 3.13 嗎？') {
    Install-With-Winget 'Python.Python.3.13' 'Python' 'https://www.python.org/downloads/（安裝時勾選 Add python.exe to PATH）'
    $py = Find-Python
  }
  if (-not $py) { Write-Host '沒有 Python 沒辦法設定。裝好 Python 之後再雙擊一次 安裝自動上傳.bat。' -ForegroundColor Red; exit 1 }
}
Write-Host "Python：$py"

$node = Find-Node
if (-not $node) {
  if (Ask '這台電腦沒有 Node.js（18 以上，上傳用）。要用 winget 安裝 Node.js LTS 嗎？（會跳出系統管理員的確認視窗，請按「是」）') {
    Install-With-Winget 'OpenJS.NodeJS.LTS' 'Node.js' 'https://nodejs.org/（選 LTS）'
    $node = Find-Node
  }
  if (-not $node) { Write-Host '沒有 Node.js 沒辦法上傳。裝好 Node.js 之後再雙擊一次 安裝自動上傳.bat。' -ForegroundColor Red; exit 1 }
}
Write-Host "Node.js：$node"
Write-Host ''

# 3. 剩下的交給 auto_upload.py --setup（遊戲資料夾、插件、金鑰、排程、試跑）
$env:Path = (Split-Path $node) + ';' + $env:Path
$a = @((Join-Path $full 'tools\auto_upload.py'), '--setup')
if ($Game) { $a += "--game=$Game" }
if ($Yes) { $a += '--yes' }
if ($SkipTask) { $a += '--skip-task' }
Push-Location $full
& $py @a
$rc = $LASTEXITCODE
Pop-Location
Write-Host ''
if ($rc -eq 0) {
  Write-Host '完成！隨身碟上的這個資料夾可以刪掉了（裡面有上傳金鑰，不要傳給別人）。' -ForegroundColor Green
  Write-Host "要移除：雙擊 $full\移除自動上傳.bat"
} else {
  Write-Host '設定沒有完成，請把這個視窗截圖給阿莫比。' -ForegroundColor Red
}
exit $rc
