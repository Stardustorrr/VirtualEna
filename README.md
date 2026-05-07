# Virtual Ena

Windows desktop pet MVP with a transparent always-on-top avatar, local chat memory,
screen reading, and optional AI replies.

## Start

```powershell
npm install
npm run start
```

`npm run start` launches `desktop-pet.ps1` directly.

## Local Embedding Prototype

Use `tools/embedding_memory_probe.py` to test local embedding generation and a
small short-term-memory retrieval score.

```powershell
.\.venv\Scripts\pip.exe install -r tools\requirements-embedding.txt
$env:HF_ENDPOINT = "https://hf-mirror.com"
.\.venv\Scripts\python.exe tools\embedding_memory_probe.py "我摸了摸头"
```

The script uses `BAAI/bge-small-zh-v1.5`, prints the embedding dimension, and
ranks sample memories by a simple activation score.

## Project Structure

```text
.
├─ data/                 # Runtime data committed to Git
│  ├─ rag-corpus.json
│  └─ fewshot.examples.json
├─ images/               # Runtime avatar assets
├─ src/                  # Electron renderer files
├─ training/             # Local-only training workspace, ignored by Git
├─ desktop-pet.ps1       # Main Windows desktop pet app
├─ setting.json          # Non-secret runtime settings
├─ package.json
└─ README.md
```

## Version Control Notes

Commit `data/` because the app reads these files at startup for RAG context and
few-shot style examples. Do not commit `training/`; it contains raw text,
extraction scripts, generated datasets, and other local training artifacts.

## API Key

Do not put API keys in `setting.json`. Set environment variables instead:

```powershell
$env:DEEPSEEK_API_KEY = "your-key"
# or
$env:OPENAI_API_KEY = "your-key"
```

For persistent user-level variables:

```powershell
[Environment]::SetEnvironmentVariable("DEEPSEEK_API_KEY", "your-key", "User")
[Environment]::SetEnvironmentVariable("OPENAI_API_KEY", "your-openai-key", "User")
```

Restart PowerShell or restart the desktop pet after setting persistent variables.

## Settings

Choose the normal chat model in `setting.json`:

```json
{
  "chatProvider": "deepseek",
  "chatBaseUrl": "https://api.deepseek.com/v1",
  "chatModel": "deepseek-chat",
  "screenMode": "ocr",
  "visionBaseUrl": "https://api.openai.com/v1",
  "visionModel": "gpt-4o-mini"
}
```

`screenMode` can be:

- `ocr`: use local Windows OCR.
- `vision`: send a screenshot to a vision-capable model.

## Ena Dialogue State

The main app stores dialogue state in `%APPDATA%\VirtualEna\memory.json`.
Existing memory files are migrated automatically. The current structure includes:

- `emotion`: `valence`, `arousal`, and `attachment`, each clamped to `[-1, 1]`.
- `shortTermMemories`: temporary memories with `content`, `t0`, `strength`,
  `emotion`, `embedding`, `blur`, and `clarity`.
- `needs`, `behavior`, and `affection`: reserved structures for later systems.

The model receives an internal state prompt containing Ena's emotion text and the
selected working memories, then returns JSON:

```json
{
  "reply": "visible reply",
  "emotion_delta": { "valence": 0.05, "arousal": 0.0, "attachment": 0.02 },
  "memory_importance": 0.6
}
```

The app shows only `reply`, applies `emotion_delta`, and stores the conversation
as a temporary memory.

### Tunable Parameters

All unclear formula parameters live under `enaSystem` in `setting.json`.

- `emotion.decayToNeutralPerTurn`: how quickly emotion drifts toward neutral each turn.
- `emotion.deltaScale`: scales model-provided `emotion_delta` before applying it.
- `emotion.maxDeltaPerTurn`: clamps one-turn emotional changes.
- `memory.forgettingA`: `A` in `gamma = A * (1 - |e|)`. Higher means faster forgetting.
- `memory.deleteThreshold`: memories below this strength are removed.
- `memory.recallBoost`: `r` in `s_new = min(1, s_old + r * activation)`.
- `memory.blurK`: `k` in the clarity/blur sigmoid. Higher makes blur change more sharply.
- `memory.blurB`: `B` in `T = B / (1 - |e|)`. Higher delays blur.
- `memory.activationSemanticWeight`: `a_1` in activation.
- `memory.activationStrengthWeight`: `a_2` in activation.
- `memory.workMemoryThreshold`: `w`; selected memories must exceed this activation.
- `memory.workMemoryTopK`: maximum working memories sent to the model.
- `memory.initialStrengthBase`: base strength for new dialogue memories.
- `memory.initialStrengthEmotionWeight`: extra initial strength from emotional intensity.
- `memory.maxShortTermMemories`: cap for temporary memories.

### Debugging

Use `%APPDATA%\VirtualEna\memory.json` to inspect the live state after each chat
turn. For faster tuning, edit `setting.json`, restart the app, and try the same
few prompts repeatedly.

Good first tuning moves:

- Ena forgets too quickly: lower `memory.forgettingA` or `memory.deleteThreshold`.
- Old memories appear too often: raise `memory.workMemoryThreshold`.
- Memories feel too fuzzy too soon: raise `memory.blurB` or lower `memory.blurK`.
- Emotion swings too hard: lower `emotion.deltaScale` or `emotion.maxDeltaPerTurn`.
- Emotion feels flat: raise `emotion.deltaScale` slightly.

Request diagnostics are written to `%APPDATA%\VirtualEna\debug.log`, including
message counts and prompt sizes.
