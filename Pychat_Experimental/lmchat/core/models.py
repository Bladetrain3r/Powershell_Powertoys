#!/usr/bin/env python3
"""
Core data models for chat application
"""

import json
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Optional, Any
from enum import Enum

class OutputFormat(Enum):
    """Standard output formats for commands"""
    TEXT = "text"
    DATA = "data"
    TABLE = "table"
    STATUS = "status"
    ERROR = "error"
    HELP = "help"

class CommandResult:
    """Standardized result from any command/operation"""
    def __init__(self, 
                 success: bool = True,
                 format: OutputFormat = OutputFormat.TEXT,
                 content: Any = None,
                 error: Optional[str] = None,
                 code: Optional[str] = None,
                 suggestion: Optional[str] = None):
        self.success = success
        self.format = format
        self.content = content
        self.error = error
        self.code = code
        self.suggestion = suggestion
    
    def to_dict(self) -> Dict:
        result = {
            "success": self.success,
            "format": self.format.value
        }
        
        if self.success:
            if self.format == OutputFormat.TEXT:
                result["content"] = self.content
            elif self.format == OutputFormat.TABLE:
                result["headers"] = self.content.get("headers", [])
                result["rows"] = self.content.get("rows", [])
            elif self.format == OutputFormat.DATA:
                result["data"] = self.content
            elif self.format == OutputFormat.STATUS:
                result["message"] = self.content.get("message", "")
                result["details"] = self.content.get("details", {})
        else:
            result["error"] = self.error
            if self.code:
                result["code"] = self.code
            if self.suggestion:
                result["suggestion"] = self.suggestion
        
        return result
    
    @classmethod
    def success_text(cls, text: str) -> 'CommandResult':
        """Create a successful text result"""
        return cls(success=True, format=OutputFormat.TEXT, content=text)
    
    @classmethod
    def success_data(cls, data: Dict) -> 'CommandResult':
        """Create a successful data result"""
        return cls(success=True, format=OutputFormat.DATA, content=data)
    
    @classmethod
    def error(cls, error: str, code: Optional[str] = None, suggestion: Optional[str] = None) -> 'CommandResult':
        """Create an error result"""
        return cls(success=False, format=OutputFormat.ERROR, error=error, code=code, suggestion=suggestion)

class Message:
    """Single message in conversation"""
    def __init__(self, role: str, content: str, timestamp: Optional[datetime] = None):
        self.role = role
        self.content = content
        self.timestamp = timestamp or datetime.now()
    
    def to_dict(self) -> Dict:
        return {
            "role": self.role,
            "content": self.content,
            "timestamp": self.timestamp.isoformat()
        }
    
    @classmethod
    def from_dict(cls, data: Dict) -> 'Message':
        timestamp = datetime.fromisoformat(data["timestamp"]) if "timestamp" in data else None
        return cls(data["role"], data["content"], timestamp)

class Conversation:
    """Manages conversation state and history"""
    def __init__(self):
        self.messages: List[Message] = []
        self.metadata = {
            "created": datetime.now(),
            "model": None,
            "session_name": None
        }
    
    def add_message(self, role: str, content: str):
        self.messages.append(Message(role, content))
    
    def get_messages_for_api(self, include_system: bool = True, max_messages: Optional[int] = None) -> List[Dict]:
        """Get messages formatted for API calls"""
        messages = self.messages
        if max_messages:
            messages = messages[-max_messages:]
        
        # Return just role and content for API
        return [{"role": msg.role, "content": msg.content} for msg in messages]
    
    def clear(self):
        self.messages = []
    
    def to_dict(self) -> Dict:
        return {
            "metadata": {
                "created": self.metadata["created"].isoformat(),
                "model": self.metadata["model"],
                "session_name": self.metadata["session_name"]
            },
            "messages": [msg.to_dict() for msg in self.messages]
        }
    
    def save(self, path: Path):
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(self.to_dict(), f, indent=2, ensure_ascii=False)
    
    @classmethod
    def load(cls, path: Path) -> 'Conversation':
        with open(path, encoding='utf-8') as f:
            data = json.load(f)
        
        conv = cls()
        conv.metadata = {
            "created": datetime.fromisoformat(data["metadata"]["created"]),
            "model": data["metadata"]["model"],
            "session_name": data["metadata"]["session_name"]
        }
        conv.messages = [Message.from_dict(msg) for msg in data["messages"]]
        return conv

class Config:
    """Configuration management"""
    def __init__(self, path: Path):
        self.path = path
        self.data = self._load()
    
    def _load(self) -> Dict:
        if self.path.exists():
            with open(self.path, encoding='utf-8') as f:
                return json.load(f)
        return {}
    
    def get(self, key: str, default=None):
        return self.data.get(key, default)
    
    def set(self, key: str, value):
        self.data[key] = value
        self.save()
    
    def save(self):
        with open(self.path, 'w', encoding='utf-8') as f:
            json.dump(self.data, f, indent=2, ensure_ascii=False)
    
    @classmethod
    def get_default_config(cls) -> Dict:
        return {
            "base_url": "http://localhost:1234",
            "model": "local-model",
            "max_tokens": 1024,
            "temperature": 0.7,
            "system_prompt": "You are a helpful assistant.",
            "stream": True,
            "timeout": 60.0,
            "max_conversation_length": 100
        }