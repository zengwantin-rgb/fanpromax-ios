# Movement review, 2026-11-10

The current integrated-i3.1 candidate does not meet the requested movement outcome. Comparable steady local displacement windows were approximately 6.4 m/s at normal speed and 8 m/s at selected 3x (about 1.25x). The user reports vehicle ascent followed by rollback. Person flight is not implemented. Readback and native call counts are not verification of movement or server acceptance.

No new phone candidate is published by these review workflows. Original binary inputs remain private; analysis runs on GitHub-hosted macOS only. Reports contain derived text, not raw device logs.

## APK implementation now recovered

Pinned APK SHA256: `02d6e9e30f0f25865552c75ae66e625c0466b017114ba9e5051edb60655024d9`.
Pinned extracted ELF SHA256: `5f4ba230657469e44105de501afb5cd98da7e5b71cdfa6bfeca481180b1bd8b6`.

Hosted review: https://github.com/zengwantin-rgb/fanpromax-ios/actions/runs/42727551768
Derived text: https://github.com/zengwantin-rgb/fanpromax-ios/releases/tag/motion-review-77e02a3a2564

- Flight worker `0xa2f4b0`, bounded by unwind records, reads the flight button and rotation button. It resolves its target through `0xa32698` and `0xa32a28`, using a configured chain or multiple fallback chains.
- It computes horizontal components from direction and a UI value, reads a third float at target+0x164, alternates adjustments to that float, and submits a 12-byte vector to target+0x15c through `0xe3f094`. It also submits zeros to target+0x168. The writer wrapper dispatches through a backend virtual function. These offsets do not establish the corresponding iOS object or field identity.
- Flight diagnostics value 6 is stored after those calls without checking their return values. Therefore that diagnostic alone would not establish even successful writes, much less stable flight.
- The normal active loop requests a 5 ms sleep; idle handling uses 50 ms. These are requested sleep durations, not measured execution frequency.
- Speed toggle at drawing-global+0x754 leads to worker `0xa2fa9c` and operation `0xa32c30`. This was missed by the earlier named-render-worker-only inspection because the routines are stripped.
- The speed operation uses configured pointer/field offsets, periodic parameter changes, input-dependent component additions, a downward adjustment and input-component clearing. This is materially different from multiplying the two iOS walking fields. It is not proof of stable selected-multiplier motion on either platform.
- Configured offsets, remote-memory backend semantics and actual game object identities need further evidence. No input was executed, and no authorization service was contacted. No claim is made that the APK prevents correction or implements person flight successfully.

## iOS final speed policy

Cached hosted disassembly shows `0x1c6cc90` computes final speed using several branches and multipliers. At `0x1c6d388` it calls `0x2300a78` with the owning character, then selects the smaller value. The helper reads character+0xbf0 and character+0xbf8 and computes `a + (b - a)`; for ordinary finite values this approximates b, subject to floating-point rounding. This is a candidate independent cap, not a proven cause of the measured 8 m/s plateau. The phone log did not preserve that field value.

A separate hosted review examines the character constructor and the speed-policy context. The original lacks usable LC_FUNCTION_STARTS metadata, so fallback outputs explicitly say bounded context rather than claiming recovered complete functions. No cap write is added on the strength of a guessed field name.

## Remaining verification gaps

- Establish the cap's initialization and update semantics before changing it.
- Establish the Android vector target's actual identity before considering a corresponding iOS operation.
- Preserve native final-speed and independent-cap observations alongside each historical movement window; currently exporting in a car replaces current-context observations.
- Local ascent followed by rollback is real user evidence, but its exact source is not identified by existing logs. Static client analysis cannot prove acceptance by the live game server.
- Do not ask for another routine reinstall merely to repeat existing observations. A later device check must answer a specific unresolved runtime question after offline work is complete.

## Constructor follow-up result

Hosted run https://github.com/zengwantin-rgb/fanpromax-ios/actions/runs/42727977651 completed successfully. Text: https://github.com/zengwantin-rgb/fanpromax-ios/releases/tag/ios-motion-review-2cdea86d0aca . The constructor entry at 0x22c28b8 is only a tail branch to 0x22bc520; adjacent instructions must not be treated as its body. In the followed constructor context, 0x22be29c stores bit pattern 0x44228000 (650.0f) to character+0xbf8, and 0x22be2a4 stores 0x43fa0000 (500.0f) to +0xbf0. This contradicts an assumption that the observed 800 cm/s plateau itself establishes a fixed 800 cap in this field. Runtime updates/other branches remain unresolved. No speculative multiplier write was added.

The actual 3x and stable-flight goals remain unmet. This review completes the bounded offline comparison, not those runtime goals. Current i3.1 remains an unsuccessful experiment for those goals. Person flight remains absent. All inspections were hosted macOS; no workspace binary inspection/build/test was performed.
