#!/usr/bin/env python3
"""
Business logic controllers for different operations
"""

import json
import sys
from typing import Optional, Callable, Generator, Dict, List
from pathlib import Path

import httpx

# Optional clipboard support
try:
    import pyperclip
    HAS_CLIPBOARD = True
except ImportError:
    HAS_CLIPBOARD = False

class APIController:
    """Handles API communication"""
    def __init__(self, base_url: str, timeout: float = 60.0):
        self.base_url = base_url
        self.timeout = timeout
        self.api_url = f"{base_url}/v1/chat/completions"
    
    def test_connection(self) -> bool:
        """Test if API is accessible"""
        try:
            with httpx.Client(timeout=5.0) as client:
                response = client.get(f"{self.base_url}/v1/models")
                return response.status_code == 200
        except:
            return False
    
    def get_models(self) -> Optional[List[Dict]]:
        """Fetch available models"""
        try:
            with httpx.Client(timeout=5.0) as client:
                response = client.get(f"{self.base_url}/v1/models")
                return response.json().get("data", [])
        except:
            return None
    
    def stream_completion(self, messages: List[Dict], config: Dict) -> Generator[str, None, None]:
        """Stream completion from API"""
        data = {
            "model": config.get("model", "local-model"),
            "messages": messages,
            "max_tokens": config.get("max_tokens", 1024),
            "temperature": config.get("temperature", 0.7),
            "stream": True
        }
        
        with httpx.Client(timeout=self.timeout) as client:
            with client.stream("POST", self.api_url, json=data) as response:
                for line in response.iter_lines():
                    if line.startswith("data: "):
                        data_str = line[6:]
                        if data_str == "[DONE]":
                            break
                        
                        try:
                            chunk = json.loads(data_str)
                            if "choices" in chunk and len(chunk["choices"]) > 0:
                                delta = chunk["choices"][0].get("delta", {})
                                if "content" in delta:
                                    yield delta["content"]
                        except json.JSONDecodeError:
                            pass

class ClipboardController:
    """Handles clipboard operations"""
    @staticmethod
    def get_clipboard() -> Optional[str]:
        if not HAS_CLIPBOARD:
            return None
        
        try:
            return pyperclip.paste()
        except Exception:
            return None
    
    @staticmethod
    def is_available() -> bool:
        return HAS_CLIPBOARD

class FileController:
    """Handles file operations"""
    @staticmethod
    def read_file(path: Path) -> Optional[str]:
        """Read file content"""
        try:
            return path.read_text()
        except Exception as e:
            print(f"Error reading file: {e}")
            return None
    
    @staticmethod
    def detect_language(path: Path) -> Optional[str]:
        """Detect programming language from file extension"""
        extensions = {
            '.py': 'python',
            '.js': 'javascript',
            '.ts': 'typescript',
            '.java': 'java',
            '.cpp': 'cpp',
            '.c': 'c',
            '.go': 'go',
            '.rs': 'rust',
            '.rb': 'ruby',
            '.php': 'php',
            '.sh': 'bash',
            '.yaml': 'yaml',
            '.yml': 'yaml',
            '.json': 'json',
            '.xml': 'xml',
            '.html': 'html',
            '.css': 'css',
            '.sql': 'sql',
            '.dockerfile': 'dockerfile',
            'Dockerfile': 'dockerfile'
        }
        
        # Check exact filename first
        if path.name in extensions:
            return extensions[path.name]
        
        # Then check extension
        return extensions.get(path.suffix.lower())

class SessionController:
    """Handles session management"""
    def __init__(self, session_dir: Path):
        self.session_dir = session_dir
        self.session_dir.mkdir(exist_ok=True)
    
    def get_session_path(self, name: str) -> Path:
        return self.session_dir / f"{name}.json"
    
    def list_sessions(self) -> List[str]:
        """List all saved sessions"""
        return [f.stem for f in self.session_dir.glob("*.json")]
    
    def session_exists(self, name: str) -> bool:
        return self.get_session_path(name).exists()

class CommandController:
    """Handles command parsing and execution"""
    def __init__(self):
        self.commands = {}
        self.aliases = {}
    
    def register_command(self, name: str, handler: Callable, description: str = "", aliases: Optional[List[str]] = None):
        """Register a command handler"""
        self.commands[name] = {
            "handler": handler,
            "description": description
        }
        
        if aliases:
            for alias in aliases:
                self.aliases[alias] = name
    
    def parse_input(self, user_input: str) -> tuple:
        """Parse user input into command and arguments"""
        if not user_input.startswith('/'):
            return None, user_input
        
        parts = user_input[1:].split(' ', 1)
        command = parts[0].lower()
        args = parts[1] if len(parts) > 1 else ""
        
        # Check aliases
        if command in self.aliases:
            command = self.aliases[command]
        
        return command, args
    
    def execute_command(self, command: str, args: str) -> bool:
        """Execute a command if it exists"""
        if command in self.commands:
            self.commands[command]["handler"](args)
            return True
        return False
    
    def get_help(self) -> str:
        """Get help text for all commands"""
        lines = ["Available commands:"]
        for name, info in self.commands.items():
            if info["description"]:
                lines.append(f"  /{name} - {info['description']}")
        return "\n".join(lines)