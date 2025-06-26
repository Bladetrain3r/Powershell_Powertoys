#!/usr/bin/env python3
"""
Screenshot Analyzer - Captures and analyzes screenshots with context and OCR
"""

from pathlib import Path
from typing import Optional, Dict, Any
import base64
import requests
import time

# Import base class only
from classes.analyzer_base import AnalyzerBase


class ScreenshotAnalyzer(AnalyzerBase):
    """Analyzes screenshots with system context and OCR"""
    
    def __init__(self, **kwargs):
        """Initialize the screenshot analyzer"""
        super().__init__(name="ScreenshotAnalyzer", **kwargs)
        
        # Lazy import to avoid circular dependency
        from classes.capture import Capture
        
        # Initialize capture utility
        self.capture = Capture(output_dir=self.output_dir, logger=self.logger)
        
        # Load prompts
        self.context_prompt = self.load_prompt("analysis", "screenshot_context")
        self.vision_prompt = self.load_prompt("analysis", "screenshot_vision")
        self.summary_prompt = self.load_prompt("summarization", "tts_summary")
        
        if not self.context_prompt:
            self.logger.error("Failed to load screenshot context prompt")
            raise ValueError("Required prompt template not found")
        
        # Get config values
        self.max_context_length = self.get_config_value(
            "chunk_sizes",
            "analysis/screenshot_context",
            12000
        )
        self.analysis_temperature = self.get_config_value(
            "temperature_settings",
            "analysis",
            0.2
        )
        self.analysis_max_tokens = self.get_config_value(
            "max_tokens",
            "analysis",
            2500
        )
        self.summary_temperature = self.get_config_value(
            "temperature_settings",
            "summarization",
            0.2
        )
        self.summary_max_tokens = self.get_config_value(
            "max_tokens",
            "summarization",
            800
        )
        
        # Check for vision-specific model in config
        self.vision_model = self.get_config_value(
            "defaults",
            "vision_model",
            self.model_name  # Use base model if no vision-specific model
        )
        self.logger.info(f"Using vision model: {self.vision_model}")
    
    def analyze(
        self,
        monitor: int = 1,
        save_all_files: bool = True,
        generate_audio: bool = True,
        include_ocr: bool = True,
        include_context: bool = True
    ) -> Dict[str, Any]:
        """
        Analyze screenshot with context and OCR
        
        Args:
            monitor: Monitor number to capture
            save_all_files: Save all intermediate files
            generate_audio: Generate TTS audio summary
            include_ocr: Perform OCR on screenshot
            include_context: Include system context in analysis
            
        Returns:
            Dictionary containing analysis results
        """
        timestamp = self.get_timestamp()
        
        # Validate environment
        env_check = self.validate_environment()
        if not env_check['llm_api']:
            return {
                'success': False,
                'error': 'LLM API is not available',
                'timestamp': timestamp
            }
        
        self.logger.info("Starting screenshot analysis...")
        
        # Gather system context if requested
        context_data = {}
        if include_context:
            context_data = self._gather_context()
        
        # Capture screenshot with optional OCR
        if include_ocr:
            screenshot_data = self.capture.capture_screenshot_with_ocr(
                monitor=monitor,
                save_screenshot=save_all_files,
                save_ocr_text=save_all_files
            )
        else:
            screenshot_data = self.capture.capture_screenshot(
                monitor=monitor,
                save_to_file=save_all_files
            )
        
        if not screenshot_data.get('success'):
            return {
                'success': False,
                'error': 'Failed to capture screenshot',
                'timestamp': timestamp
            }
        
        # Prepare image for vision API
        image = screenshot_data.get('image')
        if not image:
            return {
                'success': False,
                'error': 'No image captured',
                'timestamp': timestamp
            }
        
        image_base64 = self.capture.image_to_base64(image)
        
        # Perform contextual analysis
        analysis = self._perform_contextual_analysis(
            image_base64,
            screenshot_data.get('ocr_text', ''),
            context_data
        )
        
        if not analysis:
            return {
                'success': False,
                'error': 'Failed to analyze screenshot',
                'timestamp': timestamp
            }
        
        # Generate summary for TTS
        summary = self._generate_summary(analysis)
        
        # Save analysis results
        file_paths = {}
        if save_all_files:
            try:
                # Save context
                if context_data:
                    context_path = self.save_text_file(
                        self._format_context_data(context_data),
                        "context",
                        timestamp
                    )
                    file_paths['context'] = str(context_path)
                
                # Save analysis
                analysis_path = self.save_text_file(
                    analysis,
                    "analysis",
                    timestamp
                )
                file_paths['analysis'] = str(analysis_path)
                
                # Save summary
                if summary:
                    summary_path = self.save_text_file(
                        summary,
                        "summary",
                        timestamp
                    )
                    file_paths['summary'] = str(summary_path)
                    
            except Exception as e:
                self.logger.error(f"Failed to save files: {e}")
        
        # Generate audio if requested
        audio_path = None
        if generate_audio and summary and env_check.get('tts_api', False):
            audio_file = self.output_dir / f"screenshot_analysis_{timestamp}.mp3"
            if self.generate_tts_audio(summary, audio_file):
                audio_path = audio_file
                file_paths['audio'] = str(audio_path)
        
        return {
            'success': True,
            'timestamp': timestamp,
            'screenshot_path': str(screenshot_data.get('path')) if screenshot_data.get('path') else None,
            'ocr_text_length': len(screenshot_data.get('ocr_text', '')),
            'ocr_path': str(screenshot_data.get('ocr_path')) if screenshot_data.get('ocr_path') else None,
            'analysis': analysis,
            'summary': summary,
            'file_paths': file_paths,
            'context': context_data
        }
    
    def _gather_context(self) -> Dict[str, Any]:
        """Gather system context information"""
        self.logger.info("Gathering system context...")
        
        context = {
            'active_window': self.capture.get_active_window_info(),
            'clipboard_preview': self._get_clipboard_preview(),
            'top_processes': self.capture.get_top_processes(count=3, sort_by='cpu')
        }
        
        return context
    
    def _get_clipboard_preview(self, max_length: int = 200) -> str:
        """Get a preview of clipboard content"""
        clipboard = self.capture.capture_clipboard()
        
        if not clipboard:
            return "Empty"
        
        if len(clipboard) > max_length:
            return clipboard[:max_length] + "..."
        
        return clipboard
    
    def _format_context_data(self, context_data: Dict[str, Any]) -> str:
        """Format context data for saving"""
        lines = [
            f"CONTEXT INFORMATION - {self.get_timestamp()}",
            f"Active Window: {context_data['active_window']['title']} ({context_data['active_window']['process']})",
            f"Clipboard: {context_data['clipboard_preview']}",
            "",
            "Top Processes:"
        ]
        
        for proc in context_data['top_processes']:
            lines.append(f"- {proc['name']}: {proc['cpu_percent']}% CPU")
        
        return "\n".join(lines)
    
    def _perform_contextual_analysis(
        self,
        image_base64: str,
        ocr_text: str,
        context_data: Dict[str, Any]
    ) -> Optional[str]:
        """Perform contextual analysis using vision model"""
        self.logger.info("Performing contextual analysis...")
        
        # Format the prompt with context
        prompt_vars = {
            'current_time': self.get_timestamp(),
            'active_window': context_data.get('active_window', {}).get('title', 'Unknown'),
            'active_process': context_data.get('active_window', {}).get('process', 'Unknown'),
            'clipboard_preview': context_data.get('clipboard_preview', 'Empty'),
            'extracted_text': ocr_text or 'No text detected',
            'ocr_text': ocr_text or 'No text detected'
        }
        
        # Use context prompt if we have context, otherwise vision prompt
        if context_data:
            prompt_template = self.context_prompt
        else:
            prompt_template = self.vision_prompt
        
        prompt = self.format_prompt(prompt_template, **prompt_vars)
        
        # Clean prompt for API
        prompt = self.clean_text_for_api(prompt, self.max_context_length)
        
        # Call vision-capable API with base64 image - exactly like PowerShell script
        analysis = self._call_vision_api(
            prompt,
            image_base64,
            max_tokens=self.analysis_max_tokens,
            temperature=self.analysis_temperature
        )
        
        return analysis
    
    def _generate_summary(self, analysis: str) -> Optional[str]:
        """Generate a concise summary suitable for TTS"""
        if not analysis or not self.summary_prompt:
            return None
        
        self.logger.info("Generating summary for TTS...")
        
        prompt = self.format_prompt(
            self.summary_prompt,
            content=analysis
        )
        
        summary = self.call_llm_api(
            prompt,
            max_tokens=self.summary_max_tokens,
            temperature=self.summary_temperature
        )
        
        return summary
    
    def _call_vision_api(
        self,
        prompt: str,
        image_base64: str,
        max_tokens: int,
        temperature: float
    ) -> Optional[str]:
        """Call vision-capable API with image - matches PowerShell implementation"""
        # Log image info for debugging
        self.logger.info(f"Preparing vision API call with image ({len(image_base64)} base64 chars)")
        
        payload = {
            "model": self.vision_model,  # Use vision-specific model
            "messages": [{
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": prompt
                    },
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/png;base64,{image_base64}"
                        }
                    }
                ]
            }],
            "max_tokens": max_tokens,
            "temperature": temperature
        }
        
        self.logger.debug(f"Vision API payload structure: text + image_url")
        
        # Use the base class API call method with retry logic
        for attempt in range(self.max_retries):
            try:
                self.logger.debug(f"Calling vision API at {self.api_endpoint}/v1/chat/completions (attempt {attempt + 1}/{self.max_retries})")
                
                response = requests.post(
                    f"{self.api_endpoint}/v1/chat/completions",
                    json=payload,
                    timeout=30
                )
                response.raise_for_status()
                
                data = response.json()
                content = data['choices'][0]['message']['content']
                
                self.logger.info(f"Vision API call successful - received {len(content)} chars")
                return content.strip()
                
            except Exception as e:
                self.logger.warning(f"Vision API attempt {attempt + 1} failed: {e}")
                if attempt < self.max_retries - 1:
                    time.sleep(self.retry_delay * (attempt + 1))
        
        self.logger.error("Vision API failed after all attempts")
        return None


def main():
    """Example usage"""
    # Create analyzer
    analyzer = ScreenshotAnalyzer()
    
    print("Capturing and analyzing screenshot...")
    
    # Run analysis
    results = analyzer.analyze(
        monitor=1,
        save_all_files=True,
        generate_audio=True,
        include_ocr=True,
        include_context=True
    )
    
    if results['success']:
        print(f"\nAnalysis successful!")
        print(f"Timestamp: {results['timestamp']}")
        print(f"Screenshot: {results['screenshot_path']}")
        print(f"OCR extracted: {results['ocr_text_length']} characters")
        print(f"\nAnalysis preview:")
        print(results['analysis'][:500] + "..." if len(results['analysis']) > 500 else results['analysis'])
        
        if results.get('summary'):
            print(f"\nSummary: {results['summary']}")
        
        print(f"\nFiles saved:")
        for file_type, path in results['file_paths'].items():
            print(f"- {file_type}: {path}")
    else:
        print(f"\nAnalysis failed: {results['error']}")


if __name__ == "__main__":
    main()