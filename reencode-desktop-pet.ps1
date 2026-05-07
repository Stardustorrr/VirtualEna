$path = Join-Path $PSScriptRoot 'desktop-pet.ps1'
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$utf8Bom = New-Object System.Text.UTF8Encoding $true
$text = [System.IO.File]::ReadAllText($path, $utf8NoBom)
[System.IO.File]::WriteAllText($path, $text, $utf8Bom)
[scriptblock]::Create((Get-Content $path -Raw -Encoding UTF8)) | Out-Null
Write-Host 'UTF8_BOM_OK'