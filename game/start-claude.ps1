# Скрипт для запуска Claude Code с проектом Godot
# Автоматически устанавливает правильную рабочую директорию

Write-Host "Запуск Claude Code для проекта Godot..." -ForegroundColor Cyan
Write-Host "Рабочая директория: C:\Games\игра" -ForegroundColor Gray
Write-Host ""

# Переходим в директорию проекта
Set-Location "C:\Games\игра"

# Запускаем Claude
claude

# Если Claude закрылся, показываем сообщение
Write-Host ""
Write-Host "Claude Code завершён." -ForegroundColor Green
