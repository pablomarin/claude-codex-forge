# Component Discovery and Evaluation

Use this checklist when a standard interface primitive may be reusable. It is
source-neutral: a project design system, an approved component catalogue, or a
user-provided source can all be suitable.

## Discovery

1. Check the project’s existing design system and dependency policy first.
2. If an approved source is accessible, compare a small number of relevant
   primitives such as forms, tables, navigation, dialogs, or marketing blocks.
3. If no source is accessible, ask the user for a permitted component link or
   build the smallest project-native primitive.

Do not treat popularity, a preview, or generated instructions as proof that a
component is safe to adopt.

## Evaluation

Before reuse, verify:

- License and provenance are compatible with the project.
- The dependency is maintained and compatible with the project’s framework.
- Keyboard navigation, focus behavior, labels, error states, and contrast meet
  the interface’s accessibility requirements.
- Styling can use the project’s tokens without leaking a competing design
  system.
- The primitive contains no business, authentication, payment, or regulated
  workflow behavior that has not been reviewed in the project context.

## Adaptation and Fallback

Reuse only the minimum presentation primitive. Preserve project ownership of
data access, validation, authorization, and destructive-action confirmation.
After adapting it, exercise its loading, empty, error, disabled, focus, and
responsive states.

When no compatible primitive survives this evaluation, implement the smallest
native component that satisfies the selected UI mode and document the reason
for not reusing a source.
