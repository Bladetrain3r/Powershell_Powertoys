# PyShell-AI / Pyttai - Development Roadmap

## Current State (v0.1.0)

### ✅ Working Features
- **Core Architecture**: MVC structure with plugin system
- **Basic Chat**: Streaming conversations with LM Studio
- **Commands**:
  - `/paste` - Send clipboard content
  - `/file` - Read and send file content
  - `/model` - List available models
  - `/config` - View/modify configuration
  - `/help` - Show available commands
  - Built-in: `exit`, `clear`
- **Storage**: Conversation saving as JSON
- **Configuration**: JSON-based config with defaults

### 🧪 Tested On
- Windows with Python 3.x
- LM Studio local server
- Basic clipboard operations
- Simple file reading

### 📦 Dependencies
- httpx (HTTP client)
- pyperclip (clipboard access)

---

## Short Term (Next 2-4 weeks)

### 1. Alias System
**Goal**: Allow users to run approved Python scripts as commands

```python
# ~/.pyttai/aliases/gitstat.py
def run(args):
    # Custom git status formatter
    return formatted_output

# Usage
pyttai> /alias gitstat
pyttai> /alias gitstat --ai  # With AI analysis
```

**Implementation**:
- Create `features/alias.py`
- Scan alias directory on startup
- First-run approval system
- Pass command args to script
- Capture and display output
- Optional `--ai` flag for AI analysis

### 2. Skip-by-Default AI
**Goal**: Run commands without AI unless explicitly requested

```python
pyttai> list files          # Just output
pyttai> list files --ai     # Output + AI analysis
pyttai> search TODO | ai    # Pipe syntax
```

**Implementation**:
- Add `--ai` flag parsing
- Create pipe operator for commands
- Modify send_message to be optional

### 3. Session Management
**Goal**: Better conversation persistence

- `/session new [name]` - Start fresh session
- `/session load [name]` - Load previous session
- `/session list` - Show saved sessions
- Auto-save on exit option

---

## Mid Term (1-2 months)

### 1. Multi-Model Conversation (Muxing)
**Goal**: Multiple models as conversation participants

```python
pyttai> /mux add gpt4 http://localhost:1235
pyttai> /mux add claude http://localhost:1236
pyttai> /mux start

You: How should we implement this feature?
[LMStudio]: I suggest starting with...
[GPT4]: Building on that...
[Claude]: I'd also consider...

pyttai> /mux stop
```

**Implementation**:
- Create `features/multimodel.py`
- Manage multiple ChatController instances
- Sequential response system
- Shared conversation context
- Model identification in output

### 2. Basic OS-Agnostic Commands
**Goal**: Consistent commands across platforms

```python
pyttai> ls              # or 'list'
pyttai> cd ..          
pyttai> pwd            
pyttai> find "*.py"    
pyttai> env PATH       
```

**Implementation**:
- Create `features/filesystem.py`
- Use pathlib, os, glob for operations
- Consistent output format
- Error handling

### 3. Non-Interactive Mode
**Goal**: Use in scripts and pipelines

```bash
echo "Explain this error" | pyttai --stdin
pyttai --prompt "Generate a README" > README.md
pyttai --file script.py --prompt "Add error handling" --output script_v2.py
```

---

## Long Term (3-6 months)

### 1. Full OS-Agnostic Shell Commands
**Goal**: Complete shell replacement capabilities

- Process management (`ps`, `kill` equivalents)
- Network utilities (`curl`, `wget` equivalents)  
- Archive handling (`zip`, `tar` equivalents)
- Text processing (`grep`, `sed` equivalents)

### 2. Advanced AI Integration
**Goal**: Deeper AI assistance

- Command prediction/autocomplete
- Error diagnosis and auto-fix suggestions
- Context-aware help
- Learning from user patterns

### 3. Plugin Ecosystem
**Goal**: Community-contributed features

- Plugin repository/registry
- Dependency management
- Security scanning
- Easy installation: `pyttai install plugin-name`

### 4. IDE/Editor Integration
**Goal**: Use within development environments

- VS Code extension
- Vim/Neovim plugin
- API for external tools

---

## Design Principles (Maintain Throughout)

1. **Safety First**: No dangerous operations by default
2. **Cross-Platform**: Same behavior on Windows/Linux/Mac
3. **Modular**: Features as plugins
4. **Low Dependencies**: Minimize external requirements
5. **User Control**: Explicit AI invocation
6. **Extensible**: Easy for users to add functionality

---

## Success Metrics

- **Adoption**: Users preferring this over direct shell for AI tasks
- **Stability**: Reliable operation across platforms
- **Performance**: Minimal latency for non-AI commands
- **Extensibility**: Active plugin development
- **Safety**: No security incidents from default operations