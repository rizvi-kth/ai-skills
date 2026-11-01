---
name: uv-manager
description: Operate Python projects end to end with uv, with safety checks for real-world repos. Use to initialise or migrate a project, add/remove/upgrade dependencies, manage Python versions, write runnable single-file scripts, install or run CLI tools, bump versions, build and publish, export requirements for Docker/CI, and fix uv problems behind corporate proxies, private indexes, offline sandboxes, Windows, or non-uv (Poetry/PDM/conda) projects.
---

# uv-manager

A self-contained operating guide for managing Python with **uv** (Astral's package and project manager). One file, no dependencies. Works as:
- a **Claude skill**: save as `uv-manager/SKILL.md`
- an **OpenAI / other agent** instruction set: paste the body into the system prompt or agent `instructions`; for Codex-style agents, save as `AGENTS.md` in the repo
- a human reference

Basis: the uv cheatsheet by Rodrigo Girão Serrão (mathspp.com/blog/uv-cheatsheet) plus the uv docs (docs.astral.sh/uv). Commands and flags verified against **uv 0.11.32**. If the local uv is older or newer, rule A7 applies.

**How to read this file:** Part A (rules) and Part B (router) are always needed. Everything after is reference to consult when the router points there.

---

# PART A — Operating rules (always follow)

### A1. Preflight (once per session)
1. Run `uv --version`. (`uv self version` also works, but only for uv installed by its own installer.)
2. If uv is missing, ask before installing it:
   - macOS/Linux: `curl -LsSf https://astral.sh/uv/install.sh | sh`
   - Windows (PowerShell): `powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"`
   - Locked-down machine or no internet to astral.sh: `pipx install uv` or `python -m pip install --user uv`
   - After installing, the shell may need restarting before `uv` is on PATH.
3. Note the OS. On Windows, follow section K.

### A2. Detect what kind of project this is BEFORE running uv commands
uv looks for `pyproject.toml` in the current directory **and its parents**, so check upward too (`uv run --directory <dir>` / `--project <dir>` target a specific one).

| Found | Meaning | Action |
|---|---|---|
| `uv.lock` | uv project | Proceed normally |
| `pyproject.toml` + `poetry.lock` or a `[tool.poetry]` table | Poetry project | **Do not run `uv add/lock/sync`.** Ask the user. Offer: use Poetry, or migrate (section J5) |
| `pdm.lock` or `[tool.pdm]` | PDM project | Same as Poetry |
| `Pipfile` / `Pipfile.lock` | Pipenv project | Same as Poetry |
| `environment.yml`, or `CONDA_PREFIX` set | conda environment | Ask. Never mix uv project commands into a conda env unasked. `uv pip` into it is possible only if the user wants it |
| `pyproject.toml` only, no lock of any kind | Probably uv-compatible (setuptools/hatch/flit) | Confirm with the user once, then proceed; uv will create `uv.lock` |
| `requirements*.txt` only | pip-style project | Ask: migrate to uv project (J5), or keep pip style with `uv pip` (section I) |
| `[tool.uv.workspace]` in a parent `pyproject.toml` | Inside a workspace | See section L before `uv init` or `uv add` |
| Nothing | No project | `uv init` is appropriate |

Creating a `uv.lock` in someone else's tool's project is a visible change in their repo, so always confirm first.

### A3. Never mix environment managers in a uv project
- No bare `pip install`, `python -m venv`, `pipx` or `poetry add` inside a uv project.
- **Never use `uv pip install` into a uv project's `.venv`.** `uv sync`, and the automatic sync `uv run` performs, are *exact*: they remove anything not in `uv.lock`. A package installed that way disappears on the next `uv run`. Use `uv add` (permanent) or `uv run --with pkg` (one-off).
- If the user really needs extra packages kept in a synced env, use `uv sync --inexact` and explain the trade-off.

### A4. Execute with `uv run`
`uv run <cmd>` locks, syncs, and runs inside the project env. No activation needed.
- If a different venv or conda env is active, uv warns that `VIRTUAL_ENV ... does not match the project environment path` and **ignores it**. That is expected, not an error. Add `--active` only if the user wants the active env used.
- `uv run` may create `uv.lock` and `.venv` and edit the lock. To run something without touching the project, use `uv run --no-project ...` or `uvx ...`.
- For CI or reproducible runs, use `uv run --locked` (fail if the lock is stale) or `--frozen` (use the lock as-is, never update it).

### A5. Confirm before risky or irreversible actions
Ask first, show the exact command, and wait:
- `uv publish`: uploads are permanent; a version number can never be reused on PyPI.
- `uv lock --upgrade` (all packages); prefer `--upgrade-package X` when the user means one package.
- `uv remove` when other code may import the package. Check with `uv tree --invert --package X`.
- `uv python uninstall`, `uv tool uninstall`, `uv cache clean`
- `uv self update`; in a corporate setting, uv may be centrally managed.
- `uv venv --clear` or deleting `.venv`
- Creating `uv.lock` in a non-uv project (A2)
- Editing `requires-python`

Safe without asking: `uv tree`, `uv python list`, `uv version` (read-only form), `uv lock --check`, `uv help`, `--dry-run` variants.

### A6. Network-aware behaviour (corporate, sandbox, offline)
Most uv commands hit the network: resolving, downloading packages, downloading Python, `uvx`, and `uv format` (which downloads Ruff). Before blaming the project, classify the error:

| Error text contains | Cause | Fix |
|---|---|---|
| `failed to lookup address`, `dns error`, `Connection refused`, `timed out` | No network (sandbox, air-gap, VPN off) | Retry **once** with `--offline` (cache only). If that fails, stop and tell the user network is needed. **Do not loop.** |
| `invalid peer certificate`, `UnknownIssuer`, `certificate verify failed` | Corporate TLS inspection | `--system-certs` / `UV_SYSTEM_CERTS=1` (older uv: `--native-tls` / `UV_NATIVE_TLS=1`, now deprecated). Or `SSL_CERT_FILE=/path/corp-ca.pem` |
| `403`, `401`, `407` | Proxy auth or index auth | Check `HTTPS_PROXY`/`HTTP_PROXY`/`NO_PROXY`; index credentials (section M) |
| `Read-only file system`, `Permission denied` on cache | Unwritable cache/home | `UV_CACHE_DIR=/tmp/uv-cache` (or `--no-cache` for a single command) |
| Python download fails | Blocked github/astral downloads | Use a system Python: `--python /usr/bin/python3.12` or `UV_PYTHON_DOWNLOADS=never`; or `UV_PYTHON_INSTALL_MIRROR` |

**Never** use `--allow-insecure-host` / `UV_INSECURE_HOST` to "fix" certificate errors unless the user explicitly asks and understands the risk.

### A7. Version awareness
uv changes fast. If a flag errors as unknown, run `uv help <command>` and adapt; don't guess. Commands that newer uv has and older uv may lack: `uv format`, `uv version --bump`, `uv python upgrade`, `uv build --clear`, `uv auth`. If missing, tell the user the uv version and offer `uv self update` (with confirmation), or use the fallback given in each section.

### A8. Reporting
Show each command you ran or will run. After it finishes, report the outcome in one or two sentences: what changed in `pyproject.toml`/`uv.lock`, which files were created, and what failed and why.

### A9. Package-name safety
`uv add` downloads and may build arbitrary code. If a requested name looks misspelled (`reqeusts`, `python-dateutils`) or is unfamiliar, confirm the exact name with the user before adding it.

### A10. Placeholders
`3.X` means a real version such as `3.13`. `--python 3.X` works on almost every uv command.

---

# PART B — Intent router

| User intent | Command | Section |
|---|---|---|
| New project | `uv init myproj` | C |
| New CLI app / web app | `uv init --app --package myapp` | C |
| New library | `uv init --lib mylib` | C |
| Adopt uv in existing code folder | `uv init --bare` | C, J5 |
| Add package | `uv add pkg` | D |
| Add test/dev tool | `uv add --dev pkg` | D |
| Add optional extra | `uv add --optional extra pkg` | D |
| Add from git / local path | `uv add git+https://...` / `uv add --editable ../lib` | D |
| Remove package | `uv remove pkg` | D |
| Upgrade one package | `uv lock --upgrade-package pkg` then `uv sync` | D |
| Upgrade all (confirm) | `uv lock --upgrade` then `uv sync` | D |
| What's outdated? | `uv tree --outdated --depth 1` | D |
| Why is X installed? | `uv tree --invert --package X` | D |
| Fresh clone setup | `uv sync` | D |
| CI install | `uv sync --locked` | N |
| Run tests / app | `uv run pytest` / `uv run python -m pkg` | A4 |
| Try a package, don't touch project | `uv run --no-project --with pkg python` or `uvx --with pkg python` | G |
| Change Python version | `uv python pin 3.X` then `uv sync` | F |
| One-file script with deps | `uv init --script x.py` + `uv add --script x.py pkg` | G |
| Run a CLI once | `uvx tool` | H |
| Install a CLI globally | `uv tool install tool` | H |
| Bump version | `uv version --bump minor` | E |
| Build / publish (confirm) | `uv build --clear` / `uv publish` | E |
| requirements.txt for Docker/other tools | `uv export --format requirements.txt -o requirements.txt` | N |
| Format code | `uv format` | O |
| Plain venv / pip workflow | `uv venv` + `uv pip ...` | I |
| Disk full / weird cache | `uv cache prune` / `uv cache clean` (confirm) | O |
| Something broken | — | P |

---

# PART C — Creating projects

| Command | Effect |
|---|---|
| `uv init` | Project in current dir (adds `pyproject.toml`, `README.md`, `main.py`, `.python-version`, git repo) |
| `uv init myproj` | Project in new dir `myproj` |
| `uv init --app --package myapp` | Packageable app with `src/` layout and build system (CLIs, web apps) |
| `uv init --lib mylib` | Library; `--lib` **already implies `--package`** |
| `uv init --bare` | Only `pyproject.toml`; no sample files, no git, no `.python-version`. Best for existing code |
| `uv init --python 3.X ...` | Set the project Python |
| `uv init --no-workspace ...` | Do **not** join a parent workspace |
| `uv init --vcs none ...` | Skip `git init` |
| `uv init --build-backend hatch ...` | Choose build backend: `uv` (default, = `uv_build`), `hatch`, `setuptools`, `flit`, `pdm`, `poetry`, `maturin`, `scikit` |

Corner cases:
- **A `pyproject.toml` already exists** → `uv init` fails with "Project is already initialized". Don't re-init; go to D.
- **Existing code folder** → plain `uv init` adds a sample `main.py` and `README.md` next to the user's files. Use `--bare`.
- **Inside a workspace** → `uv init child` silently adds `child` to the parent's `[tool.uv.workspace] members`. Ask whether that's intended; otherwise use `--no-workspace`.
- **Plain `uv init` (no `--package`)** creates a project with no build system: you can't `uv build` it or install its CLI. Use `--package` if the code will be installed, imported elsewhere, or published.
- **Dotted or uppercase dir names** are normalised for the package name (`My.Proj` → `my-proj`); pass `--name` to control it.

---

# PART D — Dependencies

| Command | Effect |
|---|---|
| `uv add requests` | Add dependency (edits `pyproject.toml`, updates `uv.lock`, syncs `.venv`) |
| `uv add A B C` | Several at once |
| `uv add "requests>=2.31,<3"` | With constraint (always quote: shells treat `>` and `<` as redirects) |
| `uv add --bounds major requests` | Control the auto-added constraint: `lower` (default), `major`, `minor`, `exact` |
| `uv add --dev pytest` | Dev dependency (`[dependency-groups] dev`) |
| `uv add --group lint ruff` | Named dependency group |
| `uv add --optional plot matplotlib` | Optional extra (`pip install mypkg[plot]`) |
| `uv add git+https://github.com/org/repo --tag v1.2` | Git dependency (`--branch`, `--rev` also work) |
| `uv add --editable ../shared-lib` | Local path, editable |
| `uv add --index myindex=https://... pkg` | From a specific index (see M) |
| `uv add -r requirements.txt` | Import a requirements file (see J5 caveats) |
| `uv add --no-sync pkg` | Edit and lock but don't install (fast, for metadata-only edits) |
| `uv add --frozen pkg` | Edit `pyproject.toml` only; no lock, no sync (works offline) |
| `uv remove pkg` | Remove; transitive deps go **only if nothing else needs them** |
| `uv remove --dev pytest` / `--group lint` / `--optional plot` | Remove from that section |
| `uv sync` | Make `.venv` match `uv.lock` exactly |
| `uv sync --all-extras --all-groups` | Include every extra and group |
| `uv sync --no-dev` | Production install |
| `uv lock` | Re-resolve after manual `pyproject.toml` edits |
| `uv lock --check` | Exit non-zero if the lock is stale (CI guard) |
| `uv lock --upgrade-package requests` | Upgrade one package (preferred) |
| `uv lock --upgrade` | Upgrade everything allowed by constraints (**confirm**) |
| `uv tree` | Dependency tree |
| `uv tree --outdated --depth 1` | Direct deps with newer versions available |
| `uv tree --invert --package X` | What depends on X (check before removing) |

Corner cases:
- After **manually editing** `pyproject.toml`, run `uv lock` (or just `uv sync`/`uv run`, which re-lock).
- `uv lock --upgrade` does not install anything; follow it with `uv sync`.
- If an upgrade hits **a constraint**, `uv lock --upgrade` silently keeps the old version. Check with `uv tree --outdated`, then raise the bound with the user.
- **Resolution conflicts:** read uv's explanation (it names the conflicting packages). Options: relax a bound, pin a compatible version, or (if only some Python versions conflict) narrow `requires-python`. Get the user's choice.
- **Platform-specific deps** (e.g. Windows-only): `uv add "pywin32; sys_platform == 'win32'"`.
- **`requires-python` too wide** (e.g. `>=3.8`) can make resolution fail for packages that dropped old Pythons. Suggest raising it, with approval.

---

# PART E — Versioning, building, publishing

| Command | Effect |
|---|---|
| `uv version` | Show version |
| `uv version --short` | Version number only (for scripts) |
| `uv version 2.0.0` | Set an exact version |
| `uv version --bump major` | `0.3.2 → 1.0.0` |
| `uv version --bump minor` | `1.0.0 → 1.1.0` |
| `uv version --bump patch` | `1.1.0 → 1.1.1` |
| `uv version --bump minor --bump beta` | `1.0.0 → 1.1.0b1`; `1.1.0b1 → 1.1.0b2` |
| `uv version --bump rc` | `1.1.0b1 → 1.1.0rc1`; `1.1.0rc1 → 1.1.0rc2` |
| `uv version --bump stable` | `1.1.0rc1 → 1.1.0` |
| `uv version --bump minor --dry-run` | Preview only |
| `uv version --bump ... --frozen` | Change version without re-locking/syncing (offline-safe) |
| `uv build --clear` | Empty `dist/` then build sdist + wheel |
| `uv build --wheel` / `--sdist` | Only one kind |
| `uv build --no-sources` | Build as it would on PyPI (ignores local/git `tool.uv.sources`); use before publishing |
| `uv publish --dry-run` | Check what would be uploaded |
| `uv publish --index testpypi` | Publish to TestPyPI (index must be defined, see below) |
| `uv publish` | Publish **everything in `dist/*`** to PyPI (**confirm**) |

Corner cases:
- **Dynamic versions** (`dynamic = ["version"]`, e.g. hatch-vcs or setuptools-scm reading git tags): `uv version` and `--bump` fail with "cannot get or set dynamic project versions". Bump by creating a git tag instead (`git tag v1.2.0`), after confirming with the user.
- **Stale files in `dist/`:** `uv publish` uploads every file there, including old builds. Always build with `--clear` (fallback for older uv: delete `dist/` first), then `uv publish --dry-run`.
- **No build system** (project made with plain `uv init`): `uv build` has nothing to build. Add a `[build-system]` table or re-create with `--package`, with approval.
- **Credentials:** never print or commit tokens. Options, in order of preference:
  1. Trusted publishing from GitHub Actions (no token; `uv publish` detects it)
  2. `UV_PUBLISH_TOKEN` environment variable
  3. `uv publish --token "$TOKEN"`, with the token taken from an env var or secret store, never pasted into a file
- **TestPyPI first.** Add this to `pyproject.toml`, then `uv publish --index testpypi`:
  ```toml
  [[tool.uv.index]]
  name = "testpypi"
  url = "https://test.pypi.org/simple/"
  publish-url = "https://test.pypi.org/legacy/"
  explicit = true
  ```
- **Version already exists** on the index → upload is rejected. Bump the version; you cannot overwrite a release.
- **Release checklist:** `uv lock --check` → `uv run pytest` → `uv version --bump ...` → `uv build --clear --no-sources` → `uv publish --dry-run` → confirm → `uv publish` → `git tag vX.Y.Z`.

---

# PART F — Python versions

| Command | Effect |
|---|---|
| `uv python list` | Installed and downloadable versions |
| `uv python list --only-installed` | Installed only |
| `uv python find 3.X` | Path of the interpreter uv would use |
| `uv python install 3.X` | Install a uv-managed Python |
| `uv python install 3.X --default` | Also expose it as `python`/`python3` on PATH |
| `uv python uninstall 3.X` | Remove (**confirm**) |
| `uv python upgrade` | Upgrade uv-managed Pythons to the latest patch |
| `uv python pin 3.X` | Write `.python-version` for this project |
| `uv python pin --global 3.X` | Default for all projects without a pin |
| `uv run --python 3.X python` | Run a specific Python |

Changing a project's Python:
1. Check `requires-python` in `pyproject.toml`. **The pin must satisfy it**, or uv errors.
2. If it doesn't, ask the user before editing `requires-python`.
3. Run `uv python pin 3.X`, then `uv sync`. uv recreates `.venv` with the new interpreter.

Corner cases:
- `uv python upgrade` and `uninstall` only affect **uv-managed** Pythons. System, Homebrew, pyenv and Microsoft Store Pythons are untouched; say so if the user expects otherwise.
- **Downloads blocked** (A6): point uv at an existing interpreter with `--python /path/to/python` or `UV_PYTHON_DOWNLOADS=never`; to force only system Pythons, use `--no-managed-python`.
- **Pre-releases / free-threaded:** `uv python install 3.14t` (free-threaded) or a pre-release such as `3.15.0a1`. Warn that package wheels may be missing.
- **`.python-version` ignored:** an explicit `--python`, or the `UV_PYTHON` env var, takes priority. Check those first.
- **Alpine/musl or unusual architectures** may not have managed builds; use the system Python.

---

# PART G — Single-file scripts (PEP 723)

| Command | Effect |
|---|---|
| `uv init --script s.py --python 3.X` | Create a script with a metadata block |
| `uv add --script s.py requests` | Add dependency to the script's inline block |
| `uv remove --script s.py requests` | Remove it |
| `uv lock --script s.py` | Create `s.py.lock` for reproducible runs |
| `uv run s.py` | Run in an isolated, cached env built from the block |
| `uv run --with rich s.py` | Run with a one-off extra dependency |
| `uv run --python 3.X s.py` | Run with a given Python |
| `uv export --script s.py` | requirements.txt for the script |

Inline block that uv writes:
```python
# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "requests",
# ]
# ///
```

**Executable scripts (macOS/Linux):** first line, then `chmod +x s.py`:
```python
#!/usr/bin/env -S uv run --script
```
`--script` makes uv treat the file as a script even with no `.py` extension (e.g. `./backup`), and even when it sits inside a project folder.

Corner cases:
- **Script inside a project folder:** a script **with** an inline block runs isolated and ignores the project. A script **without** one runs in the project env. Say which applies if behaviour surprises the user.
- **`env -S` unsupported** (old BusyBox/Alpine, some minimal containers): the shebang fails with "No such file or directory". Run it explicitly with `uv run --script s.py`.
- **Windows ignores shebangs**: run `uv run s.py` explicitly. A `.py` association won't use uv.
- **Try a package without touching any project:**
  - `uv run --no-project --with rich python -c "import rich"`, or
  - `uvx --with rich python`

  A plain `uv run --with` inside a project **does** create/modify `uv.lock` and `.venv`.

---

# PART H — Tools (isolated CLIs; replaces pipx)

| Command | Effect |
|---|---|
| `uvx ruff check` | Run a tool once (alias of `uv tool run`) |
| `uvx --from textual textual-demo` | Command name differs from package name |
| `uvx ruff@0.6.0 check` | Specific version |
| `uvx --with mkdocs-material mkdocs serve` | Tool plus plugins, one-off |
| `uv tool install ruff` | Install, available on PATH globally |
| `uv tool install --with mkdocs-material mkdocs` | Install with plugins |
| `uv tool install --python 3.X tool` | Pin the tool's Python |
| `uv tool install --editable .` | Install your own packaged project's CLI, live-editable |
| `uv tool install --force tool` | Reinstall / overwrite existing executables |
| `uv tool list` | Installed tools |
| `uv tool upgrade ruff` / `--all` | Upgrade |
| `uv tool uninstall ruff` | Remove (**confirm**) |
| `uv tool update-shell` | Add the tool bin dir to PATH (restart shell after) |
| `uv tool dir --bin` | Show where executables go |

Corner cases:
- **"command not found" after install** → run `uv tool update-shell`, restart the shell, and check `uv tool dir --bin` is on PATH.
- **Use the project's pinned version, not uvx's, for dev tools.** For pytest, mypy and ruff inside a project, prefer `uv add --dev` + `uv run`, so everyone uses the locked version. `uvx` gets the latest, which can differ from CI.
- **Tool needs project imports** (e.g. pytest, mypy): it must run in the project env (`uv run`), not via `uvx`, or imports fail.
- `uv tool install -e .` requires a **packaged** project with `[project.scripts]`.
- **Executable name clash** with an existing binary → uv refuses; `--force` overwrites (confirm).

---

# PART I — pip-style workflow (venv + uv pip)

For non-uv projects, quick experiments, or when the user explicitly wants pip semantics.

| Command | Effect |
|---|---|
| `uv venv` | Create `.venv` (`--python 3.X` to choose) |
| `uv venv --seed` | Also install pip/setuptools into it (needed by tools that call `pip` directly) |
| `uv pip install -r requirements.txt` | Install into the active or `.venv` env |
| `uv pip install -e .` | Editable install |
| `uv pip compile requirements.in -o requirements.txt` | Pin (pip-tools replacement) |
| `uv pip sync requirements.txt` | Make env exactly match file |
| `uv pip list` / `freeze` / `show X` / `uninstall X` | As in pip |

Corner cases:
- **Never in a uv project** (see A3).
- `uv pip install` refuses to touch a system Python without a venv. `--system` overrides; use only in disposable containers and CI, never on a user's machine without asking.
- `uv venv` on an existing `.venv` asks or fails; `--clear` wipes it (confirm).
- Activation: `source .venv/bin/activate` (macOS/Linux), `.venv\Scripts\activate` (Windows). Or skip activation and use `uv run`.

---

# PART J — Recipes

**J1. New CLI app**
```bash
uv init --app --package --python 3.13 mycli
cd mycli
uv add click
uv add --dev pytest
uv run pytest
uv run mycli              # entry point from [project.scripts]
uv tool install -e .      # optional: global, live-editable
```

**J2. New library, published safely**
```bash
uv init --lib mylib && cd mylib
uv add --dev pytest
uv run pytest
uv version --bump minor
uv build --clear --no-sources
uv publish --dry-run
# confirm with user →
uv publish --index testpypi   # optional rehearsal (index defined per E)
uv publish
```

**J3. Throwaway script**
```bash
uv init --script fetch.py --python 3.12
uv add --script fetch.py requests
uv run fetch.py
```

**J4. Try a package without touching the project**
```bash
uv run --no-project --with rich python -c "import rich; print(rich.__version__)"
```

**J5. Migrate an existing codebase to uv**
```bash
# 1. Check what exists (A2). If Poetry/PDM/Pipenv: confirm migration with the user.
uv init --bare --python 3.X        # no sample files
uv add -r requirements.txt         # runtime deps
uv add --dev -r requirements-dev.txt
uv run pytest                      # verify
```
`-r` caveats:
- `==` pins in the file become exact pins in `pyproject.toml`; offer to loosen them.
- `-e`, `--hash`, `--index-url`, `-c` constraint lines, and `--find-links` lines may not carry over. Re-add them as `--editable` or `[[tool.uv.index]]` entries, or leave them out deliberately.
- **From Poetry/PDM:** move `[tool.poetry.dependencies]` into `[project] dependencies` (or use the community tool `uvx migrate-to-uv`, after confirming with the user). Keep the old lock file until tests pass.

**J6. Change Python version** → see F. Then `uv python install 3.13` (optional), `uv python pin 3.13`, `uv sync`, `uv run pytest`.

**J7. Upgrade safely**
```bash
uv tree --outdated --depth 1          # see what's behind
uv lock --upgrade-package requests    # one at a time, or:
uv lock --upgrade                     # all (confirm)
uv sync && uv run pytest
uv tool upgrade --all
uv python upgrade
```
If tests fail, `git checkout uv.lock && uv sync` restores the previous state.

**J8. Pre-release path**
```bash
uv version --bump minor --bump beta   # 1.0.0 → 1.1.0b1
uv version --bump rc                  # → 1.1.0rc1
uv version --bump stable              # → 1.1.0
```

---

# PART K — Windows

- Run commands in PowerShell. Use quotes for constraints: `uv add "requests>=2.31"`.
- Shebangs don't work; always use `uv run script.py`.
- Venv executables live in `.venv\Scripts\`, not `.venv/bin/`.
- Tool executables live in `%USERPROFILE%\.local\bin` by default; run `uv tool update-shell`, then open a new terminal.
- "Path too long" errors: enable Windows long-path support or move the project to a shorter path (e.g. `C:\dev\proj`).
- Antivirus and OneDrive-synced folders can lock files during `uv sync` ("Access is denied" / "os error 32"). Retry, or move the project out of OneDrive.
- `py` launcher Pythons are detected by uv; `--python 3.X` picks among them.

---

# PART L — Workspaces (monorepos)

A root `pyproject.toml` with `[tool.uv.workspace] members = [...]` shares one `uv.lock` and one `.venv` across packages.

| Command | Effect |
|---|---|
| `uv init packages/newpkg` | Adds `newpkg` as a member (if under the workspace root) |
| `uv init --no-workspace x` | Create a standalone project instead |
| `uv add --package pkg-a requests` | Add a dep to one member |
| `uv run --package pkg-a pytest` | Run in a member's context |
| `uv sync --all-packages` | Install all members |
| `uv workspace list` | List members |

Before `uv add` in a subfolder, check which `pyproject.toml` it will edit. uv uses the nearest member, but the lock is the root's.

---

# PART M — Private indexes and corporate settings

```toml
# pyproject.toml
[[tool.uv.index]]
name = "corp"
url = "https://artifactory.example.com/api/pypi/pypi/simple"
default = true            # replaces PyPI entirely (mirrors / Artifactory remotes)
# explicit = true         # instead: only used by packages pinned to it:
# [tool.uv.sources]
# internal-lib = { index = "corp" }
```
- **Credentials:** never put them in `pyproject.toml`. Use env vars named after the index: `UV_INDEX_CORP_USERNAME`, `UV_INDEX_CORP_PASSWORD`, or `uv auth login <url>`, or a `.netrc` / keyring.
- **One-off:** `UV_DEFAULT_INDEX=https://...` or `--default-index`.
- **Dependency confusion:** uv by default stops at the first index containing a package (`first-index` strategy), which protects against public look-alikes. Don't change `index-strategy` to `unsafe-best-match` unless the user asks.
- **Certificates:** `UV_SYSTEM_CERTS=1` (uv ≥ 0.11; older: `UV_NATIVE_TLS=1`) or `SSL_CERT_FILE`.
- **Proxy:** uv honours `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY`.
- **Machine-wide settings** go in `~/.config/uv/uv.toml` (Windows: `%APPDATA%\uv\uv.toml`). Use `--no-config` to rule them out when debugging.

---

# PART N — CI, Docker, and exporting

**CI (any provider):**
```bash
uv sync --locked            # fails if uv.lock is out of date with pyproject.toml
uv run --frozen pytest      # never re-resolve during the run
```
Cache `$(uv cache dir)` between runs and run `uv cache prune --ci` at the end. GitHub Actions: `astral-sh/setup-uv`.

**Docker (sketch):**
```dockerfile
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev --no-install-project
COPY . .
RUN uv sync --locked --no-dev
CMD ["uv", "run", "--no-sync", "python", "-m", "myapp"]
```
Pin the uv image tag (e.g. `:0.11`) for reproducibility instead of `:latest`.

**Export for other tools:**
```bash
uv export --format requirements.txt --no-dev -o requirements.txt          # with hashes
uv export --format requirements.txt --no-hashes --no-dev -o requirements.txt
```
`uv export` reads the lock; use `--frozen` if the lock must not change.

---

# PART O — Misc and maintenance

| Command | Effect |
|---|---|
| `uv format` | Format with Ruff (downloads Ruff on first use; needs network) |
| `uv format --check` / `--diff` | Check only, or show the diff |
| `uv help <cmd>` | Help |
| `uv --version` | uv version |
| `uv self update` | Update uv (**confirm**; only for installer-based uv; pip/pipx/Homebrew installs update via that tool) |
| `uv cache dir` | Cache location |
| `uv cache prune` | Remove unused cache entries (safe) |
| `uv cache clean` | Wipe the whole cache (**confirm**; next installs re-download) |
| `uv run --env-file .env ...` | Load env vars from a file |

If `uv format` is unavailable (older uv) or offline, use `uv run ruff format` with ruff as a dev dependency, or `uvx ruff format` when online.

---

# PART P — Troubleshooting

| Symptom | Fix |
|---|---|
| `uv: command not found` | Install (A1), restart shell, check PATH (`~/.local/bin`) |
| `unrecognized subcommand` / unknown flag | uv too old (A7): `uv --version`, update with confirmation, or use fallback |
| Package installed with `uv pip install` vanished | Exact sync (A3). Use `uv add` or `uv run --with` |
| `VIRTUAL_ENV ... does not match ... will be ignored` | Expected (A4). `--active` to use the active env |
| `Project is already initialized` | Don't re-init; use `uv add`/`uv sync` |
| New project unexpectedly joined a workspace | Remove it from `members`, or recreate with `--no-workspace` |
| `cannot get or set dynamic project versions` | Version comes from VCS; bump with git tags (E) |
| `failed to lookup address` / `dns error` | No network (A6): `--offline` once, then stop |
| Certificate errors | `UV_SYSTEM_CERTS=1` / `SSL_CERT_FILE` (A6, M) |
| `UV_NATIVE_TLS is deprecated` warning | Switch to `UV_SYSTEM_CERTS` |
| `No solution found when resolving` | Read the conflict, relax bounds or `requires-python` with user (D) |
| `The lockfile ... needs to be updated` (with `--locked`) | Run `uv lock` locally and commit `uv.lock` |
| Pinned Python not used | Check `--python`, `UV_PYTHON`, `.python-version`, `requires-python` (F) |
| Python download fails | Blocked (A6/F): use system Python |
| Tool not on PATH | `uv tool update-shell`, restart shell |
| `uv build` produced nothing / error "no build backend" | Project lacks `[build-system]` (C, E) |
| Upload rejected "file already exists" | Bump version; clean `dist/` with `uv build --clear` |
| Permission/read-only errors in cache | `UV_CACHE_DIR=/tmp/uv-cache` |
| Windows "Access is denied" during sync | Close running Python processes; move off OneDrive (K) |
| Something odd from global config | Retry with `--no-config` (M) |

---

# PART Q — Files uv manages (commit or not)

| File | Commit? | Notes |
|---|---|---|
| `pyproject.toml` | Yes | Source of truth |
| `uv.lock` | Yes (apps and libraries) | Never hand-edit; regenerate with `uv lock` |
| `.python-version` | Yes, usually | Remove from git if the team wants flexible versions |
| `.venv/` | **No** | Disposable; recreate with `uv sync` |
| `dist/` | No | Build output |
| `*.py.lock` (script locks) | Yes, if reproducibility matters | |

One-line summary: `init` creates, `add`/`remove` edit dependencies, `sync` installs, `run` executes, `lock --upgrade-package` upgrades, `tree --outdated` inspects, `python pin|install` handles interpreters, `uvx`/`tool` handles CLIs, `init --script` handles single files, `version --bump` + `build --clear` + `publish` ships. Confirm before anything permanent.
