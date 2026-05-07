# Virtual Ena

Windows desktop pet MVP with a transparent always-on-top avatar, local chat memory,
screen reading, and optional AI replies.

## Start

```powershell
npm install
npm run start
```

`npm run start` launches `desktop-pet.ps1` directly.

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
