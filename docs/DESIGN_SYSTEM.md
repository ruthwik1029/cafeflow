# CafeFlow design system

## Identity and typography

| Token | Value | Usage |
| --- | --- | --- |
| Deep Charcoal | #20242A | Dark canvas, strong text, ink on coral |
| Graphite | #292E36 | Dark surfaces, editorial hero |
| Vivid Coral | #FF4B2F | Primary controls and brand accents |
| Soft Mint | #EEFFEC | Highlighted detail on dark surfaces |
| Warm Ivory | #F5F4E9 | Light canvas, dark-mode foreground |

Inter serves body/interface copy. Space Grotesk serves headlines and brand text.
Both are offline bundled fonts with licenses under `assets/fonts`. Font files are
variable fonts. Theme text uses consistent weights and line heights.

Brand colors are not blindly used for every text role: coral buttons use charcoal
labels rather than low-contrast white. Secondary labels use semantic neutral colors.
Dark and light themes define semantic on-surface, container, outline and error roles.
The hero and decorative coffee artwork intentionally retain their editorial palette.

## Components

`CafeButton` (primary/secondary/disabled), `CafeCard`, `CafeInput`, `StatusPill`,
`MetricCard`, `CafeEmptyState`, `CafeErrorState`, `CafeLoadingState`, `showCafeDialog`,
`ThemeControl`, `PageBody`, `AdaptiveColumns` and `CafeBrand` are reusable core widgets.
Navigation uses Material ListTiles/popups and the role-aware responsive shell.
The design-system route offers interactive button/dialog/input previews and clearly
labeled loading/empty/error examples; it never writes business data.

Spacing tokens: 4, 8, 16, 24, 32 and 48 logical pixels. Cards use a 20-pixel radius;
controls use 12; larger hero containers use 24–28. Main content is capped at 1440
pixels. Internal navigation changes to a drawer below 1000 pixels. Public navigation
collapses below 850 pixels or with enlarged text. Content cards wrap using available
width rather than fixed column counts. Normal button targets are at least 48 pixels.

The app supports text scaling, keyboard focus, tooltips and standard Material dialog
semantics. Decorative artwork is excluded from semantics; its decorative lettering
does not scale, while actual interface text does. Brand artwork may scale down to
fit a narrow header. Semantic loading feedback remains visible without animation
when reduced motion is requested. Theme transitions last 180 ms and are disabled
when the operating system requests reduced motion.

## Theme persistence

The user can choose system/light/dark from the theme control on every application
surface. Startup restores `cafeflow.theme` from platform preferences before rendering.
Unknown preferences fall back to system. Changes update Riverpod immediately and
persist in serialized order. If storage fails, the current theme remains usable
and a snackbar explains that the preference was not saved. Preferences are local
to that app/device/origin; cloud theme synchronization is not claimed.
