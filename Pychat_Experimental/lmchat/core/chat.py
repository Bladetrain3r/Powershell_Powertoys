#!/usr/bin/env python3
"""
Core ChatController - Orchestrates all components
"""

import sys
from pathlib import Path
from typing import Optional

from .models import Conversation, Config
from .controllers import (
    APIController, 
    ClipboardController, 
    FileController,
    SessionController,
    CommandController
)

class ChatController:
    """Main controller that orchestrates all chat functionality"""
    
    def __init__(self, config_path: Optional[Path] = None):
        # Setup paths
        self.app_dir = Path.home() / ".lmchat"
        self.app_dir.mkdir(exist_ok=True)
        
        # Initialize configuration
        config_path = config_path or (self.app_dir / "config.json")
        self.config = Config(config_path)
        
        # Set defaults if new config
        if not self.config.data:
            self.config.data = Config.get_default_config()
            self.config.save()
        
        # Initialize controllers
        self.api = APIController(
            self.config.get("base_url", "http://localhost:1234"),
            self.config.get("timeout", 60.0)
        )
        self.clipboard = ClipboardController()
        self.file = FileController()
        self.session = SessionController(self.app_dir / "sessions")
        self.commands = CommandController()
        
        # Initialize conversation
        self.conversation = Conversation()
        
        # Register built-in commands
        self._register_builtin_commands()
    
    def _register_builtin_commands(self):
        """Register core commands"""
        # Help command
        self.commands.register_command(
            "help",
            lambda args: print(self.commands.get_help()),
            "Show available commands",
            aliases=["h", "?"]
        )
        
        # Model info command
        self.commands.register_command(
            "model",
            self._handle_model_command,
            "Show model information",
            aliases=["m"]
        )
        
        # Clear command (as slash command too)
        self.commands.register_command(
            "clear",
            lambda args: self._clear_conversation(),
            "Clear conversation history",
            aliases=["c"]
        )
        
        # Config command
        self.commands.register_command(
            "config",
            self._handle_config_command,
            "Show or set configuration"
        )
    
    def _handle_model_command(self, args: str):
        """Handle model command"""
        models = self.api.get_models()
        if models:
            print("\nAvailable models:")
            for model in models:
                print(f"  - {model['id']}")
            print(f"\nCurrent model: {self.config.get('model', 'local-model')}")
        else:
            print("Could not fetch model information")
    
    def _handle_config_command(self, args: str):
        """Handle config command"""
        if not args:
            # Show current config
            print("\nCurrent configuration:")
            for key, value in self.config.data.items():
                print(f"  {key}: {value}")
        else:
            # Parse key=value
            if '=' in args:
                key, value = args.split('=', 1)
                key = key.strip()
                value = value.strip()
                
                # Try to parse value as appropriate type
                try:
                    if value.lower() in ('true', 'false'):
                        value = value.lower() == 'true'
                    elif value.isdigit():
                        value = int(value)
                    elif '.' in value and value.replace('.', '').isdigit():
                        value = float(value)
                except:
                    pass
                
                self.config.set(key, value)
                print(f"Set {key} = {value}")
            else:
                print("Usage: /config key=value")
    
    def _clear_conversation(self):
        """Clear conversation history"""
        self.conversation.clear()
        print("Conversation cleared.")
    
    def test_connection(self) -> bool:
        """Test API connection"""
        return self.api.test_connection()
    
    def send_message(self, message: str) -> bool:
        """Send a message and handle the response"""
        # Add user message
        self.conversation.add_message("user", message)
        
        # Build messages for API
        messages = []
        
        # Add system prompt if configured
        system_prompt = self.config.get("system_prompt")
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        
        # Add conversation messages
        messages.extend(self.conversation.get_messages_for_api(
            max_messages=self.config.get("max_conversation_length", 100)
        ))
        
        # Stream response
        print("\nAssistant: ", end="", flush=True)
        assistant_response = ""
        
        try:
            for chunk in self.api.stream_completion(messages, self.config.data):
                print(chunk, end="", flush=True)
                assistant_response += chunk
            
            print()  # New line
            
            # Add assistant response to conversation
            if assistant_response:
                self.conversation.add_message("assistant", assistant_response)
            
            return True
            
        except Exception as e:
            print(f"\nError: {e}")
            return False
    
    def process_input(self, user_input: str) -> bool:
        """Process user input and return True if should continue"""
        if not user_input.strip():
            return True
        
        # Check for exit
        if user_input.lower() in ('exit', 'quit', 'bye'):
            return False
        
        # Check for built-in text commands
        if user_input.lower() == 'clear':
            self._clear_conversation()
            return True
        
        # Check for slash commands
        command, args = self.commands.parse_input(user_input)
        if command:
            if not self.commands.execute_command(command, args):
                print(f"Unknown command: /{command} (use /help)")
            return True
        
        # Regular message
        self.send_message(user_input)
        return True
    
    def register_feature(self, feature_module):
        """Register commands from a feature module"""
        if hasattr(feature_module, 'register_commands'):
            feature_module.register_commands(self)
    
    def run(self):
        """Main interaction loop - can be overridden by view"""
        print("LM Studio Chat")
        print(f"Server: {self.config.get('base_url')}")
        print("Type /help for commands, 'exit' to quit\n")
        
        while True:
            try:
                user_input = input("\nYou: ")
                if not self.process_input(user_input):
                    break
            except KeyboardInterrupt:
                print("\n\nGoodbye!")
                break
            except Exception as e:
                print(f"Error: {e}")