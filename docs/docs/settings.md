# Settings

Settings are grouped into five sections: Core, Appearance, Controls, Translation, and Project. Changes are saved when you close the Settings window. If any value is invalid (for example, a backup period), the window will show an error and won’t save until you fix it.

## Core

### Backup

Controls automatic project backups.

- Enabled - Turns automatic backups on or off.

- Period - How often a backup is created. Smaller values create backups more frequently.

- Max backups - The maximum number of backups kept per project. When the limit is reached, older backups are removed.

### Updates

- Check for updates - If enabled, the app checks for updates automatically.

## Appearance

### Translation table font

- Font

  Sets the font used in the translation table.

- Font size

  Sets the font size (in points) used in the translation table. Valid range is 8–96.

### Theme and style

- Style

  Selects the Qt UI style (widget theme). This affects the look of buttons, lists, and other controls.

- Theme

  Selects the application color scheme (Light/Dark/System depending on platform support).

### Display options

- Display trailing whitespace - If enabled, leading/trailing whitespaces in the text are visually marked in the translation table.

- Display words and characters - If enabled, shows word/character count in the status bar.

## Controls

Keyboard shortcuts

This section lets you configure the key bindings used to open panels and menus. Click a shortcut field and press the desired key combination.

- Search panel
- Tab panel
- Go to row
- Batch menu
- Bookmark menu
- Match menu
- Glossary menu
- Translations menu

Notes:

- Shortcuts are stored as key sequence strings (for example, `Ctrl+G`).
- If you assign the same shortcut to multiple actions, behavior will conflict, don't do this.

## Translation

The Translation section configures translation endpoints. Select an endpoint from the list to see and modify its settings.

### General options

- Single translation

  If enabled, the endpoint will be used to translate the source text when the corresponding translation cell is edited. This translation will be shown in the translations menu. Don't use it with priced LLM models, you will burn your tokens.

- Use glossary

  If enabled, your glossary from the glossary menu will be used when translating.

### Google

Free and unlimited.

No API key is required.

### Yandex

Requires credentials.

- API key

  Your Yandex Translate API key.

- Folder ID

  The Yandex Cloud folder identifier required by the API.

### DeepL

Requires an API key and can optionally use a glossary.

- API key

  Your DeepL API key.

### LLM endpoints (OpenAI / Claude / Gemini / DeepSeek / OpenAI-compatible / Ollama)

These endpoints share the same configuration fields.

Credentials and connection

- API key

  Secret key used to authenticate to the provider. It's optional for local providers, which include OpenAI-compatible and Ollama.

- Base URL

  Endpoint base URL for OpenAI-compatible servers and Ollama.

Model

- Model

  The model name to use for translation. Use "Check key" to fetch available models.

- Check key

  Validates the API key/base URL by requesting the list of available models and populating the Model dropdown. If this fails, you’ll see an error message.

Generation limits

- Token limit

  Maximum input/context token budget sent to the model. Valid range: 1000–65536.

- Output token limit

  Maximum tokens the model may generate in its response. Valid range: 1000–65536.

Sampling

- Temperature

  Controls randomness/creativity. Lower values are more deterministic. Valid range: 0.0–2.0.

Behavior

- Use glossary

  If enabled, glossary terms will be supplied in the request.

- Thinking

  Enables thinking/reasoning mode for endpoints/models that support it.

Prompts

- System prompt

  The main instruction prompt used for translation.

- Default

  Resets the system prompt to the built-in default.

- Single-translation system prompt

  A separate system prompt used specifically for single-translation, when it's enabled.

- Default

  Resets the single-translation system prompt to the built-in default.

### LanguageTool

Currently **WIP**.

## Project

Project settings are stored per project (not globally). This section controls translation behavior and context for the currently open project.

### Line length hint

The number of the hint line in characters. When translation cell is edited, this will draw a thin red line at the supplied character limit.

### Source language

The language of the source text. Currently, available languages are only those, that are supported by our underlying [text matching library](https://github.com/savannstm/language-tokenizer/blob/master/src/lib.rs#L139).

### Translation language

The language of the translation text. Currently, available languages are only those, that are supported by our underlying [text matching library](https://github.com/savannstm/language-tokenizer/blob/master/src/lib.rs#L139).

### Project context

A free-form text field describing the overall project context (setting, tone, terminology, audience). This is automatically supplied to LLMs, when translating.

### File context (per file)

- List (right): shows available files to assign file context to.
- Text (left): context specific to the selected file (e.g., character names, UI tone, glossary notes, constraints).

This is automatically supplied to LLMs, when translating.
