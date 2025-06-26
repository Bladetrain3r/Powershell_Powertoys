# AI Toybox Project Structure

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
