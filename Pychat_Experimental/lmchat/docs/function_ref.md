# Pyttai Function Reference

## Core Classes

### ChatController
Main orchestrator for the application.

```python
class ChatController:
    def __init__(self, config_path: Optional[Path] = None)
    def test_connection(self) -> bool
    def send_message(self, message: str) -> bool
    def process_input(self, user_input: str) -> bool
    def register_feature(self, feature_module)
    def run(self)
```

**Methods:**
- `test_connection()` - Verify API server is accessible
- `send_message(message)` - Send message and stream response
- `process_input(input)` - Process user input (commands or chat)
- `register_feature(module)` - Register a feature module
- `run()` - Start main interaction loop

### Models

#### Message
```python
class Message:
    def __init__(self, role: str, content: str, timestamp: Optional[datetime] = None)
    def to_dict(self) -> Dict
    def from_dict(cls, data: Dict) -> 'Message'
```

#### Conversation
```python
class Conversation:
    def add_message(self, role: str, content: str)
    def get_messages_for_api(self, max_messages: Optional[int] = None) -> List[Dict]
    def clear(self)
    def save(self, path: Path)
    def load(cls, path: Path) -> 'Conversation'
```

#### Config
```python
class Config:
    def get(self, key: str, default=None)
    def set(self, key: str, value)
    def save(self)
```

## Controllers

### APIController
Handles communication with LM Studio/OpenAI API.

```python
class APIController:
    def test_connection(self) -> bool
    def get_models(self) -> Optional[List[Dict]]
    def stream_completion(self, messages: List[Dict], config: Dict) -> Generator[str, None, None]
```

### CommandController
Manages command registration and execution.

```python
class CommandController:
    def register_command(self, name: str, handler: Callable, description: str = "", aliases: List[str] = None)
    def parse_input(self, user_input: str) -> tuple
    def execute_command(self, command: str, args: str) -> bool
    def get_help(self) -> str
```

### ClipboardController
Handles system clipboard operations.

```python
class ClipboardController:
    @staticmethod
    def get_clipboard() -> Optional[str]
    @staticmethod
    def is_available() -> bool
```

### FileController
File I/O operations.

```python
class FileController:
    @staticmethod
    def read_file(path: Path) -> Optional[str]
    @staticmethod
    def detect_language(path: Path) -> Optional[str]
```

### SessionController
Manages conversation persistence.

```python
class SessionController:
    def get_session_path(self, name: str) -> Path
    def list_sessions(self) -> List[str]
    def session_exists(self, name: str) -> bool
```

## Feature Module Interface

All feature modules must implement:

```python
def register_commands(chat_controller: ChatController):
    """Register commands with the chat controller"""
    pass
```

### Command Handler Signature
```python
def handle_command(args: str):
    """
    Args:
        args: String containing everything after the command
    
    Returns:
        None (prints output directly or uses chat_controller.send_message)
    """
    pass
```

## Creating a Feature Module

### Basic Example
```python
# features/example.py
def register_commands(chat_controller):
    def handle_example(args):
        if not args:
            print("Usage: /example <text>")
            return
        
        # Process args
        result = args.upper()
        
        # Send to AI for analysis
        chat_controller.send_message(f"Analyze this: {result}")
    
    chat_controller.commands.register_command(
        "example",
        handle_example,
        "Convert text to uppercase and analyze",
        aliases=["ex", "e"]
    )
```

### Advanced Example with Error Handling
```python
def register_commands(chat_controller):
    def handle_advanced(args):
        try:
            # Parse arguments
            parts = args.split()
            if len(parts) < 2:
                print("Error: Need at least 2 arguments")
                return
            
            # Access controllers
            clipboard = chat_controller.clipboard.get_clipboard()
            if clipboard:
                message = f"{args}\n\nClipboard:\n{clipboard}"
            else:
                message = args
            
            # Send for processing
            chat_controller.send_message(message)
            
        except Exception as e:
            print(f"Error in advanced command: {e}")
    
    chat_controller.commands.register_command(
        "advanced",
        handle_advanced,
        "Advanced command with clipboard integration"
    )
```

## API Usage Examples

### Sending a Message
```python
# Simple message
chat.send_message("Explain Python generators")

# With context
conversation.add_message("user", "What is Python?")
conversation.add_message("assistant", "Python is...")
chat.send_message("Now explain generators")
```

### Command Registration
```python
# Basic command
commands.register_command("test", lambda args: print(f"Test: {args}"))

# With aliases
commands.register_command(
    "search",
    search_handler,
    "Search for patterns",
    aliases=["s", "find"]
)
```

### Configuration Access
```python
# Get config value
timeout = config.get("timeout", 60.0)

# Set config value
config.set("temperature", 0.8)
config.save()
```

## Error Handling Patterns

### Recommended Pattern
```python
def safe_operation():
    try:
        # Risky operation
        result = perform_operation()
        return {"success": True, "data": result}
    except SpecificError as e:
        return {
            "success": False,
            "error": str(e),
            "code": "SPECIFIC_ERROR",
            "suggestion": "Try this instead..."
        }
    except Exception as e:
        return {
            "success": False,
            "error": str(e),
            "code": "UNKNOWN_ERROR"
        }
```

## Future API (Planned)

### Alias System
```python
class AliasController:
    def load_aliases(self, directory: Path)
    def execute_alias(self, name: str, args: Dict) -> Dict
    def validate_alias(self, path: Path) -> bool
```

### Multi-Model Support
```python
class MultiModelController:
    def add_model(self, name: str, config: Dict)
    def remove_model(self, name: str)
    def broadcast_message(self, message: str) -> Dict[str, str]
```