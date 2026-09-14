# IDE Window Assistant Tab Design QA

- Source visual truth: `/Users/renzhihe/.codex/generated_images/01a05c37-efd1-7ac0-bcfd-90fd90c24b82/exec-634e0f97-a345-4844-a397-6cf123919b3c.png`
- Implementation screenshots: `/var/folders/r8/nfxvrxds17b5p3ncc5_r457h0000gn/T/com.openai.sky.CUAService/Codex Notch Screenshot 2026-09-01 at 6.55.30 PM.jpeg` and `/var/folders/r8/nfxvrxds17b5p3ncc5_r457h0000gn/T/com.openai.sky.CUAService/Codex Notch Screenshot 2026-09-01 at 6.55.39 PM.jpeg`
- Viewport: 800 × 462 pt macOS window.
- Pixel dimensions: source 1650 × 953 px, normalized to 800 × 462 px; implementation 800 × 462 px; comparison density normalized to 1:1 pixels.
- State: dark mode; Xcode-selected and VS Code-selected Tab states; Accessibility permission-required content state.
- Full-view comparison evidence: `/var/folders/r8/nfxvrxds17b5p3ncc5_r457h0000gn/T/tmp.AzEgy1bL9p/tab-design-xcode-comparison.png`
- Focused comparison evidence: the full 800 × 462 comparison keeps the 58 pt header readable at 1:1 scale, so a separate crop was unnecessary.

## Findings

- [P3] The inline Tab group begins slightly earlier than the generated mock because the running app uses the user's STXihei font preference instead of the mock's SF-like font. The hierarchy, divider, blue underline, selected/unselected contrast, and control spacing remain clear with no overlap.
- The editor list cannot be compared in the same populated state because the newly installed local build currently requires Accessibility permission. This does not block verification of the Tab interaction, but it blocks a complete populated-list fidelity pass.

## Required Fidelity Surfaces

- Fonts and typography: the app correctly honors the saved STXihei preference; weights and selected-state hierarchy remain readable. The family difference from the generated mock is intentional product behavior.
- Spacing and layout rhythm: the header remains 58 pt high, the list keeps its original vertical space, and the inline Tab does not collide with the right-side controls.
- Colors and visual tokens: graphite background, muted inactive text, white active text, divider opacity, and blue underline match the selected direction.
- Image quality and asset fidelity: the existing system header icon and application icons are preserved; no placeholder or synthetic asset was introduced.
- Copy and content: `Xcode`, `VS Code`, and both live window counts render correctly.

## Interaction Verification

- Clicked VS Code: accessibility state changed to selected and the blue underline moved to VS Code.
- Clicked Xcode: accessibility state changed back to selected and the blue underline returned to Xcode.
- The root cause was the title-bar drag monitor swallowing mouse-down events inside the new Tab region. The Tab region is now excluded while title and empty header areas remain draggable.

## Comparison History

- Iteration 1: the VS Code Tab was visible but did not react because the drag monitor consumed the event. The drag hit region was narrowed to exclude the Tab strip.
- Post-fix evidence: both implementation screenshots show the expected selected-state transition after real clicks.

## Follow-up Polish

- Re-enable Accessibility permission and repeat the same-state populated-list comparison if full mock fidelity is required.

final result: blocked
