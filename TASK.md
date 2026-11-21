# SBOM-Gen.sh implementation task

Improve `SBOM-Gen.sh` and implement all changes discussed for the `improve-sbom-gen` branch.

## Credential profile support

- Add `--profile NAME` and `-p NAME` command-line arguments.
- Support `VERACODE_API_PROFILE` as an optional fallback when `--profile` is not supplied.
- Preserve existing default credentials behavior when neither option is provided.
- Pass the selected profile name to the Veracode HTTPie/API signing integration so that `veracode-api-signing` extracts credential values from the credentials file.
- Do not parse credentials, read credential values, export API key variables, print secrets, or otherwise handle credentials directly in the script.
- Use the exact profile-selection mechanism supported by the installed `veracode-api-signing`/HTTPie integration. Add a short comment explaining the integration assumption.
- Validate that a profile argument is present and non-empty. Reject unknown command-line arguments with usage help.
- Do not log credentials or credentials-file contents in debug mode.
- Recommend or document file permissions for the credentials file, but do not read or modify credentials in the script.

## Bash and general reliability

- Add `#!/usr/bin/env bash` and fail-fast settings:
  - `set -Eeuo pipefail`
  - `IFS=$'\n\t'`
- Check `http`, `jq`, `stty`, and `python3` when required before starting.
- Handle interrupted scripts and restore terminal cursor and echo state on exit or termination.
- Quote paths and variables consistently.
- Create `.sbom` safely relative to the script location or another explicit output directory.
- Do not change the working directory merely to create or use `.sbom`.
- Avoid shell aliases and text mode expansion of aliases.
- Replace `http` aliases with a small `veracode_http` wrapper.
- Enable HTTP status checking and a reasonable timeout when supported by HTTPie.
- Retry only transient HTTP failures if implementation is reliable and clear.
- Validate fetched JSON with `jq -e` before extraction.
- Exit with actionable errors for API, authentication, network, missing data, or invalid JSON failures.
- Add dependency and credential configuration diagnostics without exposing secrets.

## Menu fixes and improvements

- Fix the Agent-Based branch conditional. It must use Bash syntax and must not execute the choice as a command.
- Improve menu terminal handling:
  - Use fixed-format `printf` strings instead of interpolated format strings.
  - Restore the cursor blink state and terminal echo reliably.
  - Replace `((idx++))` patterns that can interact badly with `set -e`.
  - Keep up/down wrapping and Enter selection behavior.
  - Keep the maximum-menu option behavior reasonable.
- Keep menu selection output clear and correct (`Chosen index`, `Chosen value`).
- Avoid relying on function return codes for selected indices. `select_option` may continue to return indices if kept, but selection logic should not confuse status codes with menu values.

## JSON extraction

- Replace fragile `grep`/`cut` parsing with `jq`.
- Use paired arrays for names and IDs; do not independently extract arrays and assume two extraction results remain aligned.
- Extract application GUID and profile name from `_embedded.applications`.
- Extract workspace ID and name from `_embedded.workspaces`.
- Extract project ID and name from `_embedded.projects`.
- Skip items with missing or empty IDs/names where appropriate.
- Handle names and IDs containing unusual characters safely.
- Rebuild menu options from paired arrays.
- Report no applications, workspaces, or projects with a clear error instead of selecting an empty array.

## Agent-Based and Application Profile behavior

- Fix and preserve application-profile SBOM generation.
- Fix and preserve agent-based workspace/project selection and SBOM generation.
- Ensure the project list belongs to the selected workspace.
- Ensure project type remains `agent` and SBOM generation type remains `agent` for agent-based output.
- Ensure application SBOM generation continues to request `type=application`.
- Generate consistent `.json` output filenames:
  - Application: `.sbom/application-${guid}.json`
  - Agent project: `.sbom/project-${project_id}.json`
- Do not overwrite an existing SBOM unless the user explicitly chooses to or the script documents this behavior.
- Echo the actual absolute or script-relative output path after successful generation.

## Path and filename safety

- Derive `SCRIPT_DIR` from `BASH_SOURCE[0]`.
- Define `OUTPUT_DIR="${SCRIPT_DIR}/.sbom"` or document another explicit output option.
- Validate API IDs before using them as filenames or URL path components.
- Permit only safe API identifier characters in target IDs, with a clear rejection for unexpected values.
- Quote URLs and output paths in every API call.

## Code structure

- Define focused functions such as:
  - `usage`
  - `die`
  - `require_command`
  - `cleanup_terminal`
  - `veracode_http`
  - `fetch_json`
  - `load_*` functions for JSON extraction
  - `select_option`
  - `generate_application_sbom`
  - `generate_agent_sbom`
  - `main`
- Replace `my_array`, `my_arrayy`, `idoutput`, `nameoutput`, and `options` with descriptive names.
- Use constants for API base URLs and SBOM API endpoints.
- Use `readonly` for constants and environment-derived configuration.
- Keep SBOM selection and API logic separate enough to test independently.
- Preserve the original author/license comments and add comments explaining profile selection and robust parsing.

## Debug behavior and output

- Replace numeric debug handling with `DEBUG=${DEBUG:-0}` or a standard `--debug` option.
- Debug output may show API response structure or item names/IDs, but must not reveal credentials or secret-bearing environment variables.
- Correct typos such as `Choosen`, `Prfoile`, and equivalent text.
- Add clear success and failure messages.

## Documentation

- Update `README.md` with:
  - Installation prerequisites for HTTPie, `veracode-api-signing`, and `jq`.
  - Usage examples:
    - `./SBOM-Gen.sh`
    - `./SBOM-Gen.sh --profile production`
    - `VERACODE_API_PROFILE=production ./SBOM-Gen.sh`
  - Explanation that profiles come from the standard Veracode credentials file.
  - A statement that this script does not read or handle credential values directly.
  - Example credential-file section names, without example secrets.
  - The existing default profile behavior.
  - Output location and filename conventions.

## Validation

- Run `bash -n SBOM-Gen.sh`.
- Run `shellcheck SBOM-Gen.sh` and address findings.
- Exercise both menu branches with mocked API/HTTP responses.
- Test profile argument precedence: `--profile` should override `VERACODE_API_PROFILE` and the default profile.
- Test missing profile argument, unknown arguments, missing dependencies, empty API collections, invalid JSON, and HTTP failures.
- Test `Ctrl+C` terminal cleanup.
- Confirm no credentials or credential-file contents are printed in normal or debug output.
