#!/usr/bin/env python3
"""
LM Studio Chat - Main entry point
"""

import sys
import os
from pathlib import Path


# Add parent directory to path for development
sys.path.insert(0, str(Path(__file__).parent))
from lmchat.core.chat import ChatController
from lmchat.features import clipboard, file_input


def main():
    """Main entry point"""
    # Clear screen
    os.system('cls' if os.name == 'nt' else 'clear')
    
    # ASCII art header (optional)
    print("""
    ╔═══════════════════════════════╗
    ║     LM Studio Chat Client     ║
    ╚═══════════════════════════════╝
    """)
    
    # Initialize chat controller
    chat = ChatController()
    
    # Test connection
    print("Connecting to LM Studio...", end="", flush=True)
    if not chat.test_connection():
        print(" FAILED")
        print(f"\nCannot connect to LM Studio at {chat.config.get('base_url')}")
        print("Make sure LM Studio is running with the local server enabled.")
        sys.exit(1)
    print(" OK")
    
    # Register feature modules
    chat.register_feature(clipboard)
    chat.register_feature(file_input)
    
    # Show basic info
    print(f"\nServer: {chat.config.get('base_url')}")
    print(f"Model: {chat.config.get('model', 'local-model')}")
    print(f"Temperature: {chat.config.get('temperature', 0.7)}")
    print("\nType /help for commands, 'exit' to quit")
    print("-" * 40)
    
    # Main interaction loop
    while True:
        try:
            # Custom prompt with color (if terminal supports it)
            if sys.platform != 'win32':
                prompt = "\n\033[93mYou:\033[0m "  # Yellow color
            else:
                prompt = "\nYou: "
            
            user_input = input(prompt)
            
            # Process input
            if not chat.process_input(user_input):
                print("\nGoodbye! 👋")
                break
                
        except KeyboardInterrupt:
            print("\n\nInterrupted. Goodbye! 👋")
            break
        except EOFError:
            # Handle Ctrl+D
            print("\n\nGoodbye! 👋")
            break
        except Exception as e:
            print(f"\nUnexpected error: {e}")
            print("Type 'exit' to quit or press Enter to continue...")

if __name__ == "__main__":
    main()