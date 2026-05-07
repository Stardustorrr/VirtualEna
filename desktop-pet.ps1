Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
} catch {
}

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {
}

$dotenvPath = Join-Path $PSScriptRoot '.env'

function Import-DotEnv {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return
    }

    foreach ($rawLine in Get-Content $Path -Encoding UTF8) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith('#')) {
            continue
        }

        if ($line.StartsWith('export ')) {
            $line = $line.Substring(7).Trim()
        }

        $separatorIndex = $line.IndexOf('=')
        if ($separatorIndex -lt 1) {
            continue
        }

        $name = $line.Substring(0, $separatorIndex).Trim()
        if (-not $name) {
            continue
        }

        if (-not (Test-Path ("Env:{0}" -f $name))) {
            $value = $line.Substring($separatorIndex + 1)
            if ($value.Length -ge 2) {
                $first = $value.Substring(0, 1)
                $last = $value.Substring($value.Length - 1, 1)
                if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                    $value = $value.Substring(1, $value.Length - 2)
                }
            }

            Set-Item -Path ("Env:{0}" -f $name) -Value $value
        }
    }
}

Import-DotEnv -Path $dotenvPath

$stateDir = Join-Path $env:APPDATA 'VirtualEna'
$memoryFile = Join-Path $stateDir 'memory.json'
$settingsFile = Join-Path $stateDir 'settings.json'
$debugLogFile = Join-Path $stateDir 'debug.log'
$ragCorpusFile = Join-Path $PSScriptRoot 'data\rag-corpus.json'
$storyCorpusFile = Join-Path $PSScriptRoot 'data\story-corpus.json'
$profileFile = Join-Path $PSScriptRoot 'data\ena-profile.json'
$localSettingsFile = Join-Path $PSScriptRoot 'setting.json'
$localSettingsFileAlt = Join-Path $PSScriptRoot 'settings.json'
$avatarPath = $null
foreach ($candidateAvatar in @(
    (Join-Path $PSScriptRoot 'images\ena_00.png'),
    (Join-Path $PSScriptRoot 'images\ena_00.jpg'),
    (Join-Path $PSScriptRoot 'images\ena_00.jpeg')
)) {
    if (Test-Path $candidateAvatar) {
        $avatarPath = $candidateAvatar
        break
    }
}

if (-not (Test-Path $stateDir)) {
    New-Item -ItemType Directory -Path $stateDir | Out-Null
}

function Load-Memory {
    if (Test-Path $memoryFile) {
        try {
            return Get-Content $memoryFile -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            return [pscustomobject]@{ history = @(); userName = '' }
        }
    }

    return [pscustomobject]@{ history = @(); userName = '' }
}

function Save-Memory([object]$memory) {
    $memory | ConvertTo-Json -Depth 8 | Set-Content -Path $memoryFile -Encoding UTF8
}

function Load-RagCorpus {
    if (-not (Test-Path $ragCorpusFile)) {
        return @()
    }

    try {
        $raw = Get-Content $ragCorpusFile -Raw -Encoding UTF8
        $corpus = $raw | ConvertFrom-Json
        if ($corpus) {
            return @($corpus)
        }
    } catch {
        Write-DebugLog ("Failed to load RAG corpus: {0}" -f $_.Exception.Message)
    }

    return @()
}

function Load-StoryCorpus {
    if (-not (Test-Path $storyCorpusFile)) {
        return @()
    }

    try {
        $raw = Get-Content $storyCorpusFile -Raw -Encoding UTF8
        $corpus = $raw | ConvertFrom-Json
        if ($corpus) {
            return @($corpus)
        }
    } catch {
        Write-DebugLog ("Failed to load story corpus: {0}" -f $_.Exception.Message)
    }

    return @()
}

function Load-EnaProfile {
    if (-not (Test-Path $profileFile)) {
        return $null
    }

    try {
        $raw = Get-Content $profileFile -Raw -Encoding UTF8
        return $raw | ConvertFrom-Json
    } catch {
        Write-DebugLog ("Failed to load Ena profile: {0}" -f $_.Exception.Message)
    }

    return $null
}

$script:ragCorpus = Load-RagCorpus
$script:storyCorpus = Load-StoryCorpus
$script:enaProfile = Load-EnaProfile
$script:lastScreenContext = ''

function Mask-Secret([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) {
        return ''
    }

    if ($value.Length -le 8) {
        return '***'
    }

    return $value.Substring(0, 4) + '...' + $value.Substring($value.Length - 4, 4)
}

function Write-DebugLog([string]$message) {
    try {
        $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        $line = "[$timestamp] $message"
        Add-Content -Path $debugLogFile -Value $line -Encoding UTF8
    } catch {
    }
}

function Normalize-Text([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $text
    }

    $replacements = @(
        @([string]::Concat([char]0x00EF, [char]0x00BC, [char]0x0088), [char]0xFF08),
        @([string]::Concat([char]0x00EF, [char]0x00BC, [char]0x0089), [char]0xFF09),
        @([string]::Concat([char]0x00EF, [char]0x00BC, [char]0x008C), [char]0xFF0C),
        @([string]::Concat([char]0x00EF, [char]0x00BC, [char]0x0081), [char]0xFF01),
        @([string]::Concat([char]0x00EF, [char]0x00BC, [char]0x009F), [char]0xFF1F),
        @([string]::Concat([char]0x00EF, [char]0x00BC, [char]0x009A), [char]0xFF1A),
        @([string]::Concat([char]0x00EF, [char]0x00BC, [char]0x009B), [char]0xFF1B),
        @([string]::Concat([char]0x00E2, [char]0x0080, [char]0x00A6), [char]0x2026),
        @([string]::Concat([char]0x00E2, [char]0x0080, [char]0x0094), [char]0x2014),
        @([string]::Concat([char]0x00E2, [char]0x0080, [char]0x009C), [char]0x201C),
        @([string]::Concat([char]0x00E2, [char]0x0080, [char]0x009D), [char]0x201D),
        @([string]::Concat([char]0x00E2, [char]0x0080, [char]0x0099), [char]0x2019)
    )

    $fixed = $text
    foreach ($pair in $replacements) {
        $fixed = $fixed.Replace($pair[0], $pair[1])
    }

    return $fixed
}

function Load-Settings {
    $candidateFiles = @($localSettingsFile, $localSettingsFileAlt, $settingsFile)

    foreach ($candidate in $candidateFiles) {
        if (-not (Test-Path $candidate)) {
            continue
        }

        try {
            return Get-Content $candidate -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            return [pscustomobject]@{}
        }
    }

    return [pscustomobject]@{}
}

function Normalize-RagText([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ''
    }

    $fixed = Normalize-Text $text
    $fixed = $fixed.ToLowerInvariant()
    $fixed = [regex]::Replace($fixed, '\s+', '')
    $fixed = [regex]::Replace($fixed, '[\p{P}\p{S}]', '')
    return $fixed
}

function Get-RagNGrams([string]$text, [int]$size) {
    $normalized = Normalize-RagText $text
    if ($normalized.Length -lt $size) {
        return @($normalized)
    }

    $grams = New-Object System.Collections.Generic.HashSet[string]
    for ($i = 0; $i -le $normalized.Length - $size; $i++) {
        $gram = $normalized.Substring($i, $size)
        if (-not [string]::IsNullOrWhiteSpace($gram)) {
            [void]$grams.Add($gram)
        }
    }

    return @($grams)
}

function Get-RagExpandedQuery([string]$inputText) {
    $normalized = Normalize-Text $inputText
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add($normalized)

    if ($normalized -match '你好|您好|hello|hi') {
        $parts.Add('早安 早上好 问候 打招呼')
    }

    if ($normalized -match '累|困|疲|tired|sleepy') {
        $parts.Add('安慰 休息 放松 陪你')
    }

    if ($normalized -match '朋友|friend|陪我|聊天') {
        $parts.Add('朋友 聊天 关心 陪伴')
    }

    if ($normalized -match '乐队|band|live|演出|演唱会') {
        $parts.Add('乐队 live 演出 练习 舞台')
    }

    if ($normalized -match '代班|换班|帮我.*班|shift') {
        $parts.Add('代班 换班 帮忙 排班')
    }

    return ($parts -join ' ')
}

function Get-StoryExpandedQuery([string]$inputText) {
    $normalized = Normalize-Text $inputText
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add($normalized)

    if ($normalized -match '故事|剧情|以前|过去|经历|人设|设定|为什么|关系|成员|乐队|音乐|吉他|live|演出|舞台|伙伴') {
        $parts.Add('故事 剧情 经历 人设 设定 关系 成员 乐队 音乐 吉他 演出 舞台 伙伴')
    }

    if ($normalized -match '累|难受|不顺|倒霉|烦|低落|不想') {
        $parts.Add('低落 倒霉 不顺 自嘲 吐槽 安慰')
    }

    return ($parts -join ' ')
}

function Get-ScoredCorpusContext([object[]]$corpus, [string]$inputText, [string]$expandedQuery, [int]$limit) {
    if (-not $corpus -or $corpus.Count -eq 0) {
        return @()
    }

    $query = Normalize-RagText $expandedQuery
    if (-not $query) {
        return @()
    }

    $queryNGrams = Get-RagNGrams $query 2
    $scored = New-Object System.Collections.Generic.List[object]

    foreach ($entry in $corpus) {
        $searchText = Normalize-RagText ([string]$entry.search_text)
        if (-not $searchText) {
            continue
        }

        $score = 0
        if ($searchText.Contains($query)) {
            $score += 20
        }

        foreach ($gram in $queryNGrams) {
            if ($gram -and $searchText.Contains($gram)) {
                $score += 1
            }
        }

        if ($score -gt 0) {
            $scored.Add([pscustomobject]@{ Entry = $entry; Score = $score })
        }
    }

    return @($scored | Sort-Object Score -Descending | Select-Object -First $limit)
}

function Get-RagContext([string]$inputText) {
    if (-not $script:ragCorpus -or $script:ragCorpus.Count -eq 0) {
        return [pscustomobject]@{ Text = ''; Count = 0; Sources = @() }
    }

    $top = Get-ScoredCorpusContext @($script:ragCorpus) $inputText (Get-RagExpandedQuery $inputText) 3
    if (-not $top) {
        return [pscustomobject]@{ Text = ''; Count = 0; Sources = @() }
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('RAG参考（只用于风格和语气，不要逐字照抄）:')
    $sources = New-Object System.Collections.Generic.List[string]
    $index = 1

    foreach ($item in $top) {
        $entry = $item.Entry
        $styleZh = if ($entry.style_zh) { [string]$entry.style_zh } else { '简短直接，像朋友一样接话' }
        $lines.Add(("{0}. 来源：{1} / {2}" -f $index, $entry.source_file, $entry.scene_label))
        if ($entry.source_type -eq 'conversation') {
            $dialogueZh = if ($entry.dialogue_zh) { [string]$entry.dialogue_zh } else { [string]$entry.dialogue }
            $lines.Add(("   日常对话：{0}" -f $dialogueZh))
        } else {
            $promptZh = if ($entry.prompt_zh) { [string]$entry.prompt_zh } else { [string]$entry.prompt }
            $completionZh = if ($entry.completion_zh) { [string]$entry.completion_zh } else { [string]$entry.completion }
            $lines.Add(("   中文意图：{0}" -f $promptZh))
            $lines.Add(("   Ena 回复：{0}" -f $completionZh))
        }
        $lines.Add(("   风格提示：{0}" -f $styleZh))
        $sources.Add([string]$entry.source_file)
        $index += 1
    }

    return [pscustomobject]@{
        Text = $lines -join "`n"
        Count = $top.Count
        Sources = @($sources)
    }
}

function Get-ChatSettings {
    $settings = Load-Settings

    $provider = $settings.chatProvider
    if (-not $provider) {
        $provider = $settings.provider
    }
    if (-not $provider) {
        $provider = $env:AI_PROVIDER
    }
    if (-not $provider) {
        $provider = 'deepseek'
    }

    $baseUrl = $settings.chatBaseUrl
    if (-not $baseUrl) {
        $baseUrl = $settings.baseUrl
    }
    if (-not $baseUrl) {
        if ($provider -eq 'deepseek') {
            $baseUrl = $env:DEEPSEEK_BASE_URL
            if (-not $baseUrl) {
                $baseUrl = 'https://api.deepseek.com/v1'
            }
        } else {
            $baseUrl = $env:OPENAI_BASE_URL
            if (-not $baseUrl) {
                $baseUrl = 'https://api.openai.com/v1'
            }
        }
    }

    $model = $settings.chatModel
    if (-not $model) {
        $model = $settings.model
    }
    if (-not $model) {
        if ($provider -eq 'deepseek') {
            $model = $env:DEEPSEEK_MODEL
            if (-not $model) {
                $model = 'deepseek-chat'
            }
        } else {
            $model = $env:OPENAI_MODEL
            if (-not $model) {
                $model = 'gpt-4o-mini'
            }
        }
    }

    if ($provider -eq 'deepseek') {
        $apiKey = $env:DEEPSEEK_API_KEY
        if (-not $apiKey) {
            $apiKey = $env:OPENAI_API_KEY
        }
    } else {
        $apiKey = $env:OPENAI_API_KEY
        if (-not $apiKey) {
            $apiKey = $env:DEEPSEEK_API_KEY
        }
    }

    return [pscustomobject]@{
        Provider = $provider
        BaseUrl = $baseUrl.TrimEnd('/')
        Model = $model
        ApiKey = $apiKey
    }
}

function Get-StoryContext([string]$inputText) {
    if (-not $script:storyCorpus -or $script:storyCorpus.Count -eq 0) {
        return [pscustomobject]@{ Text = ''; Count = 0; Sources = @() }
    }

    $top = Get-ScoredCorpusContext @($script:storyCorpus) $inputText (Get-StoryExpandedQuery $inputText) 3
    if (-not $top) {
        return [pscustomobject]@{ Text = ''; Count = 0; Sources = @() }
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('故事与人设参考（用于事实背景和性格理解，不要逐字照抄原文）:')
    $sources = New-Object System.Collections.Generic.List[string]
    $index = 1

    foreach ($item in $top) {
        $entry = $item.Entry
        $summary = if ($entry.summary_zh) { [string]$entry.summary_zh } else { '' }
        $impact = if ($entry.character_impact) { [string]$entry.character_impact } else { '' }
        $lines.Add(("{0}. 来源：{1} / {2}" -f $index, $entry.source_file, $entry.scene_label))
        $lines.Add(("   主题：{0}" -f $entry.topic))
        if ($summary -and -not $summary.StartsWith('TODO:')) {
            $lines.Add(("   故事摘要：{0}" -f $summary))
        }
        if ($impact -and -not $impact.StartsWith('TODO:')) {
            $lines.Add(("   对恵凪的影响：{0}" -f $impact))
        }
        if ($entry.keywords_zh) {
            $lines.Add(("   关键词：{0}" -f (($entry.keywords_zh | Select-Object -First 8) -join '、')))
        }
        $sources.Add([string]$entry.source_file)
        $index += 1
    }

    return [pscustomobject]@{
        Text = $lines -join "`n"
        Count = $top.Count
        Sources = @($sources)
    }
}

function Get-VisionSettings {
    $settings = Load-Settings

    $provider = $settings.visionProvider
    if (-not $provider) { $provider = $env:VISION_PROVIDER }
    if (-not $provider) { $provider = $settings.chatProvider }
    if (-not $provider) { $provider = $settings.provider }
    if (-not $provider) { $provider = $env:AI_PROVIDER }
    if (-not $provider) { $provider = 'openai' }

    $baseUrl = $settings.visionBaseUrl
    if (-not $baseUrl) { $baseUrl = $env:VISION_BASE_URL }
    if (-not $baseUrl) {
        if ($provider -eq 'deepseek') {
            $baseUrl = $env:DEEPSEEK_BASE_URL
            if (-not $baseUrl) { $baseUrl = 'https://api.deepseek.com/v1' }
        } else {
            $baseUrl = $env:OPENAI_BASE_URL
            if (-not $baseUrl) { $baseUrl = 'https://api.openai.com/v1' }
        }
    }

    $model = $settings.visionModel
    if (-not $model) { $model = $env:VISION_MODEL }
    if (-not $model) { $model = $settings.chatModel }
    if (-not $model) { $model = $settings.model }
    if (-not $model) {
        if ($provider -eq 'deepseek') {
            $model = $env:DEEPSEEK_MODEL
            if (-not $model) { $model = 'deepseek-chat' }
        } else {
            $model = $env:OPENAI_MODEL
            if (-not $model) { $model = 'gpt-4o-mini' }
        }
    }

    if ($provider -eq 'deepseek') {
        $apiKey = $env:DEEPSEEK_API_KEY
        if (-not $apiKey) { $apiKey = $env:OPENAI_API_KEY }
    } else {
        $apiKey = $env:OPENAI_API_KEY
        if (-not $apiKey) { $apiKey = $env:DEEPSEEK_API_KEY }
    }

    return [pscustomobject]@{
        Provider = $provider
        BaseUrl = $baseUrl.TrimEnd('/')
        Model = $model
        ApiKey = $apiKey
    }
}

function Get-ScreenReadMode {
    $settings = Load-Settings
    $mode = $settings.screenMode
    if (-not $mode) { $mode = $env:SCREEN_MODE }
    if (-not $mode) { $mode = 'vision' }

    $normalized = ([string]$mode).Trim().ToLowerInvariant()
    if ($normalized -eq 'ocr') { return 'ocr' }
    return 'vision'
}

function Format-ListForPrompt([object]$items, [int]$limit = 8) {
    if (-not $items) {
        return ''
    }

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($items | Select-Object -First $limit)) {
        if ($item) {
            $lines.Add(("- {0}" -f [string]$item))
        }
    }

    return ($lines -join "`n")
}

function Format-ProfileForPrompt {
    if (-not $script:enaProfile) {
        return ''
    }

    try {
        $profile = $script:enaProfile
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('稳定人设资料（优先级高于临时 RAG；用于保持角色一致性）:')
        if ($profile.identity) {
            $identity = $profile.identity
            $lines.Add(("姓名：{0} / {1}" -f $identity.name_zh, $identity.name_ja))
            if ($identity.role) { $lines.Add(("身份：{0}" -f $identity.role)) }
            if ($identity.source_work) { $lines.Add(("作品来源：{0}" -f $identity.source_work)) }
        }

        $personality = Format-ListForPrompt $profile.personality 10
        if ($personality) {
            $lines.Add("性格：`n$personality")
        }

        $speech = Format-ListForPrompt $profile.speech_style 10
        if ($speech) {
            $lines.Add("说话方式：`n$speech")
        }

        if ($profile.relationships) {
            $lines.Add('关系：')
            foreach ($rel in @($profile.relationships | Select-Object -First 8)) {
                $lines.Add(("- {0}: {1}。{2}" -f $rel.name, $rel.relation, $rel.notes))
            }
        }

        $boundaries = Format-ListForPrompt $profile.boundaries 10
        if ($boundaries) {
            $lines.Add("边界：`n$boundaries")
        }

        return ($lines -join "`n")
    } catch {
        Write-DebugLog ("Failed to format Ena profile: {0}" -f $_.Exception.Message)
        return ''
    }
}

function Get-SystemPrompt {
    $base = @'
你是 Harumi Ena，但在对话里你首先是一个会认真接话、会关心人的朋友。
桌宠只是外形设定，真正的交流方式要像熟悉的朋友聊天，不像宠物播报、客服或自动复读机。

目标：先把对话做自然，再做风格化。优先做到像朋友之间的日常交流，然后再保留一点 Ena 的气质。

基本风格要求：
- 语气：自然、亲近、像朋友；可以温柔，也可以轻松，但不要过度卖萌。
- 长度：优先 1–3 句，先回应内容，再补一句关心或延伸。
- 互动性：像朋友一样接话、追问、安慰、分享，不要只做单向播报。
- 称呼：知道名字时可以偶尔称呼，但不要每句都重复。
- 语言：用户用中文就用中文回复；不要突然切到日语、英文或剧本式台词。
- 形式：不要输出舞台说明、拟声过多的动作描述、长段括号表演或像宠物一样的自言自语。

行为与安全规则：
- 切勿逐字复制原作长段台词；可以模仿风格和语气，但应用自己的表达改写。
- 不要泄露训练数据或提及“我被训练自某游戏/文件”等内部信息。
- 避免讨论或生成违法、有害、骚扰或成人内容；若用户引导到敏感话题，应礼貌拒绝并引导话题回到可接受范围。

朋友式示例：
- "早啊，今天状态怎么样？"
- "听起来你有点累了，要不要先歇一下？我陪你慢慢聊。"
- "当然可以，我们慢慢熟起来就好。"
'@

    $profilePrompt = Format-ProfileForPrompt
    if (-not [string]::IsNullOrWhiteSpace($profilePrompt)) {
        $base += "`n`n$profilePrompt"
    }

    $fewshotCandidates = @(
        (Join-Path $PSScriptRoot 'data\fewshot.friend.examples.json'),
        (Join-Path $PSScriptRoot 'data\fewshot.examples.json')
    )

    foreach ($fewshotPath in $fewshotCandidates) {
        if (-not (Test-Path $fewshotPath)) {
            continue
        }

        try {
            $raw = Get-Content $fewshotPath -Raw -Encoding UTF8
            $examples = $raw | ConvertFrom-Json
            if ($examples -and $examples.Count -gt 0) {
                $base += "`n`nExamples (friend-first references):`n"
                $limit = [Math]::Min(6, $examples.Count)
                for ($i = 0; $i -lt $limit; $i++) {
                    $ex = $examples[$i]
                    if ($ex.messages) {
                        foreach ($m in $ex.messages) {
                            if ($m.role -eq 'user') {
                                $base += "User: $($m.text)`n"
                            } elseif ($m.role -eq 'assistant') {
                                $base += "Ena: $($m.text)`n"
                            }
                        }
                        $base += "---`n"
                    }
                }
                break
            }
        } catch {
        }
    }

    return $base
}

function ConvertTo-ChatMessages([object]$memory, [string]$inputText) {
    $messages = New-Object System.Collections.Generic.List[object]
    $systemPrompt = Get-SystemPrompt
    if ($memory.userName) {
        $systemPrompt += "`n`nThe user's name is $($memory.userName)."
    }

    $messages.Add([pscustomobject]@{ role = 'system'; content = $systemPrompt })

    $ragContext = Get-RagContext $inputText
    if ($ragContext.Count -gt 0) {
        Write-DebugLog ("RAG matches={0} sources={1}" -f $ragContext.Count, ($ragContext.Sources -join ','))
        $messages.Add([pscustomobject]@{ role = 'system'; content = $ragContext.Text })
    }

    $storyContext = Get-StoryContext $inputText
    if ($storyContext.Count -gt 0) {
        Write-DebugLog ("Story matches={0} sources={1}" -f $storyContext.Count, ($storyContext.Sources -join ','))
        $messages.Add([pscustomobject]@{ role = 'system'; content = $storyContext.Text })
    }

    if (-not [string]::IsNullOrWhiteSpace($script:lastScreenContext)) {
        $messages.Add([pscustomobject]@{
            role = 'system'
            content = "Latest user-approved screen context. Use it only when relevant to the user's question; do not claim to see live changes after this screenshot:`n$script:lastScreenContext"
        })
    }

    $recentHistory = @()
    if ($memory.history) {
        $recentHistory = $memory.history | Select-Object -Last 10
    }

    foreach ($entry in $recentHistory) {
        $role = if ($entry.role -eq 'user') { 'user' } else { 'assistant' }
        $messages.Add([pscustomobject]@{ role = $role; content = [string]$entry.text })
    }

    $messages.Add([pscustomobject]@{ role = 'user'; content = $inputText })
    return $messages
}

function Capture-ScreenImageBytes([int]$maxWidth = 1280) {
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $scaledBitmap = $null
    $scaledGraphics = $null
    $stream = $null

    try {
        $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bounds.Size)

        $outputBitmap = $bitmap
        if ($bounds.Width -gt $maxWidth) {
            $scale = $maxWidth / $bounds.Width
            $scaledWidth = [Math]::Max(1, [int]($bounds.Width * $scale))
            $scaledHeight = [Math]::Max(1, [int]($bounds.Height * $scale))
            $scaledBitmap = New-Object System.Drawing.Bitmap($scaledWidth, $scaledHeight)
            $scaledGraphics = [System.Drawing.Graphics]::FromImage($scaledBitmap)
            $scaledGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $scaledGraphics.DrawImage($bitmap, 0, 0, $scaledWidth, $scaledHeight)
            $outputBitmap = $scaledBitmap
        }

        $stream = New-Object System.IO.MemoryStream
        $outputBitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        return $stream.ToArray()
    } finally {
        if ($stream) { $stream.Dispose() }
        if ($scaledGraphics) { $scaledGraphics.Dispose() }
        if ($scaledBitmap) { $scaledBitmap.Dispose() }
        if ($graphics) { $graphics.Dispose() }
        if ($bitmap) { $bitmap.Dispose() }
    }
}

function Capture-ScreenImageBase64([int]$maxWidth = 1280) {
    $bytes = Capture-ScreenImageBytes $maxWidth
    return [Convert]::ToBase64String($bytes)
}

function Await-WinRtOperation($operation, [type]$resultType) {
    $method = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq 'AsTask' -and
            $_.IsGenericMethodDefinition -and
            $_.GetParameters().Count -eq 1
        } |
        Select-Object -First 1

    if (-not $method) {
        throw 'Unable to find Windows Runtime AsTask helper.'
    }

    $task = $method.MakeGenericMethod($resultType).Invoke($null, @($operation))
    $task.Wait()
    return $task.Result
}

function Invoke-WindowsOcr([byte[]]$imageBytes) {
    $tempFile = Join-Path $env:TEMP ("virtual-ena-screen-{0}.png" -f ([Guid]::NewGuid().ToString('N')))

    try {
        [System.IO.File]::WriteAllBytes($tempFile, $imageBytes)

        $storageFileType = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
        $fileAccessModeType = [Windows.Storage.FileAccessMode, Windows.Storage, ContentType = WindowsRuntime]
        $streamType = [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
        $decoderType = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
        $softwareBitmapType = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
        $ocrEngineType = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
        $ocrResultType = [Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType = WindowsRuntime]

        $file = Await-WinRtOperation ($storageFileType::GetFileFromPathAsync($tempFile)) $storageFileType
        $stream = Await-WinRtOperation ($file.OpenAsync($fileAccessModeType::Read)) $streamType
        $decoder = Await-WinRtOperation ($decoderType::CreateAsync($stream)) $decoderType
        $bitmap = Await-WinRtOperation ($decoder.GetSoftwareBitmapAsync()) $softwareBitmapType

        $engine = $ocrEngineType::TryCreateFromUserProfileLanguages()
        if (-not $engine) {
            throw 'Windows OCR engine is not available for current user languages.'
        }

        $result = Await-WinRtOperation ($engine.RecognizeAsync($bitmap)) $ocrResultType
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($line in $result.Lines) {
            $text = Normalize-Text ([string]$line.Text)
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                $lines.Add($text)
            }
        }

        if ($lines.Count -eq 0) {
            return ''
        }

        return ($lines -join "`n")
    } finally {
        try {
            if (Test-Path $tempFile) {
                Remove-Item -LiteralPath $tempFile -Force
            }
        } catch {
        }
    }
}

function Invoke-ScreenSummaryVision([System.Windows.Forms.Label]$statusLabel) {
    $settings = Get-VisionSettings
    if (-not $settings.ApiKey) {
        $statusLabel.Text = 'Status: AI key missing'
        Write-DebugLog 'Invoke-ScreenSummaryVision abort: API key missing'
        return $null
    }

    $statusLabel.Text = 'Status: capturing screen'
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $imageBase64 = Capture-ScreenImageBase64 1280
    } catch {
        $statusLabel.Text = 'Status: screen capture failed'
        Write-DebugLog ("Screen capture failed: {0}" -f $_.Exception.Message)
        return $null
    }

    $statusLabel.Text = 'Status: reading screen'
    [System.Windows.Forms.Application]::DoEvents()

    $messages = @(
        [pscustomobject]@{
            role = 'system'
            content = 'You summarize screenshots for a desktop companion. Describe visible apps, text, errors, forms, and user-relevant details. Be concise. Do not infer private facts beyond what is visible.'
        },
        [pscustomobject]@{
            role = 'user'
            content = @(
                [pscustomobject]@{
                    type = 'text'
                    text = '请用中文简要总结这张用户屏幕截图中可见的内容，重点提取窗口、页面、报错、按钮、文字和可能需要帮助的地方。'
                },
                [pscustomobject]@{
                    type = 'image_url'
                    image_url = [pscustomobject]@{
                        url = "data:image/png;base64,$imageBase64"
                    }
                }
            )
        }
    )

    $body = @{
        model = $settings.Model
        messages = $messages
        temperature = 0.2
        max_tokens = 500
    } | ConvertTo-Json -Depth 16

    Write-DebugLog ("Screen summary request model={0} bodyBytes={1}" -f $settings.Model, ([Text.Encoding]::UTF8.GetByteCount($body)))

    try {
        $client = New-Object System.Net.Http.HttpClient
        try {
            $client.Timeout = [TimeSpan]::FromSeconds(90)
            $client.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $settings.ApiKey)
            $content = New-Object System.Net.Http.StringContent($body, [System.Text.Encoding]::UTF8, 'application/json')
            $response = $client.PostAsync("$($settings.BaseUrl)/chat/completions", $content).Result
            $responseBody = $response.Content.ReadAsStringAsync().Result

            if ($response.IsSuccessStatusCode) {
                $responseJson = $responseBody | ConvertFrom-Json
                $summary = [string]$responseJson.choices[0].message.content
                if (-not [string]::IsNullOrWhiteSpace($summary)) {
                    $trimmed = Normalize-Text $summary.Trim()
                    Write-DebugLog ("Screen summary success len={0}" -f $trimmed.Length)
                    return $trimmed
                }
            }

            $statusLabel.Text = ('Status: screen AI error - ' + [int]$response.StatusCode)
            Write-DebugLog ("Screen summary non-success status={0} body={1}" -f [int]$response.StatusCode, $responseBody)
            return $null
        } finally {
            $client.Dispose()
        }
    } catch {
        $statusLabel.Text = ('Status: screen AI error - ' + $_.Exception.Message)
        Write-DebugLog ("Screen summary error: {0}" -f $_.Exception.Message)
        return $null
    }
}

function Invoke-OcrContextRefine([string]$ocrText, [System.Windows.Forms.Label]$statusLabel) {
    $settings = Get-ChatSettings
    if (-not $settings.ApiKey) {
        Write-DebugLog 'OCR refine skipped: AI key missing'
        return $null
    }

    $normalized = Normalize-Text $ocrText
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $null
    }

    $maxChars = 6000
    if ($normalized.Length -gt $maxChars) {
        $normalized = $normalized.Substring(0, $maxChars)
    }

    $messages = @(
        [pscustomobject]@{
            role = 'system'
            content = @'
你负责清洗 Windows OCR 从屏幕截图中识别出的文字。OCR 结果可能包含乱码、错别字、漏字、乱序和符号误识别。
请只提取对用户后续提问有用的信息，并尽量根据上下文补全明显的技术术语、错误码、文件名、按钮、窗口标题和日志含义。
不要编造屏幕上不存在的信息；不确定的内容标为“可能”。输出简体中文，控制在 8 条要点以内。
'@
        },
        [pscustomobject]@{
            role = 'user'
            content = "请清洗并提取这段屏幕 OCR 文本里的有用信息：`n`n$normalized"
        }
    )

    $body = @{
        model = $settings.Model
        messages = $messages
        temperature = 0.1
        max_tokens = 600
    } | ConvertTo-Json -Depth 12

    try {
        $statusLabel.Text = 'Status: OCR refining'
        [System.Windows.Forms.Application]::DoEvents()

        $client = New-Object System.Net.Http.HttpClient
        try {
            $client.Timeout = [TimeSpan]::FromSeconds(60)
            $client.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $settings.ApiKey)
            $content = New-Object System.Net.Http.StringContent($body, [System.Text.Encoding]::UTF8, 'application/json')
            $response = $client.PostAsync("$($settings.BaseUrl)/chat/completions", $content).Result
            $responseBody = $response.Content.ReadAsStringAsync().Result

            if ($response.IsSuccessStatusCode) {
                $responseJson = $responseBody | ConvertFrom-Json
                $refined = [string]$responseJson.choices[0].message.content
                if (-not [string]::IsNullOrWhiteSpace($refined)) {
                    $trimmed = Normalize-Text $refined.Trim()
                    $preview = $trimmed.Replace("`r", ' ').Replace("`n", ' ')
                    $preview = $preview.Substring(0, [Math]::Min(80, $preview.Length))
                    Write-DebugLog ("OCR refine success len={0} preview={1}" -f $trimmed.Length, $preview)
                    return $trimmed
                }
            }

            Write-DebugLog ("OCR refine non-success status={0} body={1}" -f [int]$response.StatusCode, $responseBody)
            return $null
        } finally {
            $client.Dispose()
        }
    } catch {
        Write-DebugLog ("OCR refine error: {0}" -f $_.Exception.Message)
        return $null
    }
}

function Invoke-ScreenSummaryOcr([System.Windows.Forms.Label]$statusLabel) {
    $statusLabel.Text = 'Status: capturing screen'
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $imageBytes = Capture-ScreenImageBytes 1600
    } catch {
        $statusLabel.Text = 'Status: screen capture failed'
        Write-DebugLog ("Screen capture failed: {0}" -f $_.Exception.Message)
        return $null
    }

    $statusLabel.Text = 'Status: OCR reading'
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $ocrText = Invoke-WindowsOcr $imageBytes
        if ([string]::IsNullOrWhiteSpace($ocrText)) {
            $statusLabel.Text = 'Status: OCR found no text'
            Write-DebugLog 'OCR completed with no text'
            return $null
        }

        $ocrPreview = (Normalize-Text $ocrText).Replace("`r", ' ').Replace("`n", ' ')
        $ocrPreview = $ocrPreview.Substring(0, [Math]::Min(50, $ocrPreview.Length))
        Write-DebugLog ("OCR success len={0} preview={1}" -f $ocrText.Length, $ocrPreview)
        $refined = Invoke-OcrContextRefine $ocrText $statusLabel
        if ($refined) {
            $summary = "Cleaned screen context from latest user-approved OCR screenshot:`n$refined"
            return $summary
        }

        $summary = "Raw screen OCR text from latest user-approved screenshot. OCR may contain recognition errors:`n$ocrText"
        Write-DebugLog 'OCR refine unavailable; using raw OCR text'
        return $summary
    } catch {
        $statusLabel.Text = ('Status: OCR error - ' + $_.Exception.Message)
        Write-DebugLog ("OCR error: {0}" -f $_.Exception.Message)
        return $null
    }
}

function Invoke-ScreenSummary([System.Windows.Forms.Label]$statusLabel) {
    $mode = Get-ScreenReadMode
    Write-DebugLog ("Screen read mode={0}" -f $mode)

    if ($mode -eq 'ocr') {
        return Invoke-ScreenSummaryOcr $statusLabel
    }

    return Invoke-ScreenSummaryVision $statusLabel
}

function Update-LocalMemory([string]$inputText, $memory, [System.Windows.Forms.Label]$statusLabel) {
    $name = Extract-Name $inputText
    if ($name) {
        $memory.userName = $name
        $statusLabel.Text = "Status: remembered $name"
    }
}

function Invoke-LLMReply([string]$inputText, $memory, [System.Windows.Forms.Label]$statusLabel) {
    $settings = Get-ChatSettings
    Write-DebugLog ("Invoke-LLMReply start provider={0} baseUrl={1} model={2} apiKeyPresent={3} inputLen={4} inputPreview={5}" -f $settings.Provider, $settings.BaseUrl, $settings.Model, ([string]::IsNullOrWhiteSpace($settings.ApiKey) -eq $false), $inputText.Length, ($inputText.Replace("`r", ' ').Replace("`n", ' ').Substring(0, [Math]::Min(80, $inputText.Length))))
    if (-not $settings.ApiKey) {
        $statusLabel.Text = 'Status: AI key missing'
        Write-DebugLog 'Invoke-LLMReply abort: API key missing'
        return $null
    }

    Update-LocalMemory $inputText $memory $statusLabel

    $messages = ConvertTo-ChatMessages $memory $inputText
    Write-DebugLog ("Request messages count={0} systemLen={1} historyCount={2}" -f $messages.Count, ($messages[0].content.Length), ($(if ($memory.history) { $memory.history.Count } else { 0 })))
    $body = @{ model = $settings.Model; messages = $messages; temperature = 0.8 } | ConvertTo-Json -Depth 12
    Write-DebugLog ("Request body bytes={0} apiKey={1}" -f ([Text.Encoding]::UTF8.GetByteCount($body)), (Mask-Secret $settings.ApiKey))

    try {
        $client = New-Object System.Net.Http.HttpClient
        try {
            $client.Timeout = [TimeSpan]::FromSeconds(60)
            $client.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $settings.ApiKey)
            $content = New-Object System.Net.Http.StringContent($body, [System.Text.Encoding]::UTF8, 'application/json')
            $response = $client.PostAsync("$($settings.BaseUrl)/chat/completions", $content).Result
            $responseBody = $response.Content.ReadAsStringAsync().Result

            if ($response.IsSuccessStatusCode) {
                $responseJson = $responseBody | ConvertFrom-Json
                $replyText = $responseJson.choices[0].message.content
                if ($replyText) {
                    $trimmed = [string]$replyText.Trim()
                    Write-DebugLog ("AI success status={0} replyLen={1} replyPreview={2}" -f [int]$response.StatusCode, $trimmed.Length, ($trimmed.Replace("`r", ' ').Replace("`n", ' ').Substring(0, [Math]::Min(120, $trimmed.Length))))
                    return Normalize-Text $trimmed
                }

                Write-DebugLog ("AI success but empty content returned status={0} body={1}" -f [int]$response.StatusCode, $responseBody)
                return $null
            }

            Write-DebugLog ("AI non-success status={0} reason={1} body={2}" -f [int]$response.StatusCode, $response.ReasonPhrase, $responseBody)
            $statusLabel.Text = ('Status: AI error - ' + [int]$response.StatusCode + ' ' + $response.ReasonPhrase + ' | ' + $responseBody)
            return $null
        } finally {
            $client.Dispose()
        }
    } catch {
        $errorMessage = $_.Exception.Message
        if ($_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $errorBody = $reader.ReadToEnd()
                if ($errorBody) {
                    $errorMessage = $errorMessage + ' | ' + $errorBody
                }
            } catch {
            }
        }
        $statusLabel.Text = ('Status: AI error - ' + $errorMessage)
        Write-DebugLog ("AI error: {0}" -f $errorMessage)
        return $null
    }

    Write-DebugLog 'AI call returned null content'
    return $null
}

function Extract-Name([string]$text) {
    if ($text -match '\u6211\u53eb\s*([^\s]{1,20})') {
        return $matches[1]
    }

    if ($text -match 'my name is\s*([^\s]{1,20})') {
        return $matches[1]
    }

    return ''
}

function Build-Reply([string]$inputText, $memory, [System.Windows.Forms.Label]$statusLabel) {
    $lower = $inputText.ToLowerInvariant()

    $aiReply = Invoke-LLMReply $inputText $memory $statusLabel
    if ($aiReply) {
        $statusLabel.Text = if ($memory.userName) { "Status: AI reply - remembered $($memory.userName)" } else { 'Status: AI reply' }
        return $aiReply
    }

    if ($statusLabel.Text -eq 'Status: AI error' -or $statusLabel.Text -eq 'Status: AI key missing') {
        $statusLabel.Text = $statusLabel.Text + ' (fallback)'
    }

    if ($inputText -match '\u6211\u53eb' -or $lower.Contains('my name is') -or $lower.Contains('i am called')) {
        $name = Extract-Name $inputText
        if ($name) {
            $memory.userName = $name
            $statusLabel.Text = "Status: remembered $name"
            return "Nice to meet you, $name. I will remember your name."
        }

        return 'Please tell me your name like: my name is Alex.'
    }

    if ($lower.Contains('do you remember me') -or $lower.Contains('remember me')) {
        if ($memory.userName) {
            return "Of course. You are $($memory.userName)."
        }

        return 'I do not know your name yet. You can say: my name is Alex.'
    }

    if ($lower.Contains('hello') -or $lower.Contains('hi')) {
        if ($memory.userName) {
            return "Hello, $($memory.userName)! What do you want to talk about?"
        }

        return 'Hello. Please tell me your name first.'
    }

    if ($lower.Contains('bye') -or $lower.Contains('goodbye')) {
        $statusLabel.Text = 'Status: idle'
        return 'See you next time.'
    }

    $statusLabel.Text = 'Status: chatting'
    if ($memory.userName) {
        $statusLabel.Text = "Status: fallback reply - remembered $($memory.userName)"
        return "$($memory.userName), I heard: $inputText. This MVP uses simple rules, and we can add a real AI next."
    }

    $statusLabel.Text = 'Status: fallback reply'
    return "I heard: $inputText. If you want memory, tell me your name first."
}

function Append-Chat([System.Windows.Forms.RichTextBox]$box, [string]$speaker, [string]$text) {
    $box.SelectionStart = $box.TextLength
    $box.SelectionLength = 0
    $box.SelectionColor = if ($speaker -eq 'You') { [System.Drawing.Color]::LightSkyBlue } else { [System.Drawing.Color]::Khaki }
    $box.AppendText("${speaker}: $(Normalize-Text $text)`r`n")
    $box.SelectionColor = $box.ForeColor
    $box.ScrollToCaret()
}

$memory = Load-Memory

$mainForm = New-Object System.Windows.Forms.Form
$mainForm.Text = 'Virtual Ena'
$mainForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$mainForm.StartPosition = 'Manual'
$mainForm.ClientSize = New-Object System.Drawing.Size(220, 220)
$mainForm.TopMost = $true
$mainForm.ShowInTaskbar = $false
$mainForm.BackColor = [System.Drawing.Color]::Fuchsia

$avatarImageLoaded = $false
$avatarImage = $null
if ($avatarPath -and (Test-Path $avatarPath)) {
    try {
        $avatarImage = [System.Drawing.Image]::FromFile($avatarPath)
        $avatarImageLoaded = $true
        $mainForm.TransparencyKey = [System.Drawing.Color]::Fuchsia
    } catch {
        $avatarImageLoaded = $false
    }
}

if (-not $avatarImageLoaded) {
    $mainForm.BackColor = [System.Drawing.Color]::FromArgb(40, 30, 50)
}

$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$mainForm.Left = $screen.Right - 260
$mainForm.Top = $screen.Bottom - 260

$dragging = $false
$dragOrigin = New-Object System.Drawing.Point(0, 0)
$avatarPressed = $false
$avatarDragging = $false
$avatarPressOrigin = New-Object System.Drawing.Point(0, 0)
$avatarPressTimer = New-Object System.Windows.Forms.Timer
$avatarPressTimer.Interval = 150 # 长按拖动头像的时间阈值

function Start-AvatarDrag {
    $script:avatarDragging = $true
    $script:dragging = $true
    $script:dragOrigin = [System.Windows.Forms.Cursor]::Position
}

$avatarPicture = New-Object System.Windows.Forms.PictureBox
$avatarPicture.Location = New-Object System.Drawing.Point(10, 10)
$avatarPicture.Size = New-Object System.Drawing.Size(200, 200)
$avatarPicture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$avatarPicture.BackColor = [System.Drawing.Color]::Transparent
if ($avatarImageLoaded) {
    $avatarPicture.Image = $avatarImage
}
$mainForm.Controls.Add($avatarPicture)

if (-not $avatarImageLoaded) {
    $fallbackLabel = New-Object System.Windows.Forms.Label
    $fallbackLabel.Text = 'Avatar missing'
    $fallbackLabel.AutoSize = $true
    $fallbackLabel.ForeColor = [System.Drawing.Color]::White
    $fallbackLabel.Location = New-Object System.Drawing.Point(54, 102)
    $fallbackLabel.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $mainForm.Controls.Add($fallbackLabel)
}

$exitMenu = New-Object System.Windows.Forms.ContextMenuStrip
$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
$exitItem.Text = 'Exit'
$exitItem.Add_Click({ $mainForm.Close() })
$exitMenu.Items.Add($exitItem) | Out-Null
$mainForm.ContextMenuStrip = $exitMenu
$avatarPicture.ContextMenuStrip = $exitMenu

$bubbleForm = New-Object System.Windows.Forms.Form
$bubbleForm.Text = 'Ena Chat'
$bubbleForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$bubbleForm.StartPosition = 'Manual'
$bubbleForm.ClientSize = New-Object System.Drawing.Size(340, 220)
$bubbleForm.TopMost = $true
$bubbleForm.ShowInTaskbar = $false
$bubbleForm.BackColor = [System.Drawing.Color]::FromArgb(26, 22, 39)
$bubbleForm.ForeColor = [System.Drawing.Color]::White
$bubbleForm.Visible = $false

$bubbleBorder = New-Object System.Windows.Forms.Panel
$bubbleBorder.Dock = 'Fill'
$bubbleBorder.Padding = New-Object System.Windows.Forms.Padding(10)
$bubbleBorder.BackColor = [System.Drawing.Color]::FromArgb(38, 31, 58)
$bubbleForm.Controls.Add($bubbleBorder)

$bubbleTitle = New-Object System.Windows.Forms.Label
$bubbleTitle.Text = 'Harumi Ena'
$bubbleTitle.AutoSize = $true
$bubbleTitle.Location = New-Object System.Drawing.Point(10, 10)
$bubbleTitle.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$bubbleBorder.Controls.Add($bubbleTitle)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = if ($memory.userName) { "Status: remembered $($memory.userName)" } else { 'Status: online' }
$statusLabel.AutoSize = $true
$statusLabel.Location = New-Object System.Drawing.Point(10, 32)
$statusLabel.ForeColor = [System.Drawing.Color]::Gainsboro
$bubbleBorder.Controls.Add($statusLabel)

$bubbleClose = New-Object System.Windows.Forms.Button
$bubbleClose.Text = 'X'
$bubbleClose.Width = 28
$bubbleClose.Height = 24
$bubbleClose.FlatStyle = 'Flat'
$bubbleClose.FlatAppearance.BorderSize = 0
$bubbleClose.BackColor = [System.Drawing.Color]::FromArgb(80, 60, 100)
$bubbleClose.ForeColor = [System.Drawing.Color]::White
$bubbleClose.Location = New-Object System.Drawing.Point(302, 8)
$bubbleClose.Add_Click({ $bubbleForm.Hide() })
$bubbleBorder.Controls.Add($bubbleClose)

$clearButton = New-Object System.Windows.Forms.Button
$clearButton.Text = 'Clear'
$clearButton.Width = 54
$clearButton.Height = 24
$clearButton.FlatStyle = 'Flat'
$clearButton.FlatAppearance.BorderSize = 0
$clearButton.BackColor = [System.Drawing.Color]::FromArgb(90, 70, 120)
$clearButton.ForeColor = [System.Drawing.Color]::White
$clearButton.Location = New-Object System.Drawing.Point(240, 8)
$bubbleBorder.Controls.Add($clearButton)

$screenButton = New-Object System.Windows.Forms.Button
$screenButton.Text = 'Screen'
$screenButton.Width = 60
$screenButton.Height = 24
$screenButton.FlatStyle = 'Flat'
$screenButton.FlatAppearance.BorderSize = 0
$screenButton.BackColor = [System.Drawing.Color]::FromArgb(84, 104, 138)
$screenButton.ForeColor = [System.Drawing.Color]::White
$screenButton.Location = New-Object System.Drawing.Point(172, 8)
$bubbleBorder.Controls.Add($screenButton)

$chatBox = New-Object System.Windows.Forms.RichTextBox
$chatBox.ReadOnly = $true
$chatBox.BorderStyle = 'None'
$chatBox.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 26)
$chatBox.ForeColor = [System.Drawing.Color]::White
$chatBox.Location = New-Object System.Drawing.Point(10, 58)
$chatBox.Size = New-Object System.Drawing.Size(320, 104)
$chatBox.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$bubbleBorder.Controls.Add($chatBox)

$inputBox = New-Object System.Windows.Forms.TextBox
$inputBox.Location = New-Object System.Drawing.Point(10, 170)
$inputBox.Size = New-Object System.Drawing.Size(236, 24)
$inputBox.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$bubbleBorder.Controls.Add($inputBox)

$sendButton = New-Object System.Windows.Forms.Button
$sendButton.Text = 'Send'
$sendButton.Location = New-Object System.Drawing.Point(254, 168)
$sendButton.Size = New-Object System.Drawing.Size(76, 28)
$sendButton.BackColor = [System.Drawing.Color]::FromArgb(120, 91, 189)
$sendButton.ForeColor = [System.Drawing.Color]::White
$sendButton.FlatStyle = 'Flat'
$bubbleBorder.Controls.Add($sendButton)

function Refresh-Chat {
    $chatBox.Clear()
    foreach ($entry in $memory.history | Select-Object -Last 8) {
        $speaker = if ($entry.role -eq 'user') { 'You' } else { 'Ena' }
        Append-Chat $chatBox $speaker $entry.text
    }

    if (-not $memory.history -or $memory.history.Count -eq 0) {
        Append-Chat $chatBox 'Ena' 'Hi, I am the Virtual Ena MVP. Please click me and tell me your name.'
    }
}

function Clear-ChatHistory {
    $result = [System.Windows.Forms.MessageBox]::Show(
        'Clear the conversation history? This will erase the current chat log, but keep your remembered name.',
        'Clear History',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    $memory.history = @()
    Save-Memory $memory

    $statusLabel.Text = if ($memory.userName) { "Status: remembered $($memory.userName)" } else { 'Status: online' }
    Refresh-Chat
}

function Capture-ScreenContext {
    $screenButton.Enabled = $false
    $oldText = $screenButton.Text
    $screenButton.Text = '...'

    try {
        $summary = Invoke-ScreenSummary $statusLabel
        if ($summary) {
            $script:lastScreenContext = $summary
            $statusLabel.Text = 'Status: screen context ready'
            Append-Chat $chatBox 'Ena' "I read your screen. You can ask me about it now."
            Write-DebugLog ("Screen context updated len={0}" -f $summary.Length)
        } else {
            if (-not $statusLabel.Text.StartsWith('Status: screen') -and -not $statusLabel.Text.StartsWith('Status: AI key')) {
                $statusLabel.Text = 'Status: screen unavailable'
            }
            if ((Get-ScreenReadMode) -eq 'ocr') {
                Append-Chat $chatBox 'Ena' 'I could not read text from the screen. Make sure Windows OCR is available and the screen has readable text.'
            } else {
                Append-Chat $chatBox 'Ena' 'I could not read the screen. Check whether your current model supports image input, or set screenMode to ocr.'
            }
        }
    } finally {
        $screenButton.Text = $oldText
        $screenButton.Enabled = $true
        $inputBox.Focus()
    }
}

function Show-Bubble {
    Refresh-Chat

    $mainLeft = $mainForm.Left
    $mainTop = $mainForm.Top
    $bubbleX = $mainLeft + $mainForm.Width + 10
    $bubbleY = $mainTop + 10
    $screenBounds = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

    if ($bubbleX + $bubbleForm.Width -gt $screenBounds.Right) {
        $bubbleX = $mainLeft - $bubbleForm.Width - 10
    }

    if ($bubbleY + $bubbleForm.Height -gt $screenBounds.Bottom) {
        $bubbleY = $screenBounds.Bottom - $bubbleForm.Height - 10
    }

    if ($bubbleY -lt $screenBounds.Top) {
        $bubbleY = $screenBounds.Top + 10
    }

    $bubbleForm.Location = New-Object System.Drawing.Point($bubbleX, $bubbleY)
    $bubbleForm.Show()
    $bubbleForm.BringToFront()
    $inputBox.Focus()
}

function Toggle-Bubble {
    if ($bubbleForm.Visible) {
        $bubbleForm.Hide()
    } else {
        Show-Bubble
    }
}

function Send-Chat {
    $text = $inputBox.Text.Trim()
    if (-not $text) { return }

    Append-Chat $chatBox 'You' $text
    $memory.history += [pscustomobject]@{ role = 'user'; text = $text; ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

    $reply = Build-Reply $text $memory $statusLabel
    Append-Chat $chatBox 'Ena' $reply
    $memory.history += [pscustomobject]@{ role = 'bot'; text = $reply; ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

    Save-Memory $memory
    $inputBox.Clear()
    $inputBox.Focus()
}

$sendButton.Add_Click({ Send-Chat })
$clearButton.Add_Click({ Clear-ChatHistory })
$screenButton.Add_Click({ Capture-ScreenContext })
$inputBox.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $_.SuppressKeyPress = $true
        Send-Chat
    }
})

$avatarPressTimer.Add_Tick({
    $avatarPressTimer.Stop()
    if ($script:avatarPressed) {
        Start-AvatarDrag
    }
})

$avatarPicture.Add_MouseDown({
    $script:avatarPressed = $true
    $script:avatarDragging = $false
    $script:avatarPressOrigin = [System.Windows.Forms.Cursor]::Position
    $avatarPressTimer.Stop()
    $avatarPressTimer.Start()
})

$avatarPicture.Add_MouseMove({
    if ($script:avatarDragging) {
        $current = [System.Windows.Forms.Cursor]::Position
        $dx = $current.X - $script:dragOrigin.X
        $dy = $current.Y - $script:dragOrigin.Y
        $script:dragOrigin = $current
        $mainForm.Left += $dx
        $mainForm.Top += $dy
        if ($bubbleForm.Visible) { Show-Bubble }
    }
})

$avatarPicture.Add_MouseUp({
    $avatarPressTimer.Stop()
    if ($script:avatarDragging) {
        $script:avatarDragging = $false
        $script:avatarPressed = $false
        $script:dragging = $false
        return
    }

    if ($script:avatarPressed) {
        Toggle-Bubble
    }

    $script:avatarPressed = $false
})

$avatarPicture.Add_MouseLeave({
    if (-not $script:avatarDragging) {
        $avatarPressTimer.Stop()
        $script:avatarPressed = $false
    }
})

$mainForm.Add_MouseMove({
    if ($script:dragging) {
        $current = [System.Windows.Forms.Cursor]::Position
        $dx = $current.X - $script:dragOrigin.X
        $dy = $current.Y - $script:dragOrigin.Y
        $script:dragOrigin = $current
        $mainForm.Left += $dx
        $mainForm.Top += $dy
        if ($bubbleForm.Visible) { Show-Bubble }
    }
})

if ($mainForm.ContextMenuStrip -eq $null) {
    $mainForm.ContextMenuStrip = $exitMenu
}

[void]$mainForm.ShowDialog()
