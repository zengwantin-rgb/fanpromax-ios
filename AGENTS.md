# Required execution environment

The user explicitly prohibits compilation and validation on the workspace server.

- Use this server only for source/document edits, Git operations and viewing GitHub-hosted logs or reports.
- Perform compilation, automated tests, syntax/source validation, binary or archive inspection, signing, packaging and release verification exclusively in GitHub Actions on GitHub-hosted macOS runners.
- Do not run local native binaries, unit tests, Python/Unicorn tests, py_compile, archive verifiers, APK/IPA/ELF/Mach-O parsers or delivery verification scripts here.
- Editing files using a script is allowed; running a validation script is not.
- Do not download APK/IPA/dylib binaries to this server for analysis or verification. Original user inputs may be transferred encrypted for analysis on the authorized hosted runner.
- Keep the repository private. Do not publish raw device logs, credentials or third-party binary inputs.

# Current scope

Target: iPhone 15 Pro Max, iOS 17.0, TrollStore; GitHub owner zengwantin-rgb.
The user explicitly excludes aiming/aimbot and recoil compensation. Do not implement those features.
Do not represent unported Android features or unresolved game-control permissions as implemented.
