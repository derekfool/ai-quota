# Asset provenance

On 2026-09-13 the owner confirmed that the bundled sounds and icon/reference imagery were generated with ChatGPT. This records the owner's source declaration, not independent legal clearance or a guarantee of exclusivity. Project-owned material is distributed under the root MIT license to the extent the owner holds rights. No provider endorsement is implied.

- `Sources/QuotaCore/Sounds/01-small-dialogue.wav`, `02-medium-dialogue.wav`, `03-recovery-lift.wav`: owner-approved generated Handpan ensemble cues.
- `Sources/QuotaCore/Sounds/focus-on.wav`: approved generated mechanical ticks, v9 with reduced amplitude.
- `Sources/QuotaCore/Sounds/focus-off.wav`: approved generated mechanical button cue.
- Classic chime sounds are synthesized by `QuotaChime.swift` at runtime.
- `Assets/AppIcon.png`: ChatGPT-generated gray tabby holding an AI conversation ticket; generated using the owner-supplied cat reference. The owner states the reference was also ChatGPT-generated. `AppIcon.icns` is its resized macOS bundle representation.
- SF Symbols are requested by name from macOS, not bundled copies. Package.swift has no external Swift package dependencies. Provider names identify compatibility and remain their respective owners' marks.

- `Assets/WatchCats/`: three owner-approved cat variants (sad, blank, lying), each with open and blink frames. Generated using OpenAI image generation on 2026-09-13, directly referencing the owner-supplied app icon; the lying pose also references the supplied resting-cat image. Prompts preserve the icon's large head, dark pupils, thick contours and cel-shaded fur. The lying variant rests its cheek on a surface; the other two have relaxed paws by the belly. Background removal and aligned eye-patch compositing were performed locally with the owner's permission. PNGs are resized for the native decorative overlay. No source photographs, personal filesystem paths, or account data are bundled.

- `Assets/WatchCats/angry-open.png` and `angry-blink.png`: owner-approved fourth resting pose, generated with OpenAI image generation from the supplied grumpy-cat expression, resting mascot, and app-icon references. Original alpha is preserved; only aligned eye regions from the blink generation are composited, then both frames are cropped and resized together.
