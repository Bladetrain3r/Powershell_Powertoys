# Pyttai Operator Syntax

## Design Philosophy

Python handles operators differently from shells. Instead of fighting with `|`, `>`, `>>`, `&&`, etc., Pyttai uses a consistent colon-based syntax that:
- Works identically across all platforms
- Parses cleanly in Python
- Avoids shell injection risks
- Is visually distinct from normal text

## Operator Reference

| Operator | Shell Equivalent | Description | Example |
|----------|------------------|-------------|---------|
| `:p` | `\|` | Pipe output to next command | `list files :p grep .py` |
| `:r` | `>` | Redirect output to file | `list files :r files.txt` |
| `:rr` | `>>` | Append output to file | `status :rr log.txt` |
| `:i` | `<` | Input from file | `analyze :i data.txt` |
| `:ii` | `<<` | Here-document input | `format :ii END\ntext\nEND` |
| `:s` | `&&` | Run next if success | `test connection :s download` |
| `:f` | `\|\|` | Run next if failure | `connect :f use-offline` |
| `:c` | (custom) | Read file as command input | `send :c prompt.txt` |

## Parsing Rules

1. **Space Delimited**: Operators must be surrounded by spaces
   - ✅ `command :p next`
   - ❌ `command:p next`
   - ❌ `command: p next`

2. **Quote Protection**: Operators inside quotes are literal text
   - `echo "use :p for piping"` → outputs: `use :p for piping`
   - `'my:file:name.txt'` → literal filename

3. **Left-to-Right**: Operations execute in order
   - `cmd1 :p cmd2 :r out.txt` → cmd1 pipes to cmd2, result to file

## Examples

### Basic Piping
```bash
# List Python files
list files :p filter .py

# Count lines in Python files
find *.py :p count lines

# Chain multiple operations
list processes :p filter python :p sort cpu
```

### File Operations
```bash
# Save command output
system info :r sysinfo.txt

# Append to log
timestamp :rr activity.log
status :rr activity.log

# Use file as input
analyze :i code.py
summarize :c requirements.txt
```

### Conditional Execution
```bash
# Run backup only if test succeeds
test database :s backup database

# Try primary server, fallback if fails
connect primary :f connect backup

# Chain conditionals
build :s test :s deploy
```

### Complex Examples
```bash
# Process and save results
find *.log :p grep ERROR :r errors.txt

# Conditional pipeline
check api :s fetch data :p parse json :r output.json

# Multi-stage processing
list files :p filter .py :c analyze.prompt :p ai
```

## Implementation Details

### Parser Logic
```python
def parse_command_line(line: str) -> List[Operation]:
    # Protect quoted sections
    protected = protect_quotes(line)
    
    # Split on colon operators
    parts = split_on_operators(protected)
    
    # Build operation chain
    operations = []
    for part in parts:
        op_type, content = identify_operation(part)
        operations.append(Operation(op_type, content))
    
    return operations
```

### Operation Types
```python
class OperationType(Enum):
    COMMAND = "command"
    PIPE = ":p"
    REDIRECT = ":r"
    APPEND = ":rr"
    INPUT = ":i"
    HEREDOC = ":ii"
    SUCCESS = ":s"
    FAILURE = ":f"
    READ_FILE = ":c"
```

### Execution Flow
1. Parse command line into operations
2. Execute first command
3. Apply operators in sequence
4. Handle success/failure conditions
5. Return final result

## Benefits

1. **Consistent**: Same syntax everywhere
2. **Safe**: No shell injection risks
3. **Clear**: Visually distinct operators
4. **Powerful**: All shell operations supported
5. **Extensible**: Easy to add new operators

## Future Operators (Proposed)

| Operator | Description | Example |
|----------|-------------|---------|
| `:a` | Run in parallel | `scan port1 :a scan port2` |
| `:t` | Tee (output + pass through) | `download :t progress.log :p unzip` |
| `:ai` | Pipe to AI analysis | `errors.log :ai explain` |
| `:j` | JSON parse/filter | `api call :j .data.items` |

## Comparison with Shell Syntax

```bash
# Bash
ls -la | grep .py > files.txt 2>&1

# Pyttai
list files detailed :p filter .py :r files.txt

# Bash
make && make test && make install

# Pyttai  
build :s test :s install

# Bash
curl api.com || echo "Failed" >> error.log

# Pyttai
fetch api.com :f echo "Failed" :rr error.log
```

The Pyttai syntax is more verbose but:
- Works identically on all platforms
- Easier to parse programmatically
- Clearer intent
- Safer execution