# Pyttai Development Roadmap

*AI-native shell for developers - safe, extensible, cross-platform*

## Current State (v0.1.0) ✅

### Working
- Core MVC architecture with plugin system
- Streaming chat with LM Studio (OpenAI-compatible)
- Basic commands: `/paste`, `/file`, `/model`, `/config`, `/help`
- Conversation saving/loading
- JSON configuration

### Known Issues
- [ ] No UTF-8 enforcement
- [ ] Inconsistent error handling
- [ ] Missing input validation
- [ ] No feature import error handling

---

## Phase 1: Foundation (Next 2 weeks) 🚧

### 1.1 UTF-8 & Error Handling
```python
# Force UTF-8 everywhere
sys.stdout.reconfigure(encoding='utf-8')

# Consistent error format
{
    "success": False,
    "error": "File not found",
    "suggestion": "Check path exists"
}
```

### 1.2 Core Improvements
- [ ] Add comprehensive error handling
- [ ] Implement UTF-8 throughout
- [ ] Add path validation
- [ ] Create consistent return types
- [ ] Add basic logging

### 1.3 Documentation
- [ ] README.md - Quick start guide
- [ ] FUNCTIONS.md - API reference

---

## Phase 2: Core Features (Weeks 3-6) 🔧

### 2.1 Alias System
```bash
pyttai> /alias gitstat          # Run alias
pyttai> /alias list             # Show available
```

- Simple Python scripts in `~/.pyttai/aliases/`
- Structured output format
- First-run approval

### 2.2 Colon Operator Syntax
```bash
pyttai> list files :p filter .py      # Pipe
pyttai> status :r output.txt          # Redirect
```

**Essential operators**:
- `:p` - Pipe
- `:r` - Redirect (overwrite)
- `:rr` - Redirect (append)
- `:ai` - Pipe to AI

### 2.3 Session Management
- `/session save [name]` - Save conversation
- `/session load [name]` - Load conversation
- Auto-save on exit option

---

## Phase 3: Multi-Model Support (Weeks 7-10) 🤝

### 3.1 Model Multiplexing
```bash
pyttai> /mux add gpt4 http://localhost:1235
pyttai> /mux start
You: How should we design this?
[LMStudio]: Consider starting with...
[GPT4]: Building on that...
You: Good points, what about error handling?
```

- Sequential conversation with multiple models
- Each model sees full context
- User controls the flow

### 3.2 Implementation
- Multiple ChatController instances
- Shared conversation context
- Simple round-robin responses
- `/mux stop` to return to single model

---

## Phase 4: Stability & Polish (Weeks 11-12) 🎯

### 3.1 Testing
- Unit tests for core functionality
- Cross-platform testing (Linux, macOS)
- Edge case handling

### 3.2 Performance
- Optimize streaming
- Reduce startup time
- Memory usage optimization

### 3.3 Package & Distribution
- Setup.py for pip installation
- Single executable option
- Basic install documentation

---

## Design Principles

1. **MVP First** - Core functionality before features
2. **Safety First** - No dangerous defaults
3. **Cross-Platform** - Same behavior everywhere
4. **Low Dependencies** - httpx and pyperclip only
5. **User Control** - Explicit AI invocation
6. **Extensible** - But don't over-engineer

---

## Success Metrics

- **It works** - Reliable daily driver
- **It's useful** - Solves real problems
- **It's simple** - Easy to understand and modify

---

## Not in Scope (For Now)

- Complex shell command emulation
- IDE integrations  
- Web UI
- Plugin repository
- Advanced AI features (auto-complete, prediction)

These can be community contributions or future versions once the core is solid.