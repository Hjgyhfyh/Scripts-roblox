' Скрытый запуск watcher-скрипта авто-синхронизации
Set sh = CreateObject("WScript.Shell")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""D:\Нужное\Скрипты роблокс\_github_sync\_sync\watch-sync.ps1"""
sh.Run cmd, 0, False
