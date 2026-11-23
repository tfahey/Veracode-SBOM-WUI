# SBOM-Gen.sh Improvement - Phased Approach

## Overview

This document outlines a phased approach to implement all requirements from TASK.md. Each phase builds on the previous one and maintains a baseline of preserved functionality.

---

## Existing Functionality to Preserve (Baseline)

### Core Capabilities
1. **Application Profile SBOM Generation**
   - Fetch applications list from Veracode API
   - Display interactive menu of applications
   - Generate SBOM for selected application with `type=application`
   - Output to `.sbom/[guid].json` (current naming)

2. **Agent-Based SBOM Generation**
   - Fetch workspaces list from Veracode API
   - Display interactive menu of workspaces
   - Fetch projects for selected workspace
   - Display interactive menu of projects
   - Generate SBOM for selected project with `type=agent`
   - Output to `.sbom/[project_id].json` (current naming)

3. **Interactive Menu System**
   - Up/Down arrow key navigation
   - Enter to select
   - Up/Down wrapping behavior
   - Terminal cursor and echo state restoration
   - Ctrl+C interrupt handling

---

## Phase 1: Foundation & Shell Safety

**Goal:** Establish fail-fast shell settings and error handling without changing logic or return value handling.

### Changes
- Add `#!/usr/bin/env bash` shebang
- Add `set -Eeuo pipefail` for fail-fast
- Add `IFS=$'\n\t'` for safe word splitting
- Add error handling functions: `usage()`, `die()`, `require_command()`
- Add trap setup for cleanup on INT/TERM signals
- Add `cleanup_terminal()` to restore cursor/echo
- Extract `SCRIPT_DIR` and define `OUTPUT_DIR` constants
- Add `check_dependencies()` for http, jq, stty validation
- Fix syntax error on line 214: `elif "$choice"` → `elif [ "$choice" ]`
- Add `DEBUG` environment variable support

### Critical Constraint
**Do NOT change `select_option()` function's return mechanism** - it must continue using `return $index`

### Test Coverage
- Menu navigation works (up/down/enter)
- Both SBOM generation paths work
- Ctrl+C restores terminal cleanly
- Application and agent SBOMs generate valid JSON
- bash -n and shellcheck pass

### Commits
- `P1-01: Shebang and fail-fast settings`
- `P1-02: Error handling and trap setup`
- `P1-03: Constants and dependency checks`
- `P1-04: Fix conditional syntax error`

---

## Phase 2: Argument Parsing & Profile Support

**Goal:** Add `--profile` and `VERACODE_API_PROFILE` support without breaking default behavior.

### Changes
- Implement `parse_arguments()` function for `--profile`, `--debug`, `--help` flags
- Support `VERACODE_API_PROFILE` environment variable fallback
- Pass selected profile to `veracode-http` via `VERACODE_API_PROFILE` export
- Validate profile argument is non-empty
- Reject unknown arguments with usage help
- Add argument parsing to `main()` entry point
- Update `usage()` with profile examples and credential file guidance

### No Changes To
- `select_option()` function - return mechanism stays identical
- Application or agent SBOM generation logic
- Menu behavior

### Test Coverage
- Works without `--profile` (default behavior preserved)
- `./SBOM-Gen.sh --profile production` recognizes profile
- `VERACODE_API_PROFILE=prod ./SBOM-Gen.sh` recognizes env var
- `--profile` overrides `VERACODE_API_PROFILE`
- All baseline functionality still works

### Commits
- `P2-01: Add parse_arguments() function`
- `P2-02: Implement profile support and precedence`
- `P2-03: Update usage and documentation`

---

## Phase 3: Code Structure & Function Refactoring

**Goal:** Extract helper functions to reduce duplication and improve testability without changing behavior.

### New Functions
- `fetch_json()` - wrapper for `veracode-http` with error handling
- `load_applications()` - fetch and parse applications (using existing grep/cut, not jq yet)
- `load_workspaces()` - fetch and parse workspaces
- `load_projects()` - fetch projects for a workspace
- `generate_application_sbom()` - generate application SBOM
- `generate_agent_sbom()` - generate agent-based SBOM

### No Changes To
- JSON extraction methods (still use grep/cut, not jq)
- Menu behavior
- Argument parsing

### Test Coverage
- Functions can be called independently
- Error handling is preserved
- All baseline functionality still works

### Commits
- `P3-01: Extract fetch_json() helper`
- `P3-02: Extract load_applications() and load_workspaces()`
- `P3-03: Extract load_projects() and generation functions`
- `P3-04: Refactor main() to use extracted functions`

---

## Phase 4: JSON Extraction Modernization

**Goal:** Replace fragile grep/cut parsing with robust jq paired arrays.

### Changes
- Replace each grep/cut extraction with `jq` queries using `-e` for validation
- Implement paired arrays pattern for IDs and names (don't extract separately)
- Extract application GUID and profile name from `_embedded.applications`
- Extract workspace ID and name from `_embedded.workspaces`
- Extract project ID and name from `_embedded.projects`
- Skip items with missing/empty IDs or names
- Handle special characters safely in names/IDs
- Add empty collection error messages

### New Helper Functions
- `extract_paired_array()` - generic paired array extraction
- `validate_json()` - validate JSON before extraction

### Test Coverage
- Exact same filenames generated: `.sbom/[guid].json`, `.sbom/[project_id].json`
- Menu displays same applications/workspaces/projects
- Empty collection error handling
- Invalid JSON error handling
- Special characters in names handled safely
- All baseline functionality still works

### Commits
- `P4-01: Add jq-based extraction helper functions`
- `P4-02: Migrate application extraction to jq with paired arrays`
- `P4-03: Migrate workspace and project extraction to jq`
- `P4-04: Add paired-array safety validation`

---

## Phase 5: Menu Improvements & Terminal Handling

**Goal:** Improve `select_option()` reliability while preserving menu behavior.

### Changes
- Use fixed-format `printf` strings (no interpolation)
- Improve terminal state restoration reliability
- Replace `((idx++))` patterns with safe alternatives
- Fix typos: "Choosen" → "Chosen", "Prfoile" → "Profile"
- Ensure proper cursor blink restoration
- Ensure proper echo restoration on Ctrl+C
- Support safe return code handling in `select_option()`

### Test Coverage
- Menu navigation works (up/down/enter)
- Selection works and generates SBOM
- Wrapping behavior preserved
- All applications still generate SBOM
- All agent projects still generate SBOM
- Terminal state properly restored on exit
- Ctrl+C handling works

### Commits
- `P5-01: Improve printf formatting in select_option()`
- `P5-02: Enhance terminal state restoration`
- `P5-03: Fix menu selection return handling`
- `P5-04: Fix typos in output messages`

---

## Phase 6: Path Safety & Filename Validation

**Goal:** Secure API ID usage and prevent injection attacks.

### Changes
- Validate API IDs contain only safe characters `[a-zA-Z0-9._-]`
- Reject any ID with unsafe characters with clear error
- Quote all URLs in API calls
- Quote output paths in all commands
- Ensure no directory traversal via `.sbom/../etc` attack
- Update filenames to follow spec: `application-${guid}.json`, `project-${id}.json`

### Test Coverage
- Normal GUIDs/IDs generate correct filenames
- Special characters in names (not IDs) handled safely
- Invalid IDs rejected with clear error
- All baseline functionality still works

### Commits
- `P6-01: Add ID validation for safe characters`
- `P6-02: Quote URLs and paths consistently`
- `P6-03: Update filename formats per spec`

---

## Phase 7: Documentation & Help

**Goal:** Update documentation to reflect all changes.

### Changes
- Update `README.md` with:
  - HTTPie, veracode-api-signing, jq installation steps
  - Usage examples: default, `--profile`, env var
  - Credential file format explanation
  - Output location and filename conventions
  - Note that script doesn't handle credentials directly
- Update error messages for clarity
- Add comments explaining profile selection mechanism
- Add comments explaining paired array approach
- Add comments explaining JSON validation strategy

### Test Coverage
- Documentation accuracy verified
- Examples all work as documented

### Commits
- `P7-01: Update README with installation and usage`
- `P7-02: Add code comments for complex sections`

---

## Phase 8: Final Validation

**Goal:** Comprehensive validation of all functionality.

### Validation Checklist
```
Bash Validation:
  ✓ bash -n SBOM-Gen.sh
  ✓ shellcheck SBOM-Gen.sh
  
Credential Profile Testing:
  ✓ Works with default credentials
  ✓ --profile argument recognized
  ✓ VERACODE_API_PROFILE env var recognized
  ✓ --profile overrides env var
  ✓ Rejects empty profile name
  ✓ Rejects unknown arguments

Application Profile SBOM:
  ✓ Menu displays applications
  ✓ Selection generates SBOM
  ✓ Output filename: application-${guid}.json
  ✓ JSON output is valid

Agent-Based SBOM:
  ✓ Workspace menu displays
  ✓ Project menu displays for workspace
  ✓ Selection generates SBOM
  ✓ Output filename: project-${id}.json
  ✓ JSON output is valid

Error Handling:
  ✓ Missing dependencies detected
  ✓ API failures show clear error
  ✓ Invalid JSON shows clear error
  ✓ Empty collections show clear error
  ✓ Ctrl+C restores terminal cleanly
  
Edge Cases:
  ✓ Special characters in names handled
  ✓ Very long names handled
  ✓ Empty names rejected
  ✓ Missing IDs rejected
  ✓ Invalid IDs rejected
  
Debug Mode:
  ✓ --debug shows helpful output
  ✓ No credentials exposed in debug
  ✓ No secret env vars exposed
```

### Test Automation
- Create test suite that mocks API responses
- Test all error conditions
- Verify filenames and content
- Validate no credentials are exposed

### Commits
- `P8-01: Add comprehensive test suite`
- `P8-02: Final validation and cleanup`

---

## Success Criteria

- ✓ All TASK.md requirements implemented
- ✓ All baseline functionality preserved and working
- ✓ No existing menu functionality broken
- ✓ Both SBOM generation paths work correctly
- ✓ `bash -n` and `shellcheck` pass
- ✓ Credentials never logged or exposed
- ✓ Error messages are clear and actionable
- ✓ Terminal state properly restored on exit
- ✓ Code is well-structured with focused functions
- ✓ Documentation is accurate and complete

---

## Timeline Estimate

- **P1:** 1-2 hours (foundation is straightforward)
- **P2:** 1-2 hours (profile support is well-scoped)
- **P3:** 2-3 hours (refactoring with testing)
- **P4:** 4-5 hours (most complex; highest risk; needs extensive testing)
- **P5:** 2-3 hours (menu improvements; terminal testing)
- **P6:** 1-2 hours (validation and security)
- **P7:** 1 hour (documentation)
- **P8:** 2-3 hours (comprehensive validation)

**Total: 14-21 hours of focused development**

