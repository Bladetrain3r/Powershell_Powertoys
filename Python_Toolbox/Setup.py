#!/usr/bin/env python3
"""
Create folder structure and extract prompts from PowerShell scripts
"""

import os
from pathlib import Path
import re

def create_folder_structure():
    """Create the project folder structure"""
    
    # Define folder structure
    folders = [
        "prompts/analysis",
        "prompts/summarization", 
        "prompts/generation",
        "prompts/verification",
        "prompts/templates",
        "classes",
        "tests",
        "outputs",  # Added for output files
        "logs",     # Added for logging
    ]
    
    # Create folders
    for folder in folders:
        Path(folder).mkdir(parents=True, exist_ok=True)
        print(f"Created: {folder}/")
    
    # Create __init__.py files for Python packages
    for folder in ["classes", "tests"]:
        init_file = Path(folder) / "__init__.py"
        init_file.write_text("# Python package initialization\n")
        print(f"Created: {init_file}")
    
    # Create .gitkeep files to preserve empty folders
    gitkeep_folders = ["outputs", "logs", "prompts/templates"]
    for folder in gitkeep_folders:
        gitkeep = Path(folder) / ".gitkeep"
        gitkeep.write_text("")
        print(f"Created: {gitkeep}")

def create_prompt_files():
    """Create prompt files extracted from PowerShell scripts"""
    
    # Using triple quotes with different delimiters to avoid conflicts
    prompts = {}
    
    # Analysis prompts
    prompts["prompts/analysis/screenshot_context.txt"] = '''SYSTEM CONTEXT:
- Current Time: {current_time}
- Active Window: "{active_window}" (Process: {active_process})
- Recent Clipboard: {clipboard_preview}

EXTRACTED TEXT (Windows OCR):
{extracted_text}

TASK: Analyze this screenshot with the above context. Focus on the content on the screen, the active application, and any relevant text. Avoid speculation about the user's intent or actions.'''

    prompts["prompts/analysis/screenshot_vision.txt"] = '''EXTRACTED TEXT (OCR):
{ocr_text}

TASK: Analyze this screenshot and describe the main activity, application, and content. Avoid speculation and focus on content over guessed activity.'''

    prompts["prompts/analysis/file_risk_assessment.txt"] = '''Analyze this file for security and code quality risks. Provide assessment in EXACTLY this format, nothing else, no other words, and keep each section concise:

RISK_LEVEL: [LOW/MEDIUM/HIGH/CRITICAL]
SECURITY_ISSUES: [Brief description of security concerns like hardcoded passwords, SQL injection risks, etc.]
QUALITY_ISSUES: [Brief description of code quality issues like hardcoded paths, poor variable naming, etc.]
BEST_PRACTICE_VIOLATIONS: [Brief description of best practice violations like missing error handling, poor structure, etc.]

File: {filename}
Content: {content}'''

    prompts["prompts/analysis/system_monitor.txt"] = '''Analyze this system monitoring data and provide insights about resource usage. Focus on:

• RESOURCE HOG IDENTIFICATION - Which processes are consuming the most CPU/memory and why
• SYSTEM HEALTH ASSESSMENT - Overall system performance and any concerns
• OPTIMIZATION OPPORTUNITIES - What could be improved or investigated
• UNUSUAL ACTIVITY - Any processes or patterns that seem abnormal
• RECOMMENDATIONS - Specific actions to improve performance

System Data:
{system_data}'''

    # Summarization prompts
    prompts["prompts/summarization/clipboard_summary.txt"] = '''Concisely summarize this text. Focus on key points and main ideas. Optimize for text-to-speech delivery, no special characters (correct spoken english only), keep it brief and clear:

{content}'''

    prompts["prompts/summarization/activity_chronicle.txt"] = '''Create a brief overview of this user activity timeline. Identify main themes, productivity patterns, or notable activities. Keep it concise and insightful:

{timeline}'''

    prompts["prompts/summarization/screenshot_summary.txt"] = '''Summarize this activity in 1-2 concise sentences. Focus on what the user was doing or viewing. Be specific about applications, content, or tasks:

{content}'''

    prompts["prompts/summarization/news_overview.txt"] = '''Analyze these news headlines and create a comprehensive daily briefing. Structure your response as:

TOP_STORIES: [3-5 most important stories of the day with brief explanations]
TRENDING_TOPICS: [Common themes and topics appearing across multiple sources]
TECHNOLOGY_NEWS: [Key technology and innovation stories]
BUSINESS_ECONOMIC: [Major business and economic developments]
POLITICS_GOVERNANCE: [Political and policy developments]
INTERNATIONAL: [Global and international news]
OTHER_NOTABLE: [Other significant stories worth mentioning]
SUMMARY: [2-3 sentence overall summary of the day's news]

DO NOT use special characters or complex formatting. Purely simple text.
No intro music or other bullshit. No superfluous additions. Just. The. Feed. Summarised.

Today's Headlines ({date}):
{headlines}'''

    prompts["prompts/summarization/audio_briefing.txt"] = '''Summarise the feeds in brief. Plaintext only.

Requirements:
- Start with date and brief overview
- Cover the most important stories clearly
- Cover key topics like technology, business, politics, and international news
- Use simple, clear language suitable for text-to-speech

News Analysis:
{news_analysis}'''

    prompts["prompts/summarization/tts_summary.txt"] = '''Create a 2-3 sentence audio summary of this system analysis.
Focus on key findings and main recommendations.
Only the summary, no additional context or statements.
Make it suitable for text-to-speech:

{content}'''

    # Generation prompts
    prompts["prompts/generation/test_cases.txt"] = '''Generate practical test cases for this code:

UNIT TESTS: [Test individual functions with specific inputs/outputs]
EDGE CASES: [Boundary conditions, null/empty inputs, invalid data]
ERROR HANDLING: [Exception scenarios and error conditions]
INTEGRATION TESTS: [Component interactions if applicable]
VALIDATION TESTS: [Input validation and data integrity]

Focus on realistic test scenarios that would actually be implemented.

File: {filename}
Code: {code}'''

    prompts["prompts/generation/error_analysis.txt"] = '''Analyze potential errors in this code:

SYNTAX ERRORS: [Compilation/parsing issues]
RUNTIME ERRORS: [Execution exceptions and failure points]
LOGIC ERRORS: [Incorrect behavior or flawed algorithms]
RESOURCE ERRORS: [File/memory/network/permission issues]
INPUT VALIDATION: [Unhandled user input scenarios]

Focus on likely failure scenarios rather than theoretical edge cases.

File: {filename}
Code: {code}'''

    prompts["prompts/generation/cumulative_risk.txt"] = '''Assess the cumulative risk from this error analysis:

OVERALL_RISK_LEVEL: [LOW/MEDIUM/HIGH/CRITICAL]
PRODUCTION ENVIRONMENT: [Is it safe to deploy in prod? Yes/No]
DEVELOPMENT ENVIRONMENT: [Is it reasonably safe to deploy in dev? Yes/No]
LOCAL ENVIRONMENT: [Is it reasonably safe to run locally? Yes/No]
MOST_LIKELY_FAILURES: [What will probably actually break]
WORST_CASE_SCENARIO: [Realistic worst-case outcomes]
MITIGATION_PRIORITY: [Which issues to fix first]
USER_IMPACT: [How failures affect end users]
QUICK_WINS: [Easy fixes with high impact]

Be practical and focus on real-world implications.

File: {filename}
Error Analysis: {error_analysis}'''

    prompts["prompts/generation/critical_analysis.txt"] = '''CONTENT TYPE: {content_type}
{analysis_instructions}

{content_specific_prompt}

{content_label}:
{content}'''

    # Verification prompts (structured output)
    prompts["prompts/verification/consistency_check.txt"] = '''Confirm these individual and overview summaries are in line with each other. Respond with ONLY "GOOD" if they are consistent, or "BAD" if they are not. Do not provide any explanations or additional text.

Respond with ONLY either "GOOD" or "BAD" - nothing else. One of those two words, by itself, in caps.

OVERVIEW SUMMARY:
{overview_summary}

INDIVIDUAL SUMMARIES:
{individual_summaries}'''

    prompts["prompts/verification/file_summary_format.txt"] = '''Analyze this file content and create a summary. 
Each line should be one sentence describing one thing. 
Format it only as newline separated text. 
Don't include any confirmations or extra explanations.
Keep it brief please.

You are simply summarizing the content of the file as simply and parsably as possible.
Don't say "here's a summary" or something like that all I want is the content of the file nothing else at all
To reiterate, this is supposed to be programmatic not conversational.
DO NOT SAY ANYTHING ELSE.
SILENCE BESIDES THAT.
THANK YOU.

File: {filename}
Content:
{content}'''

    prompts["prompts/verification/risk_level_check.txt"] = '''Based on this analysis, determine the risk level.
Respond with ONLY one of these words: LOW, MEDIUM, HIGH, CRITICAL
No other text, no punctuation, just the risk level word.

Analysis:
{analysis}'''
    
    # Create prompt files
    for filepath, content in prompts.items():
        path = Path(filepath)
        path.write_text(content.strip() + "\n", encoding='utf-8')
        print(f"Created: {filepath}")

def create_config_files():
    """Create configuration files"""
    
    # Create prompt config with chunk sizes
    prompt_config = {
        "defaults": {
            "api_endpoint": "http://localhost:1234",
            "model_name": "gemma-3-4b-it-qat",
            "output_dir": "~/Screenshots",
            "tts_endpoint": "http://localhost:8880",
            "tts_model": "kokoro",
            "tts_voice": "af_sky",
            "log_level": "INFO"
        },
        "chunk_sizes": {
            "analysis/screenshot_context": 12000,
            "analysis/file_risk_assessment": 6000,
            "summarization/clipboard_summary": 8000,
            "summarization/news_overview": 15000,
            "generation/test_cases": 8000,
            "generation/error_analysis": 8000,
            "verification/consistency_check": 15000
        },
        "temperature_settings": {
            "verification": 0.1,
            "analysis": 0.2,
            "summarization": 0.3,
            "generation": 0.3
        },
        "max_tokens": {
            "verification": 50,
            "analysis": 1500,
            "summarization": 1000,
            "generation": 2000
        }
    }
    
    import json
    config_path = Path("prompts/templates/config.json")
    config_path.write_text(json.dumps(prompt_config, indent=2), encoding='utf-8')
    print(f"Created: {config_path}")
    
    # Create README
    readme_content = '''# AI Toybox Project Structure

## Folders

- **prompts/**: All AI prompt templates organized by category
  - **analysis/**: Prompts for analyzing content (screenshots, files, etc.)
  - **summarization/**: Prompts for creating summaries
  - **generation/**: Prompts for generating new content (tests, analysis)
  - **verification/**: Prompts requiring structured/specific output format
  - **templates/**: Shared templates and configuration

- **classes/**: Import-only Python code (utilities, managers, etc.)
- **tests/**: Test files for the project
- **outputs/**: Generated output files
- **logs/**: Application logs

## Usage

1. Import prompt manager from classes
2. Load prompts using category/name
3. Format with variables
4. Send to AI model

## Adding New Prompts

1. Create .txt file in appropriate category folder
2. Use {variable_name} for replaceable content
3. Update config.json if special settings needed
'''
    
    readme_path = Path("README.md")
    readme_path.write_text(readme_content, encoding='utf-8')
    print(f"Created: {readme_path}")
    
    # Create .gitignore
    gitignore_content = '''# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
env/
venv/
.env

# IDE
.vscode/
.idea/
*.swp
*.swo

# Project specific
outputs/*
!outputs/.gitkeep
logs/*
!logs/.gitkeep
*.log

# OS
.DS_Store
Thumbs.db
'''
    
    gitignore_path = Path(".gitignore")
    gitignore_path.write_text(gitignore_content, encoding='utf-8')
    print(f"Created: {gitignore_path}")

def main():
    """Main execution"""
    print("Creating AI Toybox project structure...\n")
    
    create_folder_structure()
    print("\n" + "="*50 + "\n")
    
    create_prompt_files()
    print("\n" + "="*50 + "\n")
    
    create_config_files()
    print("\n" + "="*50 + "\n")
    
    print("Project structure created successfully!")
    print("\nNext steps:")
    print("1. Create PromptManager class in classes/prompt_manager.py")
    print("2. Create APIClient class in classes/api_client.py")
    print("3. Start converting PowerShell scripts to Python modules")

if __name__ == "__main__":
    main()