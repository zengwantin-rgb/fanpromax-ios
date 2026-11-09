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

The user explicitly selected an integrated game IPA for character acceleration, vehicle flight, invincibility and damage reduction; aiming and recoil remain excluded. Worktree /root/fanpromax-ios-integrated, branch analysis/integrated-controls contains the new in-process module and full instructions. Integrated i1 published at integrated-9ac6158aaa63, compiled SHA 9ac6158aaa63d547e21aebf6cbbb4fd1162c27d5; hosted run 42710519212 build/UI/publish all succeeded. Draft PR #1 keeps the external main unchanged until device feedback. The module implements guarded character speed-field and vehicle physics experiments only; actual game startup/speed/flight remain unverified. Invincibility and damage reduction are NOT implemented: inspected GodMode/DamageScale native methods are immediate returns. PrimitiveComponent singleton is 0x80ae820 (factory 0x59a0718), NOT the display type slot. SOURCE_INPUT_TOKEN was removed after hosted work; no raw device reports were uploaded, no local compilation/validation or archive/binary inspection performed. Read Integrated README and analysis/integrated-feasibility.md on that branch before continuing.

Latest device evidence: integrated-i1 profile_ready=true and task_count=3475, historical speed_field_writes_confirmed=22 but both speed leases inactive and character unavailable while user explicitly confirms alive and walking. This proves module/game-task execution, not sustained 3x speed. Flight calls=0 while walking is expected; i1's restored label was not proof of a flight operation. Integrated i2 published at integrated-c1f92ca3f01d, compiled SHA c1f92ca3f01d6dcbb732907db73b90e958321dd9; hosted run 42714212191 build/UI/publish all succeeded. It verifies local ownership before pinning the controller, retains cleanup baselines when local identity is transiently unavailable, and exports context stage/generations/alive/mode/eligibility and last speed write time. Actual i2 fix remains unverified. Work in /root/fanpromax-ios-integrated on analysis/integrated-controls, PR #1. SOURCE_INPUT_TOKEN has again been removed. No local build/tests/validation or binary/archive inspection, no raw device JSON uploaded.

User reported self-injecting/replacing i2 produced a persistent black screen with no F button, then explicitly confirmed the game opened after rebooting the phone. Cause is NOT established; do not claim injection corruption, cache issues or a code fix. Continue i2 alive-walking device validation before changing startup code. The additional static i1/i2 loader audit run 42716944452 did NOT start: GitHub check annotation says recent account payments failed OR spending limit needs increase. No audit script ran and no module-comparison conclusion exists. This does not invalidate completed i2 build/UI/publish run 42714212191. Do not switch repo public or compile/inspect on the workspace server as a workaround; repository remains private.
