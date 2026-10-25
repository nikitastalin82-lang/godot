param(
    [string]$ZipPath = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $projectRoot "Ресурсы\Анимации\UAL1_Standard.glb"

if ([string]::IsNullOrWhiteSpace($ZipPath)) {
    $candidates = @(
        (Join-Path $env:USERPROFILE "Desktop\Universal Animation Library[Standard].zip"),
        (Join-Path $env:USERPROFILE "Downloads\Universal Animation Library[Standard].zip"),
        (Join-Path $env:USERPROFILE "Desktop\Universal Animation Library [Standard].zip"),
        (Join-Path $env:USERPROFILE "Downloads\Universal Animation Library [Standard].zip")
    )
    $ZipPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

if ([string]::IsNullOrWhiteSpace($ZipPath) -or !(Test-Path -LiteralPath $ZipPath)) {
    throw "Не найден ZIP. Запусти скрипт с параметром -ZipPath 'полный_путь_к_архиву'."
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
try {
    $entry = $archive.Entries | Where-Object { $_.FullName -match '(^|/)UAL1_Standard\.glb$' } | Select-Object -First 1
    if ($null -eq $entry) {
        throw "В архиве не найден UAL1_Standard.glb."
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    $input = $entry.Open()
    try {
        $output = [System.IO.File]::Create($destination)
        try { $input.CopyTo($output) } finally { $output.Dispose() }
    } finally { $input.Dispose() }
}
finally {
    $archive.Dispose()
}

Write-Host "Готово: $destination"
Write-Host "Теперь открой проект в Godot и запусти сцену satoko_animation_check.tscn."
