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

0.2.2 published at ios-636c6d2d389a, compiled SHA 636c6d2d389a42e133a72b6e9d02a1d17ae6485b; hosted run 42699437092 build/UI/publish all succeeded. Native, standard/large-text UIKit, 195 signature pages, CRC and cloud publication source/digest checks passed. Actual device startup/display/touch recovery remains unverified.

New 0.2.2 device logs show hosting and deferred setup returned with a heartbeat about 82 seconds later, sampling intentionally off, and no reported signal-11 exit. HID/AX/UIKit counts remain zero; receiver setup reason is sink_interface_unavailable. Logs lack the actual signature, so do not claim selector absence or annotated encoding as proven cause. 0.2.3 adds object-encoding compatibility, guarded object-ivar KVC, readback and actual signature diagnostics. Actual tap/drag still unverified.

0.2.3 published at ios-8ee16dcbaeb2, compiled SHA 8ee16dcbaeb22cc2ae00b4418d1903aa101a5f0c; hosted run 42702714898 build/UI/publish all succeeded, 195 signature pages and CRC verified. Annotated-object signature, guarded KVC and sink readback tests passed in standard/large-text UIKit. Simulator metadata is iOS18.6, setter absent; not equivalent to device iOS17.0. Actual device touch remains unverified. All build/test/publication verification stayed on hosted macOS; raw phone logs were not uploaded.

The user has now explicitly selected an integrated game IPA for character acceleration, vehicle flight, invincibility and damage reduction; aiming and recoil remain excluded. In-process changes for the selected controls are authorized. Keep the external App unchanged. Do not represent client fields, static names or model tests as proven server effects; invincibility and damage reduction have no verified implementation. All compilation/inspection/packaging/tests remain hosted-macOS only.

Integrated i1 published at integrated-9ac6158aaa63, compiled SHA 9ac6158aaa63d547e21aebf6cbbb4fd1162c27d5; hosted run 42710519212 build/UI/publish all succeeded. Actual game startup, controls, speed and flight remain device-unverified. Invincibility and damage reduction are NOT implemented. GodMode target 0x1ca7564 and DamageScale target 0x1ca66ec are immediate returns in the pinned client. PrimitiveComponent singleton is 0x80ae820, confirmed via 0x59a0718; do not substitute display-related type slots. SOURCE_INPUT_TOKEN was removed after hosted work; any future source download needs temporary authorized access to the original private input, without exposing tokens or running local binary checks. Old unpublished integrated draft candidates were removed.
