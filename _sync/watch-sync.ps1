# Авто-синхронизация папки "Скрипты" -> GitHub (Hjgyhfyh/Scripts-roblox)
# Следит за изменениями и делает commit+push (с дебаунсом).

$ErrorActionPreference = 'Stop'
$Source = 'D:\Нужное\Скрипты роблокс\Делаем скрипты тут\Скрипты'
$Mirror = 'D:\Нужное\Скрипты роблокс\_github_sync'
$LogFile = Join-Path $Mirror '_sync\sync.log'
$DebounceMs = 3000

function Write-Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg"
    Add-Content -Path $LogFile -Value $line -Encoding utf8
}

function Invoke-Sync {
    try {
        # Зеркалим Скрипты -> корень клона, не трогая .git и служебную папку _sync
        robocopy $Source $Mirror /MIR /XD "$Mirror\.git" "$Mirror\_sync" /NFL /NDL /NJH /NJS /NP | Out-Null
        Push-Location $Mirror
        git add -A | Out-Null
        $changes = git status --porcelain
        if ([string]::IsNullOrWhiteSpace($changes)) {
            Pop-Location
            return
        }
        git commit -m "auto-sync: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-Null
        git push origin main 2>&1 | Out-Null
        Pop-Location
        Write-Log "pushed changes"
    } catch {
        Write-Log "ERROR: $_"
        if ((Get-Location).Path -eq $Mirror) { Pop-Location }
    }
}

Write-Log "watcher started"

# Стартовая синхронизация на случай изменений во время простоя
Invoke-Sync

$fsw = New-Object System.IO.FileSystemWatcher
$fsw.Path = $Source
$fsw.IncludeSubdirectories = $true
$fsw.NotifyFilter = [System.IO.NotifyFilters]'FileName, DirectoryName, LastWrite, Size'
$fsw.EnableRaisingEvents = $true

# Глобальный таймер-дебаунс
$global:pending = $false
$timer = New-Object System.Timers.Timer
$timer.Interval = $DebounceMs
$timer.AutoReset = $false

$onChange = {
    if (-not $global:pending) {
        $global:pending = $true
        $timer.Stop(); $timer.Start()
    } else {
        $timer.Stop(); $timer.Start()
    }
}

Register-ObjectEvent $fsw Changed -Action $onChange | Out-Null
Register-ObjectEvent $fsw Created -Action $onChange | Out-Null
Register-ObjectEvent $fsw Deleted -Action $onChange | Out-Null
Register-ObjectEvent $fsw Renamed -Action $onChange | Out-Null
Register-ObjectEvent $timer Elapsed -Action {
    $global:pending = $false
    Invoke-Sync
} | Out-Null

# Держим процесс живым
while ($true) { Start-Sleep -Seconds 3600 }
