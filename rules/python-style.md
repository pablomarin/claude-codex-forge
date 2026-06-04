---
paths:
  - "**/*.py"
---

# Python Style

## Tooling

Use `ruff` (lint + format), `mypy --strict`, `uv` (packages). Line length: 100.

**Cache resets — use tool flags, never `rm -rf`.** Recursive deletes are ask-tier in Forge settings (`Bash(rm -rf:*)`), so they pause the run for a human permission prompt — which silently stalls an autonomous `/goal` loop. Every Python tool has a prompt-free flag that does the same job:

| Instead of             | Use                       |
| ---------------------- | ------------------------- |
| `rm -rf .mypy_cache`   | `mypy --no-incremental …` |
| `rm -rf .pytest_cache` | `pytest --cache-clear …`  |
| `rm -rf .ruff_cache`   | `ruff check --no-cache …` |

(If deletion is genuinely unavoidable, the exact commands `rm -rf .mypy_cache` / `.pytest_cache` / `.ruff_cache` are allow-listed in Forge settings — exact match only, no trailing arguments.)

## Type Hints

ALWAYS type all function parameters and return values.

```python
def get(id: int) -> User | None: ...          # Correct
async def fetch(ids: list[int]) -> list[Item]: ...  # Correct
def get(id): ...                               # WRONG: missing types
```

Use modern syntax: `str | None` not `Optional[str]`, `list[int]` not `List[int]`.

## Patterns

**Early returns** — avoid nesting:

```python
def process(x: Order | None) -> Result:
    if not x: return Error("missing")
    if not x.valid: return Error("invalid")
    return execute(x)
```

**No mutable defaults**:

```python
def f(items: list[int] | None = None): ...  # Correct
def f(items: list[int] = []): ...           # WRONG: shared mutable
```

**Specific exceptions**:

```python
except httpx.TimeoutException: ...  # Correct
except Exception: ...               # WRONG: too broad
except: ...                         # WRONG: bare except
```

**Async — never block**:

```python
await asyncio.sleep(5)  # Correct
time.sleep(5)           # WRONG: blocks event loop
```

**Concurrent I/O**:

```python
a, b, c = await asyncio.gather(fetch_a(), fetch_b(), fetch_c())
```

## Data Structures

- `@dataclass` for internal data containers
- `pydantic.BaseModel` for external input validation

## Rules

1. ALWAYS add complete type hints
2. ALWAYS run `ruff` and `mypy --strict` before commit
3. NEVER use mutable default arguments
4. NEVER use bare `except:` or broad `except Exception:`
5. NEVER block the event loop with sync calls
6. PREFER early returns over nested conditionals
