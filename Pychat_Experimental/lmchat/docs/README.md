# Pyttai - AI-Native Shell for Developers

A powerful, extensible terminal interface that integrates AI assistance into your command-line workflow. Built with Python, designed for safety, works everywhere.

## Features

- 🤖 **AI-Powered** - Chat with local or remote language models
- 🔌 **Extensible** - Plugin architecture for custom commands
- 🌍 **Cross-Platform** - Works on Windows, Linux, macOS
- 🛡️ **Safe by Default** - No dangerous operations without explicit consent
- 📋 **Smart Clipboard** - Seamlessly send clipboard content to AI
- 📁 **File Analysis** - Read and analyze code/text files

## Quick Start

### Prerequisites
- Python 3.8+
- LM Studio (or compatible OpenAI API server)

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/pyttai.git
cd pyttai

# Install dependencies
pip install -r requirements.txt

# Run
python main.py
```

### First Run

1. Start LM Studio and load a model
2. Run `python main.py`
3. The config file will be created at `~/.lmchat/config.json`
4. Edit the config if needed (default: `http://localhost:1234`)

## Usage

### Basic Chat
```
You: Explain Python decorators
Assistant: Decorators are a way to modify functions...
```

### Commands

| Command | Description | Example |
|---------|-------------|---------|
| `/help` | Show available commands | `/help` |
| `/paste` | Send clipboard content | `/paste analyze this code` |
| `/file` | Read and send file | `/file script.py explain` |
| `/model` | List available models | `/model` |
| `/config` | View/set configuration | `/config temperature=0.8` |
| `clear` | Clear conversation | `clear` |
| `exit` | Quit application | `exit` |

### Command Examples

```bash
# Send clipboard content with prompt
/paste summarize this error message

# Analyze a file
/file main.py suggest improvements

# Check configuration
/config
/config max_tokens=2048
```

## Configuration

Configuration file location: `~/.lmchat/config.json`

```json
{
    "base_url": "http://localhost:1234",
    "model": "local-model",
    "max_tokens": 1024,
    "temperature": 0.7,
    "system_prompt": "You are a helpful assistant.",
    "stream": true,
    "timeout": 60.0
}
```

## Architecture

Pyttai uses a modular MVC architecture:

- **Models** - Data structures (conversations, messages, config)
- **Controllers** - Business logic (API, clipboard, files)
- **Features** - Plugin modules for commands
- **View** - Terminal interface

See [ARCHITECTURE.md](ARCHITECTURE.md) for details.

## Extending

Add custom commands by creating a feature module:

```python
# features/myfeature.py
def register_commands(chat_controller):
    def handle_mycommand(args):
        # Your implementation
        chat_controller.send_message(f"Processing: {args}")
    
    chat_controller.commands.register_command(
        "mycommand",
        handle_mycommand,
        "Description of my command"
    )
```

## Roadmap

- ✅ Basic chat interface
- ✅ Clipboard integration
- ✅ File reading
- 🚧 UTF-8 support
- 🚧 Alias system
- 📋 Multi-model support
- 📋 OS-agnostic commands

See [ROADMAP.md](ROADMAP.md) for full details.

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Built for use with [LM Studio](https://lmstudio.ai/)
- Inspired by the Unix philosophy: do one thing well
- Designed for developers who want AI in their workflow

---

**Note**: This is an early version. Please report issues and suggestions!