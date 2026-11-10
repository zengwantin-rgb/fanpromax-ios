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

## Direct-reference scan and diagnostic repair

Hosted scan https://github.com/zengwantin-rgb/fanpromax-ios/actions/runs/42729855356 completed. It finds 1,541 direct unsigned-offset references to +bf0/+bf8 across the executable, including unrelated arrays, stack locations, rendering state and arithmetic buffers. This is a candidate search, not an object-type proof or exhaustive alias analysis. For example 0x23e7f58 increments an array count at +bf8 and must not be treated as updating a character speed cap. No character-specific runtime update to 800 was established. The initial per-context upload was canceled and its partial release removed; the completed run bundles contexts into a single text report.

Source `integrated-i3.2-review` repairs the existing misleading flight result: a successful void native setter call alone no longer yields readback success. It checks immediate velocity readback and ongoing gravity ownership; ignored writes, unavailable readback and game-side gravity changes have regression cases. The history now stores an immutable `end_sample_context` after speed-field handling, so exporting after entering a vehicle preserves the relevant walking observations. These are diagnostic/ownership fixes, not a speed or rollback fix.

Automatic IPA packaging and release are disabled for ordinary pushes. Explicit workflow dispatch with publish_candidate=true is required to package and release; ordinary pushes still compile/sign-check the module and run hosted tests/UI. No new installation request follows from these checks.

Hosted build/UI run https://github.com/zengwantin-rgb/fanpromax-ios/actions/runs/42729995197 succeeded for runtime commit `0a3142cc1f12d174d495df539f19c2eac7ab4515`. Native restoration/flight/motion/context tests, profile checks, ARM64 module compile/sign verification and simulator UIKit checks passed. Packaging, staging and publication were skipped as intended; no new phone candidate was produced. This is not live-game validation.

## Mode and physical-read follow-up

Hosted run https://github.com/zengwantin-rgb/fanpromax-ios/actions/runs/42730799790 succeeded. In the pinned movement vtable, slot 0x5d8 resolves to 0x5056224: it requires movement+0x298 == 3 and a non-null +0x100 pointer. Thus the early GetMaxSpeed return of +0x17e8 cannot be selected while movement mode is 1 (the walking eligibility condition). Slot 0x5e8 requires mode 4. This excludes that early branch as a direct explanation for an otherwise mode-1 sample; it does not establish which later clamp was active during every historical window.

The native velocity wrapper 0x5517194 reaches body getter 0x54910e0, which invokes a callback through the handle at body+0x138. Callback 0x549d6a8 checks that handle through 0x54c2cd8 and calls 0x54c4e88 for its velocity. Invalid handles produce a zero vector. No correspondence to the APK's raw target+0x15c layout is established. In particular, a matching zero velocity does not prove a physical body was present or that a command changed it. Readback remains an immediate numeric observation, not sustained-flight proof.

All temporary cross-repository access used for the completed reviews was removed. Remaining blockers are identifying the actual runtime speed-policy branch/values and the cause of position rollback. Static references and constructor defaults alone cannot reconstruct those observations from the existing phone export.

## i4 functional speed change

Runtime commit 51a35ef8dcac1fdfddc1838df61ac72d0f79cdfe adds SpeedPolicyLease. It restores held baseline fields, samples the original native final speed, scales the two movement fields plus character+bf8, then verifies the resulting native speed against original*selected multiplier within the same game-thread task. It restores all safely owned fields and stops on mismatch. Same-task native-ratio verification is distinct from actual movement or server acceptance. The constructor and original native clamp helper/selection bytes are fingerprinted before this new field is used.

The original AArch64 cap helper and clamp-selection instructions were emulated on hosted macOS with 24 synthetic combinations (computed values 640/900, caps 650/800/1000, multipliers 1/1.6/2/3). Scaling only computed speed can reproduce truncation; scaling the cap too restores the expected ratio for this specific branch. These values are artificial test states, not a claim that the user's cap was measured at 800. Full GetMaxSpeed and server simulation were not emulated.

Regression tests cover no compounding, changing the native baseline, independent unmodified clamps, partial write rollback, cancellation, game edits and recycled objects. A new flight-motion window stores relative height and observed vertical velocity, with early records for candidate discontinuities; it does not attribute them to the server. Continuous ascent/descent and identity/request/time-gap resets are covered.

The initial emulator install attempt used a version without a compatible macOS wheel; the workflow now pins the available 2.1.4 wheel. An earlier i4 candidate delivery was canceled before publication to include flight motion evidence in the same package. The final delivery run is 42732886395. This is a concrete client-control fix plus an observation gap repair; stable live-game acceleration and flight still require new runtime evidence.

Physics adapter follow-up 42731907952: body+138 contains a raw physics actor handle. The native linear-velocity adapter checks type through virtual +28 and calls virtual +130 with a return buffer. No byte-layout equivalence to the APK's target+15c writes was established, so no Android raw offset was copied into iOS.

Final i4 delivery succeeded: https://github.com/zengwantin-rgb/fanpromax-ios/releases/tag/integrated-51a35ef8dcac . Hosted run 42732886395 passed build, UIKit, original profile, native emulation, module signing, IPA CRC/resource/text preservation and publication digest checks. IPA size is 1,804,139,030 bytes; module size 155,632 bytes. Publication report retains device_verified=false. Temporary source-input token removed. The next live-motion decision requires i4 observations; neither new native-ratio checks nor flight height history existed in the submitted i3.1 log.
