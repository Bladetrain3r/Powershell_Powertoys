#!/usr/bin/env python3
"""
Base Analyzer Class - Core functionality for all analyzers
"""

import requests
import json
from pathlib import Path
import datetime
import logging
from typing import Optional, Dict, Any, Tuple, List
import time
from abc import ABC, abstractmethod


class AnalyzerBase(ABC):
    """Base class for all analyzer implementations"""
    
    def __init__(
        self,
        name: str,
        api_endpoint: str = None,
        model_name: str = None,
        output_dir: Path = None,
        prompts_dir: Path = None,
        tts_endpoint: str = None,
        tts_model: str = None,
        tts_voice: str = None,
        log_level: str = None
    ):
        """
        Initialize the base analyzer
        
        Args:
            name: Name of the analyzer (for logging/output)
            api_endpoint: LLM API endpoint (None = use config)
            model_name: Model to use for analysis (None = use config)
            output_dir: Directory for saving outputs (None = use config)
            prompts_dir: Directory containing prompt templates (None = use config)
            tts_endpoint: TTS API endpoint (None = use config)
            tts_model: TTS model name (None = use config)
            tts_voice: TTS voice selection (None = use config)
            log_level: Logging level (None = use config)
        """
        self.name = name
        
        # Load configuration first - this will raise if config is invalid
        self.prompts_dir = prompts_dir or Path("prompts")
        self.config = self._load_config()
        
        # Get values from config, use parameters as overrides
        defaults = self.config.get('defaults')
        if not defaults:
            raise ValueError("Config missing 'defaults' section")
        
        # Set values - either from parameters or config (required)
        self.api_endpoint = api_endpoint or defaults.get('api_endpoint')
        self.model_name = model_name or defaults.get('model_name')
        self.tts_endpoint = tts_endpoint or defaults.get('tts_endpoint')
        self.tts_model = tts_model or defaults.get('tts_model')
        self.tts_voice = tts_voice or defaults.get('tts_voice')
        
        # Validate required configuration
        if not self.api_endpoint:
            raise ValueError("api_endpoint not specified in config or parameters")
        if not self.model_name:
            raise ValueError("model_name not specified in config or parameters")
        if not self.tts_endpoint:
            raise ValueError("tts_endpoint not specified in config or parameters")
        if not self.tts_model:
            raise ValueError("tts_model not specified in config or parameters")
        if not self.tts_voice:
            raise ValueError("tts_voice not specified in config or parameters")
        
        # Handle output_dir specially (can use Path.home() as fallback)
        output_dir_str = output_dir or defaults.get('output_dir')
        if output_dir_str:
            if output_dir_str.startswith('~'):
                self.output_dir = Path(output_dir_str).expanduser()
            else:
                self.output_dir = Path(output_dir_str)
        else:
            raise ValueError("output_dir not specified in config or parameters")
        
        # Setup logging with config value
        log_level_final = log_level or defaults.get('log_level')
        if not log_level_final:
            raise ValueError("log_level not specified in config or parameters")
        
        self._setup_logging(log_level_final)
        
        # Ensure directories exist
        try:
            self.output_dir.mkdir(parents=True, exist_ok=True)
        except Exception as e:
            raise ValueError(f"Cannot create output directory {self.output_dir}: {e}")
        
        # Prompt cache
        self._prompt_cache = {}
        
        # API retry settings
        self.max_retries = 3
        self.retry_delay = 1.0
    
    def _setup_logging(self, log_level: str):
        """Setup logging configuration"""
        log_dir = Path("logs")
        log_dir.mkdir(exist_ok=True)
        
        # Create logger
        self.logger = logging.getLogger(f"{self.__class__.__name__}.{self.name}")
        self.logger.setLevel(getattr(logging, log_level.upper()))
        
        # File handler
        file_handler = logging.FileHandler(
            log_dir / f'{self.name.lower().replace(" ", "_")}.log'
        )
        file_handler.setLevel(logging.DEBUG)
        
        # Console handler
        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.INFO)
        
        # Formatter
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        file_handler.setFormatter(formatter)
        console_handler.setFormatter(formatter)
        
        # Add handlers
        self.logger.addHandler(file_handler)
        self.logger.addHandler(console_handler)
    
    def _load_config(self) -> Dict[str, Any]:
        """Load configuration from templates - strict mode"""
        config_path = self.prompts_dir / "templates" / "config.json"
        
        if not config_path.exists():
            raise FileNotFoundError(
                f"Config file not found at {config_path}. "
                "Please run create_project_structure.py to initialize the project."
            )
        
        try:
            with open(config_path, 'r') as f:
                config = json.load(f)
            
            # Validate required sections
            required_sections = ['defaults', 'chunk_sizes', 'temperature_settings', 'max_tokens']
            missing_sections = [s for s in required_sections if s not in config]
            
            if missing_sections:
                raise ValueError(
                    f"Config file missing required sections: {', '.join(missing_sections)}"
                )
            
            # Validate defaults section has required fields
            defaults = config.get('defaults', {})
            required_defaults = [
                'api_endpoint', 'model_name', 'output_dir', 
                'tts_endpoint', 'tts_model', 'tts_voice', 'log_level'
            ]
            missing_defaults = [d for d in required_defaults if d not in defaults]
            
            if missing_defaults:
                raise ValueError(
                    f"Config 'defaults' section missing required fields: {', '.join(missing_defaults)}"
                )
            
            return config
            
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in config file: {e}")
        except Exception as e:
            raise ValueError(f"Failed to load config: {e}")
    
    def load_prompt(self, category: str, name: str) -> Optional[str]:
        """
        Load a prompt template from file
        
        Args:
            category: Prompt category (e.g., 'analysis', 'summarization')
            name: Prompt name
            
        Returns:
            Prompt template or None if not found
        """
        cache_key = f"{category}/{name}"
        
        # Check cache first
        if cache_key in self._prompt_cache:
            return self._prompt_cache[cache_key]
        
        prompt_path = self.prompts_dir / category / f"{name}.txt"
        
        if not prompt_path.exists():
            self.logger.error(f"Prompt not found: {prompt_path}")
            return None
        
        try:
            content = prompt_path.read_text(encoding='utf-8')
            self._prompt_cache[cache_key] = content
            self.logger.debug(f"Loaded prompt: {cache_key}")
            return content
        except Exception as e:
            self.logger.error(f"Failed to load prompt {prompt_path}: {e}")
            return None
    
    def format_prompt(self, template: str, **kwargs) -> str:
        """
        Format a prompt template with variables
        
        Args:
            template: Prompt template string
            **kwargs: Variables to substitute
            
        Returns:
            Formatted prompt
        """
        try:
            # Use format_map for safer formatting (won't fail on extra keys)
            return template.format_map(kwargs)
        except KeyError as e:
            self.logger.error(f"Missing prompt variable: {e}")
            raise
        except Exception as e:
            self.logger.error(f"Prompt formatting error: {e}")
            raise
    
    def get_config_value(self, config_type: str, key: str, default: Any = None) -> Any:
        """
        Get a configuration value
        
        Args:
            config_type: Type of config (e.g., 'chunk_sizes', 'temperature_settings')
            key: Specific key within that type
            default: Default value if not found
            
        Returns:
            Configuration value
        """
        return self.config.get(config_type, {}).get(key, default)
    
    def clean_text_for_api(self, text: str, max_length: Optional[int] = None) -> str:
        """
        Clean text for safe API transmission
        
        Args:
            text: Raw text to clean
            max_length: Maximum length (uses config default if None)
            
        Returns:
            Cleaned text safe for JSON
        """
        # Remove control characters except newlines and tabs
        cleaned = ''.join(
            char if ord(char) >= 32 or char in '\n\t' 
            else ' ' for char in text
        )
        
        # Normalize whitespace
        lines = cleaned.split('\n')
        cleaned_lines = [' '.join(line.split()) for line in lines]
        cleaned = '\n'.join(cleaned_lines)
        
        # Get max length from config if not specified
        if max_length is None:
            max_length = 8000  # Safe default
        
        # Truncate if necessary
        if len(cleaned) > max_length:
            # Try to truncate at a word boundary
            truncated = cleaned[:max_length]
            last_space = truncated.rfind(' ')
            if last_space > max_length - 100:  # Within 100 chars of end
                truncated = truncated[:last_space]
            cleaned = truncated + "... [truncated]"
            self.logger.info(f"Truncated content to {len(cleaned)} characters")
        
        return cleaned
    
    def call_llm_api(
        self, 
        prompt: str, 
        max_tokens: Optional[int] = None,
        temperature: Optional[float] = None,
        model_override: Optional[str] = None
    ) -> Optional[str]:
        """
        Call the LLM API for text generation with retry logic
        
        Args:
            prompt: The prompt to send
            max_tokens: Maximum tokens to generate
            temperature: Temperature for generation
            model_override: Override the default model
            
        Returns:
            Generated text or None if error
        """
        model = model_override or self.model_name
        
        # Use defaults from config if not specified
        if max_tokens is None:
            max_tokens = 1000
        if temperature is None:
            temperature = 0.3
        
        payload = {
            "model": model,
            "messages": [{
                "role": "user",
                "content": prompt
            }],
            "max_tokens": max_tokens,
            "temperature": temperature
        }
        
        for attempt in range(self.max_retries):
            try:
                self.logger.debug(f"Calling LLM API (attempt {attempt + 1}/{self.max_retries})")
                
                response = requests.post(
                    f"{self.api_endpoint}/v1/chat/completions",
                    json=payload,
                    timeout=30
                )
                response.raise_for_status()
                
                data = response.json()
                content = data['choices'][0]['message']['content']
                
                self.logger.info(f"LLM API call successful (model: {model})")
                return content.strip()
                
            except requests.exceptions.Timeout:
                self.logger.warning(f"LLM API timeout (attempt {attempt + 1})")
            except requests.exceptions.RequestException as e:
                self.logger.warning(f"LLM API request failed (attempt {attempt + 1}): {e}")
            except (KeyError, IndexError) as e:
                self.logger.error(f"Invalid API response format: {e}")
                return None  # Don't retry on parse errors
            
            if attempt < self.max_retries - 1:
                time.sleep(self.retry_delay * (attempt + 1))
        
        self.logger.error(f"LLM API failed after {self.max_retries} attempts")
        return None
    
    def generate_tts_audio(
        self, 
        text: str, 
        output_path: Path,
        max_length: int = 2000
    ) -> bool:
        """
        Generate TTS audio from text
        
        Args:
            text: Text to convert to speech
            output_path: Path to save audio file
            max_length: Maximum text length for TTS
            
        Returns:
            True if successful, False otherwise
        """
        # Limit text length for TTS
        tts_text = text[:max_length]
        if len(text) > max_length:
            tts_text += "..."
            self.logger.info(f"Truncated TTS text to {max_length} characters")
        
        payload = {
            "model": self.tts_model,
            "input": tts_text,
            "voice": self.tts_voice,
            "response_format": "mp3",
            "speed": 1.0,
            "stream": False
        }
        
        try:
            self.logger.debug(f"Calling TTS API")
            
            response = requests.post(
                f"{self.tts_endpoint}/v1/audio/speech",
                json=payload,
                timeout=60
            )
            response.raise_for_status()
            
            # Save audio file
            output_path.write_bytes(response.content)
            self.logger.info(f"Generated audio saved to {output_path}")
            return True
            
        except requests.exceptions.Timeout:
            self.logger.error("TTS API request timed out")
        except requests.exceptions.RequestException as e:
            self.logger.error(f"TTS API request failed: {e}")
        except Exception as e:
            self.logger.error(f"Failed to save audio file: {e}")
        
        return False
    
    def save_text_file(
        self, 
        content: str, 
        filename_prefix: str, 
        timestamp: str,
        subfolder: Optional[str] = None
    ) -> Path:
        """
        Save text content to a file
        
        Args:
            content: Text content to save
            filename_prefix: Prefix for the filename
            timestamp: Timestamp string
            subfolder: Optional subfolder within output_dir
            
        Returns:
            Path to saved file
        """
        if subfolder:
            output_dir = self.output_dir / subfolder
            output_dir.mkdir(parents=True, exist_ok=True)
        else:
            output_dir = self.output_dir
        
        filename = f"{filename_prefix}_{timestamp}.txt"
        file_path = output_dir / filename
        
        try:
            file_path.write_text(content, encoding='utf-8')
            self.logger.info(f"Saved {filename_prefix} to {file_path}")
            return file_path
        except Exception as e:
            self.logger.error(f"Failed to save {filename}: {e}")
            raise
    
    def get_timestamp(self) -> str:
        """Get formatted timestamp string"""
        return datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    
    def check_api_health(self, endpoint: str, timeout: int = 5) -> bool:
        """
        Check if an API endpoint is healthy
        
        Args:
            endpoint: API endpoint base URL
            timeout: Request timeout
            
        Returns:
            True if healthy, False otherwise
        """
        try:
            response = requests.get(f"{endpoint}/v1/models", timeout=timeout)
            return response.status_code == 200
        except:
            return False
    
    @abstractmethod
    def analyze(self, **kwargs) -> Dict[str, Any]:
        """
        Main analysis method - must be implemented by subclasses
        
        Returns:
            Dictionary containing analysis results
        """
        pass
    
    def validate_environment(self) -> Dict[str, bool]:
        """
        Validate that all required services are available
        
        Returns:
            Dictionary of service availability
        """
        results = {
            'llm_api': self.check_api_health(self.api_endpoint),
            'tts_api': self.check_api_health(self.tts_endpoint),
            'output_dir_writable': self._check_output_dir_writable(),
            'prompts_dir_exists': self.prompts_dir.exists()
        }
        
        for service, available in results.items():
            if available:
                self.logger.debug(f"{service}: Available")
            else:
                self.logger.warning(f"{service}: Not available")
        
        return results
    
    def _check_output_dir_writable(self) -> bool:
        """Check if output directory is writable"""
        try:
            test_file = self.output_dir / f".test_{self.get_timestamp()}"
            test_file.write_text("test")
            test_file.unlink()
            return True
        except:
            return False