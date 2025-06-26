#!/usr/bin/env python3
"""
Capture Class - Utilities for capturing current system state
Handles clipboard, screenshots, OCR, and process information
"""

import pyperclip
import mss
import pytesseract
import psutil
from PIL import Image
from pathlib import Path
import datetime
import logging
from typing import Optional, Dict, Any, List, Tuple
import io
import base64
import platform


class Capture:
    """Captures various aspects of current system state"""
    
    def __init__(self, output_dir: Path = None, logger: logging.Logger = None):
        """
        Initialize capture utilities
        
        Args:
            output_dir: Directory for saving captures
            logger: Logger instance (creates one if not provided)
        """
        self.output_dir = output_dir or Path.home() / "Screenshots"
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        # Setup logging
        if logger:
            self.logger = logger
        else:
            logging.basicConfig(level=logging.INFO)
            self.logger = logging.getLogger(self.__class__.__name__)
        
        # Check for required tools
        self._check_dependencies()
    
    def _check_dependencies(self):
        """Check if required dependencies are available"""
        # Check Tesseract
        try:
            # Try common Windows paths first
            import platform
            if platform.system() == 'Windows':
                common_paths = [
                    r'C:\Program Files\Tesseract-OCR\tesseract.exe',
                    r'C:\Program Files (x86)\Tesseract-OCR\tesseract.exe',
                    r'C:\Users\AppData\Local\Tesseract-OCR\tesseract.exe',
                ]
                for path in common_paths:
                    if Path(path).exists():
                        pytesseract.pytesseract.tesseract_cmd = path
                        self.logger.info(f"Found Tesseract at: {path}")
                        break
            
            # Test if Tesseract works
            pytesseract.get_tesseract_version()
            self.tesseract_available = True
            self.logger.debug("Tesseract OCR is available")
        except Exception as e:
            self.tesseract_available = False
            self.logger.warning(
                f"Tesseract OCR not available: {e}\n"
                "To install Tesseract:\n"
                "- Windows: Download from https://github.com/UB-Mannheim/tesseract/wiki\n"
                "- Mac: brew install tesseract\n"
                "- Linux: sudo apt-get install tesseract-ocr"
            )
    
    def get_timestamp(self) -> str:
        """Get formatted timestamp string"""
        return datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    
    def capture_clipboard(self) -> Optional[str]:
        """
        Capture current clipboard content
        
        Returns:
            Clipboard text content or None if empty/error
        """
        try:
            content = pyperclip.paste()
            
            if not content or content.isspace():
                self.logger.debug("Clipboard is empty")
                return None
            
            self.logger.info(f"Captured {len(content)} characters from clipboard")
            return content
            
        except Exception as e:
            self.logger.error(f"Failed to capture clipboard: {e}")
            return None
    
    def capture_screenshot(
        self, 
        monitor: int = 1,
        save_to_file: bool = True,
        filename_prefix: str = "screenshot"
    ) -> Dict[str, Any]:
        """
        Capture screenshot of specified monitor
        
        Args:
            monitor: Monitor number (1 = primary)
            save_to_file: Whether to save screenshot to file
            filename_prefix: Prefix for saved file
            
        Returns:
            Dict with 'image' (PIL Image), 'path' (if saved), 'timestamp'
        """
        timestamp = self.get_timestamp()
        result = {'timestamp': timestamp, 'success': False}
        
        try:
            with mss.mss() as sct:
                # Get monitor info
                monitor_info = sct.monitors[monitor]
                
                # Capture screenshot
                screenshot = sct.grab(monitor_info)
                
                # Convert to PIL Image
                img = Image.frombytes(
                    "RGB", 
                    screenshot.size, 
                    screenshot.bgra, 
                    "raw", 
                    "BGRX"
                )
                
                result['image'] = img
                result['size'] = img.size
                result['success'] = True
                
                # Save if requested
                if save_to_file:
                    filename = f"{filename_prefix}_{timestamp}.png"
                    filepath = self.output_dir / filename
                    img.save(filepath)
                    result['path'] = filepath
                    self.logger.info(f"Screenshot saved to {filepath}")
                
                self.logger.info(f"Captured screenshot: {img.size[0]}x{img.size[1]}")
                
        except Exception as e:
            self.logger.error(f"Failed to capture screenshot: {e}")
            result['error'] = str(e)
        
        return result
    
    def perform_ocr(
        self, 
        image: Image.Image,
        lang: str = 'eng',
        config: str = '--psm 3'
    ) -> Optional[str]:
        """
        Perform OCR on an image using Tesseract
        
        Args:
            image: PIL Image object
            lang: Language for OCR
            config: Tesseract config string
            
        Returns:
            Extracted text or None if OCR fails
        """
        if not self.tesseract_available:
            self.logger.warning("Tesseract not available, skipping OCR")
            return None
        
        try:
            # Perform OCR
            text = pytesseract.image_to_string(image, lang=lang, config=config)
            
            # Clean up text
            text = text.strip()
            
            if text:
                self.logger.info(f"OCR extracted {len(text)} characters")
            else:
                self.logger.info("OCR found no text")
            
            return text if text else None
            
        except Exception as e:
            self.logger.error(f"OCR failed: {e}")
            return None
    
    def capture_screenshot_with_ocr(
        self,
        monitor: int = 1,
        save_screenshot: bool = True,
        save_ocr_text: bool = True
    ) -> Dict[str, Any]:
        """
        Capture screenshot and perform OCR in one operation
        
        Args:
            monitor: Monitor number
            save_screenshot: Save screenshot file
            save_ocr_text: Save OCR text file
            
        Returns:
            Dict with screenshot info and OCR text
        """
        # Capture screenshot
        screenshot_result = self.capture_screenshot(
            monitor=monitor,
            save_to_file=save_screenshot
        )
        
        if not screenshot_result.get('success'):
            return screenshot_result
        
        # Perform OCR
        image = screenshot_result.get('image')
        if image:
            ocr_text = self.perform_ocr(image)
            screenshot_result['ocr_text'] = ocr_text
            
            # Save OCR text if requested
            if save_ocr_text and ocr_text:
                timestamp = screenshot_result['timestamp']
                ocr_path = self.output_dir / f"ocr_{timestamp}.txt"
                ocr_path.write_text(ocr_text, encoding='utf-8')
                screenshot_result['ocr_path'] = ocr_path
                self.logger.info(f"OCR text saved to {ocr_path}")
        
        return screenshot_result
    
    def get_active_window_info(self) -> Dict[str, Any]:
        """
        Get information about the currently active window
        
        Returns:
            Dict with window title, process name, PID
        """
        # Try Windows-specific method first
        if platform.system() == 'Windows':
            try:
                import ctypes
                from ctypes import wintypes
                
                # Get foreground window
                user32 = ctypes.windll.user32
                kernel32 = ctypes.windll.kernel32
                
                hwnd = user32.GetForegroundWindow()
                
                # Get window title
                window_title_length = user32.GetWindowTextLengthW(hwnd) + 1
                window_title = ctypes.create_unicode_buffer(window_title_length)
                user32.GetWindowTextW(hwnd, window_title, window_title_length)
                title = window_title.value
                
                # Get process ID
                pid = wintypes.DWORD()
                user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
                
                # Get process name
                try:
                    process = psutil.Process(pid.value)
                    process_name = process.name()
                except:
                    process_name = "Unknown"
                
                return {
                    'title': title or "No Title",
                    'process': process_name,
                    'pid': pid.value,
                    'bounds': None  # Could add window bounds if needed
                }
                
            except Exception as e:
                self.logger.debug(f"Windows API method failed: {e}")
        
        # Try pygetwindow method
        try:
            import pygetwindow as gw
            
            # Get active window
            active_window = gw.getActiveWindow()
            
            if active_window:
                # Try to get process info
                try:
                    # This is platform-specific, might need adjustment
                    for proc in psutil.process_iter(['pid', 'name']):
                        if active_window.title in proc.name():
                            return {
                                'title': active_window.title,
                                'process': proc.name(),
                                'pid': proc.pid,
                                'bounds': {
                                    'left': active_window.left,
                                    'top': active_window.top,
                                    'width': active_window.width,
                                    'height': active_window.height
                                }
                            }
                except:
                    pass
                
                # Fallback if we can't match process
                return {
                    'title': active_window.title,
                    'process': 'Unknown',
                    'pid': None,
                    'bounds': {
                        'left': active_window.left,
                        'top': active_window.top,
                        'width': active_window.width,
                        'height': active_window.height
                    }
                }
            
        except ImportError:
            self.logger.warning("pygetwindow not available, using Windows API or psutil fallback")
        except Exception as e:
            self.logger.error(f"Failed to get active window: {e}")
        
        # Fallback: try to get foreground process
        return self._get_foreground_process_fallback()
    
    def _get_foreground_process_fallback(self) -> Dict[str, Any]:
        """Fallback method to get foreground process info"""
        try:
            # Get processes sorted by CPU usage
            processes = sorted(
                psutil.process_iter(['pid', 'name', 'cpu_percent']),
                key=lambda p: p.info['cpu_percent'],
                reverse=True
            )
            
            # Find first non-system process with GUI
            for proc in processes:
                if proc.info['name'] not in ['System', 'Idle', 'kernel_task']:
                    return {
                        'title': f"{proc.info['name']} (estimated)",
                        'process': proc.info['name'],
                        'pid': proc.info['pid'],
                        'bounds': None
                    }
            
        except Exception as e:
            self.logger.error(f"Fallback process detection failed: {e}")
        
        return {
            'title': 'Unknown',
            'process': 'Unknown',
            'pid': None,
            'bounds': None
        }
    
    def get_top_processes(self, count: int = 10, sort_by: str = 'memory') -> List[Dict[str, Any]]:
        """
        Get top processes by CPU or memory usage
        
        Args:
            count: Number of processes to return
            sort_by: 'cpu' or 'memory'
            
        Returns:
            List of process info dicts
        """
        processes = []
        
        try:
            for proc in psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_info']):
                try:
                    # Get process info
                    pinfo = proc.info
                    memory_mb = pinfo['memory_info'].rss / 1024 / 1024
                    
                    processes.append({
                        'pid': pinfo['pid'],
                        'name': pinfo['name'],
                        'cpu_percent': pinfo['cpu_percent'],
                        'memory_mb': round(memory_mb, 2)
                    })
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    pass
            
            # Sort by requested metric
            if sort_by == 'cpu':
                processes.sort(key=lambda x: x['cpu_percent'], reverse=True)
            else:  # memory
                processes.sort(key=lambda x: x['memory_mb'], reverse=True)
            
            return processes[:count]
            
        except Exception as e:
            self.logger.error(f"Failed to get process list: {e}")
            return []
    
    def capture_system_state(self) -> Dict[str, Any]:
        """
        Capture comprehensive system state
        
        Returns:
            Dict with clipboard, screenshot, OCR, window info, and processes
        """
        self.logger.info("Capturing full system state...")
        
        state = {
            'timestamp': self.get_timestamp(),
            'clipboard': self.capture_clipboard(),
            'active_window': self.get_active_window_info(),
            'top_processes_cpu': self.get_top_processes(count=5, sort_by='cpu'),
            'top_processes_memory': self.get_top_processes(count=5, sort_by='memory')
        }
        
        # Capture screenshot with OCR
        screenshot_data = self.capture_screenshot_with_ocr()
        state['screenshot'] = screenshot_data
        
        # Add system info
        state['system'] = {
            'cpu_percent': psutil.cpu_percent(interval=1),
            'memory_percent': psutil.virtual_memory().percent,
            'disk_usage': psutil.disk_usage('/').percent
        }
        
        self.logger.info("System state capture complete")
        return state
    
    def image_to_base64(self, image: Image.Image, format: str = 'PNG') -> str:
        """
        Convert PIL Image to base64 string
        
        Args:
            image: PIL Image
            format: Image format for encoding
            
        Returns:
            Base64 encoded string
        """
        buffer = io.BytesIO()
        image.save(buffer, format=format)
        img_bytes = buffer.getvalue()
        return base64.b64encode(img_bytes).decode('utf-8')


def main():
    """Example usage"""
    capture = Capture()
    
    print("Capturing system state...")
    state = capture.capture_system_state()
    
    print(f"\nTimestamp: {state['timestamp']}")
    print(f"Clipboard: {state['clipboard'][:100] if state['clipboard'] else 'Empty'}...")
    print(f"Active Window: {state['active_window']['title']}")
    print(f"Screenshot: {state['screenshot'].get('path', 'Not saved')}")
    print(f"OCR Text: {len(state['screenshot'].get('ocr_text', '')) if state['screenshot'].get('ocr_text') else 0} chars")
    
    print("\nTop CPU Processes:")
    for proc in state['top_processes_cpu'][:3]:
        print(f"  {proc['name']}: {proc['cpu_percent']}%")
    
    print("\nSystem Status:")
    print(f"  CPU: {state['system']['cpu_percent']}%")
    print(f"  Memory: {state['system']['memory_percent']}%")


if __name__ == "__main__":
    main()