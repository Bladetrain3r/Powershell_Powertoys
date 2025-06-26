#!/usr/bin/env python3
"""
Clipboard Analyzer - Analyzes and summarizes clipboard content
"""

import pyperclip
from pathlib import Path
from typing import Optional, Dict, Any

# Import the base class
from classes.analyzer_base import AnalyzerBase


class ClipboardAnalyzer(AnalyzerBase):
    """Analyzes clipboard content and generates summaries using AI"""
    
    def __init__(self, **kwargs):
        """Initialize the clipboard analyzer with default name"""
        super().__init__(name="ClipboardAnalyzer", **kwargs)
        
        # Load the clipboard summary prompt
        self.prompt_template = self.load_prompt("summarization", "clipboard_summary")
        if not self.prompt_template:
            # Fallback if prompt file doesn't exist
            self.prompt_template = (
                "Concisely summarize this text. Focus on key points and main ideas. "
                "Optimize for text-to-speech delivery, no special characters "
                "(correct spoken english only), keep it brief and clear:\n\n{content}"
            )
            self.logger.warning("Using fallback prompt template")
        
        # Get config values specific to clipboard analysis
        self.max_content_length = self.get_config_value(
            "chunk_sizes", 
            "summarization/clipboard_summary", 
            8000
        )
        self.temperature = self.get_config_value(
            "temperature_settings",
            "summarization",
            0.3
        )
        self.max_tokens = self.get_config_value(
            "max_tokens",
            "summarization",
            1000
        )
    
    def get_clipboard_content(self) -> Optional[str]:
        """
        Get content from clipboard
        
        Returns:
            Clipboard content or None if empty/error
        """
        try:
            content = pyperclip.paste()
            
            if not content or content.isspace():
                self.logger.info("Clipboard is empty or contains only whitespace")
                return None
            
            self.logger.info(f"Retrieved {len(content)} characters from clipboard")
            return content
            
        except Exception as e:
            self.logger.error(f"Failed to access clipboard: {e}")
            return None
    
    def analyze(self, generate_audio: bool = True) -> Dict[str, Any]:
        """
        Analyze clipboard content
        
        Args:
            generate_audio: Whether to generate TTS audio
            
        Returns:
            Dictionary containing results and file paths
        """
        timestamp = self.get_timestamp()
        
        # Validate environment
        env_check = self.validate_environment()
        if not env_check['llm_api']:
            return {
                'success': False,
                'error': 'LLM API is not available'
            }
        
        # Get clipboard content
        clipboard_text = self.get_clipboard_content()
        if not clipboard_text:
            return {
                'success': False,
                'error': 'No valid clipboard content found'
            }
        
        # Clean text for API
        cleaned_text = self.clean_text_for_api(clipboard_text, self.max_content_length)
        
        # Format prompt
        prompt = self.format_prompt(self.prompt_template, content=cleaned_text)
        
        # Generate summary
        summary = self.call_llm_api(
            prompt,
            max_tokens=self.max_tokens,
            temperature=self.temperature
        )
        
        if not summary:
            return {
                'success': False,
                'error': 'Failed to generate summary'
            }
        
        # Save files
        try:
            original_path = self.save_text_file(
                clipboard_text, 
                "clipboard_original", 
                timestamp
            )
            summary_path = self.save_text_file(
                summary,
                "clipboard_summary",
                timestamp
            )
        except Exception as e:
            return {
                'success': False,
                'error': f'Failed to save files: {e}'
            }
        
        # Copy summary to clipboard
        try:
            pyperclip.copy(summary)
            self.logger.info("Summary copied to clipboard")
        except Exception as e:
            self.logger.warning(f"Failed to copy summary to clipboard: {e}")
        
        # Generate audio if requested
        audio_path = None
        if generate_audio and env_check.get('tts_api', False):
            audio_file = self.output_dir / f"clipboard_summary_{timestamp}.mp3"
            if self.generate_tts_audio(summary, audio_file):
                audio_path = audio_file
        
        return {
            'success': True,
            'original_length': len(clipboard_text),
            'summary': summary,
            'original_path': str(original_path),
            'summary_path': str(summary_path),
            'audio_path': str(audio_path) if audio_path else None,
            'timestamp': timestamp
        }


def main():
    """Example usage"""
    # Create analyzer instance
    analyzer = ClipboardAnalyzer()
    
    # Run analysis
    print("Analyzing clipboard content...")
    results = analyzer.analyze(generate_audio=True)
    
    if results['success']:
        print(f"\nAnalysis successful!")
        print(f"Original length: {results['original_length']} characters")
        print(f"Summary: {results['summary']}")
        print(f"\nFiles saved:")
        print(f"- Original: {results['original_path']}")
        print(f"- Summary: {results['summary_path']}")
        if results['audio_path']:
            print(f"- Audio: {results['audio_path']}")
    else:
        print(f"\nAnalysis failed: {results['error']}")


if __name__ == "__main__":
    main()