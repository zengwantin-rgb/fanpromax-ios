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

# Device evidence to preserve

For 0.2.0 on iPhone 15 Pro Max / iOS 17.0, the user confirms the lobby overlay is visible but corrected an earlier statement: dragging does NOT work. The user then confirmed that both simple taps and drags do not work. Do not record dragging as verified. Device reports acquire the game's read port and camera with no read error. The lobby snapshot has no remote target markers; do not treat that as failed sampling. The `event_loop_prepared` flag describes only the dispatcher/fetcher setup branch, not overall touch functionality. Game control still returns 5 and no game memory was written. Real-match target display remains unverified. Never upload raw device reports.

Version 0.2.1 has a real-device SIGSEGV (signal 11) report on iOS 17.0 and is withdrawn from recommendation. No stack trace was provided; the last status was window registration. Version 0.2.1 was published at ios-b45a0d970b80 after hosted build/UI/publication checks. It repairs the input bootstrap and adds input/drag persistence diagnostics; actual device tap/drag repair remains unverified. Do not turn the model or simulator pass into a device-success claim.

Version 0.2.2 removes system instruction scanning, inferred installer calls and custom UIApplication initialization. Receiver connections occur after window hosting; startup.json preserves stages. Do not claim device startup or touch recovery before actual feedback.
