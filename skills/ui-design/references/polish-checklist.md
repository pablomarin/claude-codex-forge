# UI Polish and Acceptance Checklist

Use this for every website, app and component task. Check affected surfaces and
applicable states; do not manufacture features to satisfy an unrelated checklist.
The main agent inspects first, then a fresh forge-ui-qa reviewer checks the browser.

## Visual direction and component craft

- [ ] The short design brief names users, tasks, scope, visual references and a
  specific aesthetic; the rendered surface follows that direction.
- [ ] New/substantially redesigned standard components were researched on 21st.dev;
  source URLs and reuse decisions, or an actual access/compatibility limitation,
  are recorded. Existing project components are reused coherently.
- [ ] The screen has a clear focal point and feels current and premium in its
  context. A functional default component library is insufficient.
- [ ] Canvas, layered surfaces, accents, borders and depth form a deliberate
  system. Transparency/blur has readable contrast over real backgrounds and
  a usable opaque fallback. No effect obscures task content.
- [ ] Components share typography, spacing, radius and interaction tokens;
  hover, selected and active treatments feel crafted rather than default.

## Typography, color and composition

- [ ] Headings, body, labels, numeric values and captions have useful hierarchy.
  Fonts fit the brand and remain readable; system fonts are valid for apps.
- [ ] Spacing has consistent rhythm and comfortable density, without excessive
  padding, arbitrary gaps, cramped controls or an endless identical-card grid.
- [ ] Semantic colors support status and primary actions; color is never the
  only indicator. Text is AA (4.5:1 normal, 3:1 large); UI boundaries meet 3:1.
- [ ] Supported light/dark themes preserve contrast, identity and surface depth.

## Copy and progressive disclosure

- [ ] Primary task, location and next action are understood within ten seconds.
- [ ] Remove repeated headings, redundant introductory paragraphs, duplicate
  status explanations, internal jargon and permanent tutorial text.
- [ ] Secondary context is available on demand; essential costs, permissions,
  risk, status and irreversible consequences remain visible.
- [ ] Labels and actions are concise and clear. Empty states give brief guidance
  and an action; errors explain recovery. Icon controls have accessible names.

## Interactions, motion and real states

- [ ] Relevant hover, focus, active, disabled, loading, empty, success and error
  states work. Long names, errors and realistic data do not break the composition.
- [ ] Motion gives useful feedback and considered delight across all modes.
  Apps feel fluid; critical decisions stay calm. No looping distraction, forced
  particles or delayed actions merely to demonstrate animation.
- [ ] Reduced motion keeps equivalent information and controls without animation.
  Prefer transform/opacity; measure layout animation if actually necessary.
- [ ] Loading and optimistic feedback preserve context; errors recover honestly.
- [ ] Effects pause off-screen where relevant; cleanup removes listeners and
  animation frames. Avoid large motion dependencies for simple effects.

## Browser, accessibility and responsive proof

- [ ] Inspect screenshots at 1440×900 and 390×844, plus required project widths
  (baseline 320, 375, 768, 1024, 1440). Check zoom and long-content overflow.
- [ ] No unintended page overflow. Wide data tables may scroll in a clearly
  bounded container while primary actions remain reachable.
- [ ] Semantic controls, visible focus, useful tab order, labelled fields,
  keyboard dialogs/menus and usable mobile targets (44px baseline; 48px critical).
- [ ] Use permitted real assets or realistic synthetic fixtures; no private data
  in screenshots. Meaningful images have alt text and explicit dimensions.
- [ ] The final-candidate audit identifies URL, persona, viewports, states,
  screenshots, task results and separate visual-quality/usability scores.
- [ ] Both axes score at least 4/5 and all concrete acceptance failures are fixed.
  A missing browser, state or screenshot is not visual approval.

## Mode-specific judgment

- **Marketing:** memorable first impression, useful imagery/motion and a clear
  conversion path. No mandatory effect recipe or motion quota.
- **Product UI:** an attractive, comfortable workspace with strong task hierarchy,
  polished controls, concise copy and efficient keyboard/touch interaction.
- **Trust-First:** refined visual quality and calm motion, visible consequences,
  accurate status and accessible decision paths. Professional does not mean dated.

Taste outside the documented direction is advisory. Failed acceptance requires
a concrete observation and smallest fix. Use one repair and a bounded closure
pass; do not chase subjective perfection through endless broad reviews.
After a repair changes the frozen candidate, the final audit must still observe
the complete required matrix on that new candidate. A findings-only closure
report cannot stand in for current final coverage.

## Public-facing metadata

Every deployed site needs appropriate favicon, scalable icon, apple icon and
branded share image (1200×630), plus production metadataBase, OpenGraph and Twitter
card metadata in its framework's equivalent root. Check that public metadata
does not disclose authenticated private content. Verify real assets and rendered
share metadata rather than checking filenames alone.
