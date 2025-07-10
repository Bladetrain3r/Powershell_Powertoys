# Pyttai Architecture

## Core Principles

1. **Separation of Commands**: Slash commands are immutable core functions. Aliases are user territory.
2. **Safety by Default**: No dangerous operations without explicit user action.
3. **UTF-8 Everywhere**: All text operations assume UTF-8. No exceptions.
4. **Structured Data**: All operations return standardized formats for composability.
5. **Explicit AI**: AI assistance only when requested, never assumed.

## Architecture Overview

```
┌─────────────────────────────────────────────┐
│              Main Entry (main.py)           │
│            Terminal UI, UTF-8 Setup         │
├─────────────────────────────────────────────┤
│         ChatController (core/chat.py)       │
│    Orchestration, Command Routing, State    │
├─────────────────────────────────────────────┤
│   Models          │   Controllers           │
│ ─────────────     │ ─────────────────────   │
│ CommandResult     │ APIController           │
│ OutputFormat      │ ClipboardController     │
│ Message           │ FileController          │  
│ Conversation      │ SessionController       │
│ Config            │ CommandController       │
└─────────────────────────────────────────────┘
```

## Command Architecture

### Slash Commands (Immutable Core)
Protected system commands that cannot be overridden:

- `/help` - Show available commands
- `/config [key=value]` - View/modify configuration
- `/model` - List available models
- `/alias [name]` - Manage user aliases
- `/session [save|load|list]` - Manage conversations
- `/mux [add|start|stop]` - Multi-model control
- `/paste [prompt]` - Send clipboard content

### Aliases (User Space)
Python scripts in `~/.pyttai/aliases/` that extend functionality:
- Custom commands and workflows
- Integration with external tools
- Personal productivity scripts
- Must follow standardized output format

### Operators (Data Flow)
Colon-prefixed operators for chaining operations:
- `:p` - Pipe output to next command
- `:r` - Redirect to file (overwrite)
- `:rr` - Append to file
- `:c` - Read file as command input
- `:ai` - Pipe to AI analysis

## Data Flow

```
User Input → Parse → Route:
                     ├─ Slash Command → Execute (immutable)
                     ├─ Alias → Load & Execute (user script)
                     └─ Chat → Send to AI

All operations return CommandResult → Format → Display
```

## Standardized Output

All commands/operations MUST return a `CommandResult`:

```python
class CommandResult:
    success: bool
    format: OutputFormat  # TEXT, DATA, TABLE, ERROR
    content: Any         # Actual data
    error: Optional[str]
    code: Optional[str]  # Error code for machines
    suggestion: Optional[str]  # Help for humans
```

This enables:
- Consistent error handling
- Reliable piping between commands
- AI-parseable outputs
- Testable operations

## File Structure

```
pyttai/
├── main.py              # Entry point, UTF-8 setup
├── core/
│   ├── models.py       # Data structures, CommandResult
│   ├── controllers.py  # Business logic
│   └── chat.py         # Main orchestrator
├── features/           # Core feature modules
│   ├── clipboard.py
│   └── session.py
└── ~/.pyttai/          # User configuration
    ├── config.json
    ├── aliases/        # User scripts
    └── sessions/       # Saved conversations
```

## Security Model

1. **No Eval**: Never execute arbitrary code
2. **Alias Approval**: First run requires user consent
3. **No Shell Injection**: Operators parsed safely
4. **Explicit File Access**: No implicit file operations
5. **Timeout Protection**: All operations have time limits

## Extension Points

### Adding a Slash Command (Core Development)
```python
# In ChatController._register_builtin_commands()
self.commands.register_command(
    "newcmd",
    handler_function,
    "Description",
    aliases=["nc"]
)
```

### Adding an Alias (User Extension)
```python
# ~/.pyttai/aliases/git_status.py
"""
name: git-status
description: Enhanced git status
version: 1.0.0
"""
def run(args):
    # Implementation
    return CommandResult.success_data({"changes": 5})
```

## Configuration

Layered configuration with precedence:
1. Command-line arguments (future)
2. Environment variables (PYTTAI_*)
3. User config (~/.pyttai/config.json)
4. Default config (built-in)

## Error Handling

All errors follow consistent format:
```json
{
    "success": false,
    "error": "Human readable message",
    "code": "MACHINE_CODE",
    "suggestion": "How to fix"
}
```

## Current Implementation Status

### Working
- Basic chat with LM Studio
- Slash commands: /help, /config, /model, /paste
- MVC architecture
- Plugin system for features

### In Progress
- UTF-8 enforcement
- Standardized error handling
- CommandResult implementation

### Planned
- Alias system
- Operator parsing
- Session management
- Multi-model support