# Settings Window Design QA

## Comparison Target

- Source visual truth: `/Users/renzhihe/meitu_code/codex-notch-macos-app/docs/design-qa/settings-reference-original.png`
- Normalized source: `/Users/renzhihe/meitu_code/codex-notch-macos-app/docs/design-qa/settings-reference-normalized.png`
- Implementation screenshot: `/Users/renzhihe/meitu_code/codex-notch-macos-app/docs/design-qa/settings-implementation.png`
- Side-by-side comparison: `/Users/renzhihe/meitu_code/codex-notch-macos-app/docs/design-qa/settings-comparison.png`
- Viewport: native macOS settings window at 470×838 pt.
- Source pixels: 939×1674; normalized to 470×838 for equal-size comparison.
- Implementation pixels: 470×838; the Computer Use capture is already normalized to the native viewport.
- Combined comparison: 956×838, source on the left and implementation on the right with a 16 px neutral gutter.
- State: dark settings window with all six sections visible, current local font `华文细黑`, current pet `Trump · 鸭圈泳装`, large capsule size, and 5-second completion delay.

## Current Iteration Status

- The title bar source now uses custom red, yellow, and green controls and routes every Settings command to the same AppKit window.
- The debug App Bundle was rebuilt and restarted from the workspace `dist` path, then captured at the target 470×838 viewport.
- The refreshed comparison shows the custom title, traffic-light positions, colors, spacing, and dark title-bar surface aligned with the source.
- The project-directory color trigger now uses a dark rounded `选择颜色` button with a current-color dot instead of a switch-shaped capsule.
- The saved implementation screenshot predates this trigger-style change. Per the repository instruction, this iteration was not rebuilt or relaunched automatically, so visual and interaction QA for the new button remains pending.

## Full-view Comparison Evidence

The equal-size comparison shows the custom traffic lights and title, 470×838 frame, main title, card bounds, six section boundaries, right-control alignment, and bottom action bar occupying the same major regions. The final implementation has no native-titlebar overlap, scrollbar, clipped card edge, wrapped label, or hidden persistent action.

A separate focused crop was not needed because every label, icon, control edge, and divider remains readable at the original 470×838 comparison size.

## Findings

- No actionable P0, P1, or P2 differences remain.
- [P3] The font section uses the closest SF Symbol `a.circle` while the mock uses a bare serif A.
  - Location: font section icon.
  - Evidence: both identify typography with the same accent color and footprint, but the implementation adds a circle outline.
  - Impact: minor icon-shape drift only; hierarchy and affordance are unchanged.
  - Follow-up: replace only if a licensed vector icon matching the bare A becomes available.
- [P3] Current font and pet names differ from the mock's sample values.
  - Location: font and pet menu controls.
  - Evidence: implementation renders the user's persisted `华文细黑` and `Trump · 鸭圈泳装`; the source shows `苹方（等宽）` and `Trump · 橙色猫咪`.
  - Impact: expected data-driven content, not visual drift.
  - Follow-up: none.

## Required Fidelity Surfaces

- Fonts and typography: title, section headers, labels, helper text, and buttons preserve the source hierarchy without wrapping or truncation. Exact glyph weight varies with the user's selected app font, which is intentional product behavior.
- Spacing and layout rhythm: outer margins, card bounds, section dividers, control rows, and action-bar positions align within roughly 1–3 px at the normalized viewport; every section remains visible without scrolling.
- Colors and visual tokens: black-blue background, slightly lifted card surface, low-contrast borders, white text hierarchy, and teal accent closely match the reference. Selected segments and the primary save button use the same semantic accent.
- Image quality and asset fidelity: the target contains no raster artwork. The implementation uses native SF Symbols for all icons, avoiding bitmap scaling or placeholder assets.
- Copy and content: the six source sections and all primary labels are present. Version, scan totals, font, pet, shortcut, and delay values come from real application state.

## Interaction Verification

- Opened the font menu and confirmed all installed font choices are exposed.
- Activated the already-selected large capsule option and confirmed no layout or state regression.
- Clicked Cancel and confirmed the settings window closed cleanly.
- Reopened the settings window and confirmed the same 470×838 layout and persisted values returned.
- Invoked `⌘,` repeatedly and confirmed the command raises the same custom settings window instead of creating a second Settings scene.
- Used real pointer clicks to confirm the red control closes, the yellow control minimizes, and the green control zooms and restores the window.
- The final debug build completed successfully, the App remained running, and no SwiftUI crash or unexpected network handle was observed.
- Browser console checks are not applicable to this native macOS SwiftUI view.

## Comparison History

1. The first automation target was an older `/Applications` copy and was excluded from QA after process-path verification.
2. The first correct build rendered at a restored 900×672 light-titlebar size, clipping the lower sections; the view now configures both Settings-scene and custom windows to 470×838 dark mode.
3. The next capture aligned the full frame but exposed black menu text and reordered chevrons; dark color scheme and external menu overlays corrected both issues.
4. A spacing pass made the font and pet sections 30 pt too tall and introduced a scrollbar; those two sections were tightened while the already-aligned sections were preserved.
5. The earlier equal-size comparison confirmed the content area had no P0/P1/P2 findings, with only title-bar and data-driven P3 differences remaining.
6. The custom-titlebar build replaced the disabled native zoom state; the refreshed equal-size comparison and close/minimize/zoom interaction pass closed the title-bar finding.

## Implementation Checklist

- [x] Match the 470×838 dark macOS window and integrated title bar.
- [x] Recreate the single bordered card with six divided sections.
- [x] Use teal SF Symbols and dark native controls.
- [x] Align menu, shortcut, segmented, update, and stepper controls to the right grid.
- [x] Keep all existing settings behaviors and live previews.
- [x] Provide functional global Restore Defaults, Cancel rollback, and Save actions.
- [x] Keep all content and persistent actions visible without scrolling at the target viewport.
- [x] Compile, restart, capture, compare, and verify the new custom title-bar interactions.
- [ ] Compile, restart, capture, and verify the color-selection button appearance and interaction.

## Follow-up Polish

- Optionally replace the circular A with a licensed bare-A icon if exact icon-shape matching becomes important.

final result: blocked
