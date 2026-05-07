$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$settingPath = Join-Path $root 'setting.json'

if (-not (Test-Path $settingPath)) {
    throw 'Missing setting.json'
}

$settings = Get-Content $settingPath -Raw -Encoding UTF8 | ConvertFrom-Json
$provider = if ($settings.chatProvider) { [string]$settings.chatProvider } elseif ($settings.provider) { [string]$settings.provider } else { 'deepseek' }
$baseUrl = if ($settings.chatBaseUrl) { [string]$settings.chatBaseUrl.TrimEnd('/') } elseif ($settings.baseUrl) { [string]$settings.baseUrl.TrimEnd('/') } elseif ($provider -eq 'deepseek') { 'https://api.deepseek.com/v1' } else { 'https://api.openai.com/v1' }
$model = if ($settings.chatModel) { [string]$settings.chatModel } elseif ($settings.model) { [string]$settings.model } elseif ($provider -eq 'deepseek') { 'deepseek-chat' } else { 'gpt-4o-mini' }
$apiKey = if ($provider -eq 'deepseek') {
    [string]$env:DEEPSEEK_API_KEY
} else {
    [string]$env:OPENAI_API_KEY
}

if (-not $apiKey) {
    throw "Missing API key for provider '$provider'."
}

$body = @{
    model = $model
    messages = @(
        @{ role = 'system'; content = 'You are a friendly assistant.' },
        @{ role = 'user'; content = 'Say pong only.' }
    )
    temperature = 0.2
} | ConvertTo-Json -Depth 8

$headers = @{ Authorization = "Bearer $apiKey" }

try {
    $response = Invoke-RestMethod -Method Post -Uri "$baseUrl/chat/completions" -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 60
    $content = $response.choices[0].message.content
    Write-Host 'SUCCESS'
    Write-Host ($content.Trim())
} catch {
    Write-Host 'FAIL'
    if ($_.Exception.Response) {
        $resp = $_.Exception.Response
        Write-Host ("HTTP_STATUS: {0}" -f [int]$resp.StatusCode)
        try {
            $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
            $errorBody = $reader.ReadToEnd()
            Write-Host $errorBody
        } catch {
            Write-Host $_.Exception.Message
        }
    } else {
        Write-Host $_.Exception.Message
    }
    exit 1
}
