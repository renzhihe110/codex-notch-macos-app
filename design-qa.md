# Floating Dashboard Design QA

## Comparison Target

- Source visual truth: `/var/folders/r8/nfxvrxds17b5p3ncc5_r457h0000gn/T/codex-clipboard-47120370-1ddb-4eca-b8b0-338227514d5f.png`
- Previous glow screenshot: `/var/folders/r8/nfxvrxds17b5p3ncc5_r457h0000gn/T/codex-clipboard-7df3145f-ae6e-4ef9-b966-477a529e31c3.png`
- First single-column screenshot: `/var/folders/r8/nfxvrxds17b5p3ncc5_r457h0000gn/T/codex-clipboard-d0b25afd-b8ca-445e-805a-4d034643f74e.png`
- Current enlarged-font screenshot: `/var/folders/r8/nfxvrxds17b5p3ncc5_r457h0000gn/T/codex-clipboard-43f08df0-5a7f-4de1-9aee-8929655e9adc.png`
- Current clipped-shell screenshot: `/var/folders/r8/nfxvrxds17b5p3ncc5_r457h0000gn/T/codex-clipboard-b8e413cb-9698-48b8-9937-9e8d4b169b13.png`
- Clean rounded-shell reference: `/var/folders/r8/nfxvrxds17b5p3ncc5_r457h0000gn/T/codex-clipboard-b754c5fb-46dd-4606-bae4-a842350fd896.png`
- Correct recent-activity list reference: `/var/folders/r8/nfxvrxds17b5p3ncc5_r457h0000gn/T/codex-clipboard-ed795251-f97b-4b77-bae4-dec547aafa45.png`
- Incorrect creation-ordered Dashboard: `/var/folders/r8/nfxvrxds17b5p3ncc5_r457h0000gn/T/codex-clipboard-aac9e9f9-9247-426a-9260-dc8017ba8dbe.png`
- Normalized comparison: `/Users/renzhihe/.codex/visualizations/2026/08/06/019fd528-d55d-7a03-a028-b5d09d9f714a/floating-dashboard-audit/04-glow-comparison.png`
- Source pixels: 818×510; implementation pixels: 940×592.
- Normalization: source content crop 645×397 padded to 645×400; implementation content crop 837×519 scaled to 645×400; combined comparison 1290×400.
- CSS size and density: not applicable to this native macOS App; both artifacts are screenshots of the same default floating-dashboard state.
- State: 最新运行截图暴露悬浮列表按创建时间截断并显示创建时刻，用户确认图一的最近活动任务及“最新消息、项目名、活动时间”内容才是正确基准；实现已恢复活动时间排序和正确字段，等待重新运行确认。

## Full-view Comparison Evidence

The normalized comparison places the reference on the left and the previous implementation on the right. 该图只作为旧双栏光晕调整的历史证据；当前单列截图用于确认字号和任务顺序问题，不能作为修订后布局的通过证据。

No separate focused crop is retained for the revised layout because there is no post-change runtime capture yet. 下一轮对比必须分别覆盖绿色休息猫、黄色走路动画、红色站立猫，以及居中的五行 Dashboard 和底部 Token 摘要。

## Findings

- [P1] 悬浮卡片外壳在窗口边界被裁切
  - Location: floating Dashboard outer shell.
  - Evidence: 当前卡片与 `NSWindow` 同为 460×396，但外壳绘制 11/14pt 外阴影和蓝紫渐变描边；运行截图左、右和底边出现不对称亮线，参考图二则为完整黑色圆角面与中性细边线。
  - Impact: 四个圆角和四条边不连续，窗口看起来像被截断。
  - Fix: 移除外扩阴影、渐变描边和第二层描边，改用黑色圆角填充、内收 `strokeBorder` 和同形 `clipShape`；等待新截图确认。
- [P1] 悬浮任务在读取截断前按创建时间排序
  - Location: visible-session SQLite query and floating task subtitle.
  - Evidence: 错误截图的五条任务逐项匹配创建时间排名 1～5；当前最活跃任务按创建时间只排第 9，会被读取层 `LIMIT 8` 提前排除，且副标题只显示创建时刻和状态。
  - Impact: 最近仍在活动的旧任务缺失，用户看到的任务顺序和内容都与正确列表不一致。
  - Fix: 在读取层按最后活动时间倒序后再截断，副标题单行组合最新消息、项目名和活动相对时间；静态检查已通过，等待新截图确认。

## Required Fidelity Surfaces

- Fonts and typography: 任务标题固定为 19.5pt medium，副标题和状态固定为 15pt regular；需要运行截图确认实际渲染密度。
- Spacing and layout rhythm: 主区固定五条 54pt 任务行和 6pt 行间距，底部摘要固定 24pt；旧双栏和任务分组已移除。
- Colors and visual tokens: Dashboard 外壳参考图二改为半透明黑色圆角填充与内收中性细边线，不使用会超出窗口的阴影或蓝紫渐变描边；猫咪入口不绘制圆形底、光环、状态点或连接段。
- Image quality and asset fidelity: 猫咪使用 DockCat 固定 commit 的六张原始 PNG，运行时只做等比缩放和贴底对齐；静态哈希已固定，仍需运行截图确认三档尺寸没有裁切或拉伸。
- Copy and content: 任务继续来自真实会话；底部只显示真实输入、其中缓存、输出和总量，输入值包含缓存。

## Comparison History

1. Pre-fix comparison found one P1 and two P2 glow mismatches in `04-glow-comparison.png`.
2. Code fixes were applied to `NotchView.swift` and `StatusBarItemController.swift`: shell-only shadows, lower outer stroke intensity, tighter connector bloom, localized orb-ring bloom, and a tighter Token-ring glow.
3. Post-fix runtime evidence is unavailable because the project constraint forbids the agent from automatically compiling and launching the App. A new same-state screenshot is required before the findings can be closed.
4. 用户批准 Plan v2 后，悬浮内容改为直接展示最近五条 54pt 任务行（标题 13pt，副标题/状态 10pt），Token 改为底部单行真实摘要；旧双栏截图不再作为当前布局通过证据。
5. 首次单列截图确认布局已切换，但任务文字偏小且最后活动时间排序不符合“最近新建”语义；Plan v3 将文字放大 50%，并将列表选择和时间文案改为创建时间。
6. 放大后的截图确认最近新建五任务及 19.5/15pt 尺寸已经生效，但标题 semibold 和状态 medium 偏粗；实现已分别降为 medium 和 regular。
7. 用户随后要求使用 DockCat 猫咪作为悬浮入口：绿色休息、黄色 3fps 四帧走路、红色站立提醒，并移除圆形光环、状态点和侧向连接；点击改为当前屏幕居中 toggle。
8. 最新运行截图确认单列内容已正常显示，但外壳外阴影在 `NSWindow` 边界被裁切；本轮参考大窗口改为不向边界外绘制的黑色圆角面和内收细边线。
9. 用户确认图一的最近活动列表才是正确基准；只读数据库证明错误 Dashboard 精确展示创建时间排名 1～5，并会在 `LIMIT 8` 前排除创建排名第 9 的当前活跃任务，因此恢复最后活动时间排序和正确副标题字段。

## Implementation Checklist

- [x] Restrict Dashboard shadows to the rounded shell.
- [x] Reduce connector glow opacity and radius.
- [x] Replace broad orb bloom with smaller base and ring-local shadows.
- [x] Reduce outer shell stroke intensity and inner-panel border opacity.
- [x] Tighten Token-ring stroke and shadow.
- [x] Remove the Token column, task group header, count badge, and 5/8 expansion state.
- [x] Render five direct 54pt task rows with 13pt title and 10pt subtitle/status text.
- [x] Render real input, cached input, output, and total Token values in the bottom summary.
- [x] Sort visible tasks by normalized creation time while preserving activity time for status mapping.
- [x] Supersede creation ordering with last-activity ordering before the read limit.
- [x] Replace the creation-time subtitle with latest message, project name, and relative activity time.
- [x] Increase task title to 19.5pt, subtitle/status to 15pt, and status capsule to 28pt.
- [x] Reduce task title to medium and status text to regular weight.
- [x] Replace the circular orb with fixed-revision DockCat resting, walking, and standing assets.
- [x] Remove the floating orb background, glow, status dot, side connector, and hover-open path.
- [x] Center the normal-size Dashboard on cat click and keep cat dragging independent from the open window.
- [x] Replace the clipped shell shadows and gradient strokes with a black rounded fill, inset border, and matching clip shape.
- [ ] Rebuild locally and confirm all four shell edges and corners are continuous.
- [ ] Verify all three cat states, 3fps animation, transparent background, and click toggle in a local run.
- [ ] Verify the packaged app contains the six PNG files and full DockCat license.
- [ ] Rebuild locally and capture the same floating-dashboard state.
- [ ] Compare the revised screenshot against the source at normalized size.

## Open Questions

- None. The only blocker is revised runtime evidence.

## Follow-up Polish

- Any remaining P3 color tuning should be based on the next normalized screenshot rather than code-only estimates.

final result: blocked
