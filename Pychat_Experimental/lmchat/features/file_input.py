#!/usr/bin/env python3
"""
File input feature - adds file reading commands
"""

from pathlib import Path

def create_file_handler(chat_controller):
    """Create file command handler"""
    def handle_file(args: str):
        if not args:
            print("Usage: /file <path> [optional prompt]")
            return
        
        # Parse args - first word is path, rest is prompt
        parts = args.split(' ', 1)
        file_path = Path(parts[0])
        prompt = parts[1] if len(parts) > 1 else ""
        
        # Check if file exists
        if not file_path.exists():
            print(f"File not found: {file_path}")
            return
        
        # Read file
        content = chat_controller.file.read_file(file_path)
        if not content:
            return
        
        # Detect language
        language = chat_controller.file.detect_language(file_path)
        
        # Build message
        if language:
            file_header = f"```{language}\n{content}\n```"
        else:
            file_header = f"```\n{content}\n```"
        
        if prompt:
            message = f"{prompt}\n\n{file_header}"
        else:
            message = f"File: {file_path.name}\n\n{file_header}"
        
        print(f"Sending {file_path.name}...")
        chat_controller.send_message(message)
    
    return handle_file

def register_commands(chat_controller):
    """Register file commands with the chat controller"""
    chat_controller.commands.register_command(
        "file",
        create_file_handler(chat_controller),
        "Read and send file content",
        aliases=["f", "read"]
    )