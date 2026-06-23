# Авто-синхронизация папки "Скрипты" -> GitHub (Hjgyhfyh/Scripts-roblox)
# Синхронный watcher: ждёт изменение, дебаунсит, делает commit+push.

$ErrorActionPreference = 'Continue'
$Source = 'D:\Нужное\Скрипты роблокс\Делаем скрипты тут\Скрипты'
$Mirror = 'D:\Нужное\Скрипты роблокс\_github_sync'
$LogFile = Join-Path $Mirror '_sync\sync.log'
$DebounceMs = 2500

$singleton = New-Object System.Threading.Mutex($false, 'RobloxScriptsAutoSyncWatcher')
if (-not $singleton.WaitOne(0)) { exit }

function Write-Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg"
    Add-Content -Path $LogFile -Value $line -Encoding utf8
}

function Invoke-Sync {
    try {
        robocopy $Source $Mirror /MIR /XD "$Mirror\.git" "$Mirror\_sync" /NFL /NDL /NJH /NJS /NP | Out-Null
        Push-Location $Mirror
        git add -A 2>&1 | Out-Null
        $changes = git status --porcelain
        if ([string]::IsNullOrWhiteSpace($changes)) { Pop-Location; return }
        git commit -m "auto-sync: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 2>&1 | Out-Null
        git push origin main 2>&1 | Out-Null
        $code = $LASTEXITCODE
        Pop-Location
        if ($code -eq 0) { Write-Log "pushed changes" } else { Write-Log "push failed (exit $code)" }
    } catch {
        Write-Log "ERROR: $_"
        while ((Get-Location).Path -eq $Mirror) { Pop-Location }
    }
}

Write-Log "watcher started"
Invoke-Sync  # стартовая синхронизация

$fsw = New-Object System.IO.FileSystemWatcher
$fsw.Path = $Source
$fsw.IncludeSubdirectories = $true
$fsw.NotifyFilter = [System.IO.NotifyFilters]'FileName, DirectoryName, LastWrite, Size'

while ($true) {
    $r = $fsw.WaitForChanged([System.IO.WatcherChangeTypes]::All, 60000)
    if ($r.TimedOut) { continue }
    # дебаунс: ждём пока изменения утихнут
    Start-Sleep -Milliseconds $DebounceMs
    while (-not ($fsw.WaitForChanged([System.IO.WatcherChangeTypes]::All, $DebounceMs)).TimedOut) { }
    Invoke-Sync
}
