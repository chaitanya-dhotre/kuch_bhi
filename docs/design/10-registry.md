# Shared-Component Registry (L3: pages import, never reimplement)

Date: 2026-10-17. Companion to `00-foundation.md` §7. Every shared
interaction defined ONCE here with its widget path; page specs reference
these entries by name. Adding a row = spec amendment (L2).

Access pattern: widgets read colors via `context.t` (`ColorTokens`
ThemeExtension); geometry via `WarmPopTokens` statics. No hardcoded color.

## Core widgets (`lib/core/widgets/`)

| ID | Widget | Path | Slots | States / contract |
|---|---|---|---|---|
| R1 | `AppAvatar` | `app_avatar.dart` | `url?`, `initials`, `radius=20` | image when url, else single-char initials (surface2/inkSoft); circular; amendment: optional `accentSoft` fill flag (default false) |
| R2 | `AppBadge` | `app_badge.dart` | `count`, `color?` | pill ≥22×22, accent/onAccent; hidden at ≤0; amendment: counts ≥100 render `99+` |
| R3 | `AppButton` | `app_button.dart` | `onPressed`, `child`, `variant` (primary/secondary/text), `busy`, `expanded` | min-h 48 (text 40); disabled = inkFaint/surface2; busy = 18px spinner, press blocked |
| R4 | `AppChip` | `app_chip.dart` | `onTap`, `child`, `selected` | 36px pill; selected = accentSoft fill + accent border |
| R5 | `showToast()` | `app_toast.dart` | `context`, `msg`, `error` | one floating SnackBar, 3s; error variant border+icon |
| R6 | `ChatTile` | `chat_tile.dart` | `title`, `subtitle`/`subtitleWidget`, `avatarUrl`, `time`, `unreadCount`, `isGroup`, `onTap`, `onLongPress` | home row; 40px avatar, group glyph disc, AppBadge unread |
| R7 | `EmptyState` | `empty_state.dart` | `title`, `subtitle?`, `action?`, `withMascot`, `mood` (CapyMood), `mascot?` | mascot slot precedence: custom > Capybara(mood) > none; NEVER inside bubbles |
| R8 | `SearchField` | `search_field.dart` | `onChanged`, `hint?`, `controller?` | 44px pill; focused = accent 1.5px border |
| R9 | `SectionHeader` | `section_header.dart` | `String title` | 11px w600 inkFaint list label |
| R10 | `SettingsTile` | `settings_tile.dart` | `icon`, `title`, `subtitle?`, `onTap?`, `trailing?` | ≥56px row, surface2 icon well |
| R11 | `Skeleton` | `skeleton.dart` | `height`, `width?`, `radius=8`, `duration=1200ms` | shimmer surface2↔line; page-specific duration may be supplied (Home uses 1400ms); parks under reduced-motion |
| R12 | `StatusBanner` | `status_banner.dart` | `message`, `leading?`, `onRetry?` | accentSoft strip + accent@45% border; optional Retry |

## Chat-domain shared pieces (single definitions; reused across pages)

| ID | Piece | Path | Contract |
|---|---|---|---|
| C1 | `MessageBodyText` (#body) | `lib/features/chat/widgets/message_body_text.dart` | ALL ciphertext-bearing bodies; slots `'bubble.mine'|'bubble'|'emoji'|'system'|'preview'`; decrypt state machine = foundation §6 + laws L1–L13 of chat spec |
| C2 | `ReplyQuote` | `lib/features/chat/widgets/reply_quote.dart` | in-bubble (full) + composer (compact) modes; body via C1 `'preview'`; tap → jump to parent |
| C3 | `PinnedMessageBanner` | `lib/features/chat/widgets/pinned_message_banner.dart` | threads decryptState; media rows = type constants; tap → jump (+cycle when >1) |
| C4 | `showMessageMenu` (long-press sheet) | `lib/features/chat/widgets/message_context_menu.dart` | THE long-press menu — same sheet language for home long-press (page 2 spec references, never reimplements); amendment: exported conversation action-list variant shares the chrome |
| C5 | `SwipeToReply` | `lib/features/chat/widgets/swipe_to_reply.dart` | right-drag clamp 80px, threshold 72px, mediumImpact haptic, elastic 180ms |
| C6 | Tick indicator (canonical set) | defined in `chat.md` §10; impl lives in `message_bubble.dart` `_TickIndicator` + `_VoiceTick`/`_DocTick`/media variants → **converge to one legend** | pending spinner / failed(error) / sent(1) / delivered(2@54%) / read(2 full) / scheduled(clock) |
| C7 | Expiry affordance (unify) | today divergent: `ExpiryBadge` (img/vid), text label (voice/doc), `ExpiredMediaPlaceholder` | spec: ONE `ExpiryBadge` pill, top-right on all media; expired content = one `ExpiredMediaPlaceholder` pattern |
| C8 | Jump-to-message + landing highlight | `chat_screen.dart _jumpToMessage` + `_HighlightWrapper` | ANY jump source (search/pin/star/reply) lands with the same brief highlight flash (chat spec §8) |
| C9 | `ConversationPreviewText` | `message_body_text.dart` (export) | derived preview (P7) for home tiles — page 2 uses, never string-caches |
| C10 | `MediaViewerScreen` | `lib/features/media/` | canonical image/video fullscreen handoff (Hero `media_{serverId}`); `video_player_screen.dart` = divergent dead path — out of scope, backlog |

## Destination boundary (screens reached FROM chat — not re-specced here)

`MediaDocsScreen`, `StarredMessagesScreen(onJump:…)`, `GroupSettingsScreen`,
`MediaViewerScreen`, disappearing-messages dialog (specced in chat page — it
lives in chat code). Each gets its own page spec when its turn in
`00-foundation.md` §8 arrives; the chat spec only defines the handoff.
