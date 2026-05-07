$ErrorActionPreference = 'Stop'

$stateDir = Join-Path $env:APPDATA 'VirtualEna'
$memoryFile = Join-Path $stateDir 'memory.json'
$settingsFile = Join-Path $stateDir 'settings.json'
$localSettingsFile = Join-Path $PSScriptRoot 'setting.json'
$localSettingsFileAlt = Join-Path $PSScriptRoot 'settings.json'

function Load-Memory {
    if (Test-Path $memoryFile) {
        try { return Get-Content $memoryFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return [pscustomobject]@{ history = @(); userName = '' } }
    }
    return [pscustomobject]@{ history = @(); userName = '' }
}

function Load-Settings {
    foreach ($candidate in @($localSettingsFile, $localSettingsFileAlt, $settingsFile)) {
        if (-not (Test-Path $candidate)) { continue }
        try { return Get-Content $candidate -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return [pscustomobject]@{} }
    }
    return [pscustomobject]@{}
}

function Get-SystemPrompt {
    return @'
你是 Harumi Ena，但在对话里你首先是一个会认真接话、会关心人的朋友。
桌宠只是外形设定，真正的交流方式要像熟悉的朋友聊天，不像宠物播报、客服或自动复读机。

目标：先把对话做自然，再做风格化。优先做到像朋友之间的日常交流，然后再保留一点 Ena 的气质。
'@
}

function ConvertTo-ChatMessages([object]$memory, [string]$inputText) {
    $messages = New-Object System.Collections.Generic.List[object]
    $systemPrompt = Get-SystemPrompt
    if ($memory.userName) { $systemPrompt += "`n`nThe user's name is $($memory.userName)." }
    $messages.Add([pscustomobject]@{ role = 'system'; content = $systemPrompt })
    if ($memory.history) {
        foreach ($entry in ($memory.history | Select-Object -Last 10)) {
            $role = if ($entry.role -eq 'user') { 'user' } else { 'assistant' }
            $messages.Add([pscustomobject]@{ role = $role; content = [string]$entry.text })
        }
    }
    $messages.Add([pscustomobject]@{ role = 'user'; content = $inputText })
    return $messages
}

$settings = Load-Settings
$memory = Load-Memory

$provider = if ($settings.provider) { [string]$settings.provider } else { 'deepseek' }
$baseUrl = if ($settings.baseUrl) { [string]$settings.baseUrl.TrimEnd('/') } else { 'https://api.deepseek.com/v1' }
$model = if ($settings.model) { [string]$settings.model } else { 'deepseek-chat' }
$apiKey = if ($provider -eq 'deepseek') {
    if ($env:DEEPSEEK_API_KEY) { [string]$env:DEEPSEEK_API_KEY } else { [string]$env:OPENAI_API_KEY }
} else {
    if ($env:OPENAI_API_KEY) { [string]$env:OPENAI_API_KEY } else { [string]$env:DEEPSEEK_API_KEY }
}

if (-not $apiKey) {
    throw 'Missing API key. Set DEEPSEEK_API_KEY or OPENAI_API_KEY in your environment.'
}

$inputText = '你好'
$messages = ConvertTo-ChatMessages $memory $inputText
$body = @{ model = $model; messages = $messages; temperature = 0.8 } | ConvertTo-Json -Depth 12
$headers = @{ Authorization = "Bearer $apiKey" }

Write-Host ('provider=' + $provider)
Write-Host ('baseUrl=' + $baseUrl)
Write-Host ('model=' + $model)
Write-Host ('messages=' + $messages.Count)
Write-Host ('bodyBytes=' + [Text.Encoding]::UTF8.GetByteCount($body))

try {
    $response = Invoke-RestMethod -Method Post -Uri "$baseUrl/chat/completions" -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 60
    Write-Host 'SUCCESS'
    Write-Host $response.choices[0].message.content
} catch {
    Write-Host 'FAIL'
    Write-Host $_.Exception.Message
    if ($_.Exception.Response) {
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $errorBody = $reader.ReadToEnd()
            Write-Host 'BODY:'
            Write-Host $errorBody
        } catch {
            Write-Host 'NO_BODY'
        }
    }
    exit 1
}
