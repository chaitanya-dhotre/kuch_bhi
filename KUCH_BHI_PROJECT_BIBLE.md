# 📱 Kuch Bhi — Project Bible

**Version:** 1.0  
**App ID:** `com.chai.kuch-bhi`  
**Backend:** [https://kuch-bhi.duckdns.org](https://kuch-bhi.duckdns.org)  
**Last Updated:** 2026-05-06

---

**FOR CODING AGENTS:** This document is the single source of truth for this project.  
You must read this file fully before writing any code. Do not deviate from the architecture,  
schema, naming conventions, or implementation phases defined here. If you are uncertain  
about anything, STOP and ask the developer. Never guess. Never take shortcuts.

---

## Table of Contents

1. [Project Overview](#1-project-overview)  
2. [Tech Stack](#2-tech-stack)  
3. [Architecture Overview](#3-architecture-overview)  
4. [Flutter Project Structure](#4-flutter-project-structure)  
5. [Design System](#5-design-system)  
6. [Feature Specification](#6-feature-specification)  
7. [PocketBase Schema](#7-pocketbase-schema)  
8. [Encryption Specification](#8-encryption-specification)  
9. [FCM & Notification Architecture](#9-fcm--notification-architecture)  
10. [Google OAuth Flow](#10-google-oauth-flow)  
11. [Media Handling](#11-media-handling)  
12. [Adaptive Layout Specification](#12-adaptive-layout-specification)  
13. [Phased Development Plan](#13-phased-development-plan)  
14. [Coding Agent Rules & Protocols](#14-coding-agent-rules--protocols)  
15. [Setup Checklist](#15-setup-checklist)  
16. [Known Pitfalls & Solutions](#16-known-pitfalls--solutions)

---

## 1\. Project Overview

**App Name:** Kuch Bhi  
**Purpose:** A private, encrypted messaging app for a closed group of friends.  
**Tagline:** *Say anything.*

### Goals

- WhatsApp-level polish and reliability on Android  
- Adaptive UI for phones, tablets, and foldable devices (Samsung Z Fold 5\)  
- End-to-end encrypted messages with fast, stable performance  
- Rock-solid read receipts (single tick / double tick / colored double tick)  
- Works completely offline; syncs when connection restores  
- Runs well on mid-range and low-end Android devices

### Non-Goals (Out of Scope for v1)

- iOS support  
- Web client  
- Voice/video calls  
- Sticker store or paid features  
- More than \~100 users total

### Planned Scale

- **Current:** \~10 users \+ 2-3 test accounts  
- **Target ceiling:** \~80–100 users (future international friends)  
- **Max group size:** 15 members

---

## 2\. Tech Stack

### Frontend

| Component | Choice | Reason |
| :---- | :---- | :---- |
| Framework | Flutter (stable channel) | Cross-platform, good perf when done right |
| Min SDK | Android 21 (5.0) | Covers 99%+ of active Android devices |
| Target SDK | Android 35 | Latest stable |
| State Management | **Riverpod** (flutter\_riverpod) | Type-safe, testable, no boilerplate hell |
| Local Database | **Drift** (drift \+ drift\_sqflite) | Type-safe SQLite, excellent migrations |
| Navigation | **go\_router** | Declarative, deep-link compatible |
| DI | Riverpod providers | No separate DI library needed |
| HTTP | **dio** | Interceptors, retry logic, timeout handling |
| WebSocket/SSE | PocketBase Flutter SDK | Built-in real-time subscriptions |

### Backend

| Component | Choice |
| :---- | :---- |
| Server | Oracle Ubuntu Ampere VM (Always Free) |
| Backend | PocketBase v0.37.5 |
| Domain | kuch-bhi.duckdns.org |
| Push Notifications | Firebase Cloud Messaging (FCM) |
| Auth | PocketBase Auth \+ Google OAuth via `google_sign_in` package |

### Key Flutter Packages

dependencies:

  \# Core

  flutter\_riverpod: ^2.5.1

  riverpod\_annotation: ^2.3.5

  go\_router: ^14.0.0

  

  \# Database

  drift: ^2.20.0

  drift\_sqflite: ^2.1.1

  

  \# Networking

  dio: ^5.4.3

  pocketbase: ^0.20.0          \# Official PocketBase Flutter SDK

  

  \# Auth

  google\_sign\_in: ^6.2.1

  

  \# Encryption

  cryptography: ^2.7.0          \# AES-256-GCM \+ X25519 ECDH

  

  \# Push Notifications

  firebase\_core: ^3.0.0

  firebase\_messaging: ^15.0.0

  flutter\_local\_notifications: ^17.0.0

  flutter\_background\_service: ^5.0.0

  

  \# Media

  image\_picker: ^1.1.2

  video\_player: ^2.9.0

  just\_audio: ^0.9.40           \# Voice messages

  record: ^5.1.2                \# Voice recording

  flutter\_image\_compress: ^2.2.0

  video\_compress: ^3.1.2

  cached\_network\_image: ^3.3.1

  photo\_view: ^0.15.0           \# In-app media viewer

  

  \# UI

  flutter\_animate: ^4.5.0

  shimmer: ^3.0.0

  qr\_flutter: ^4.1.0

  mobile\_scanner: ^5.1.1        \# QR scanner \+ gallery QR upload

  

  \# Utils

  path\_provider: ^2.1.3

  share\_plus: ^9.0.0

  url\_launcher: ^6.3.0

  connectivity\_plus: ^6.0.0

  package\_info\_plus: ^8.0.0     \# For version check / update banner

  intl: ^0.19.0

  uuid: ^4.4.0

dev\_dependencies:

  build\_runner: ^2.4.11

  drift\_dev: ^2.20.0

  riverpod\_generator: ^2.4.3

  flutter\_lints: ^4.0.0

---

## 3\. Architecture Overview

### Pattern: Feature-First Clean Architecture

Presentation Layer  →  Riverpod Providers (StateNotifier / AsyncNotifier)

                              ↓

Repository Layer    →  Repository classes (abstract interface \+ impl)

                              ↓

Data Layer          →  Local (Drift DB) \+ Remote (PocketBase SDK \+ Dio)

                              ↓

Domain Layer        →  Pure Dart models, no Flutter dependencies

### Key Architecture Rules

1. **No business logic in widgets.** Widgets call providers. Providers call repositories.  
2. **All crypto operations run in a background isolate.** Never on the main thread.  
3. **All DB reads/writes go through Drift.** Never raw SQL strings.  
4. **All PocketBase calls go through a repository.** Never call PocketBase SDK directly from UI.  
5. **Offline-first.** Every feature reads from local DB first. Remote sync happens in background.  
6. **Message queue.** If offline, messages go into a local `pending_messages` table and sync when connection restores.

### Data Flow for Sending a Message

User types → taps send

  → MessageRepository.sendMessage()

    → Encrypt message body (background isolate)

    → Save to local Drift DB with status: PENDING

    → UI updates immediately (optimistic update)

    → Upload to PocketBase

      → On success: update local status to SENT, show single tick

      → On failure: keep PENDING, retry with exponential backoff

  → PocketBase triggers FCM to recipient

    → Recipient FCM handler fires (even if app is killed)

      → Marks DELIVERED in PocketBase

        → Sender's real-time subscription updates

          → UI shows double tick

---

## 4\. Flutter Project Structure

lib/

├── main.dart

├── app.dart                        \# MaterialApp \+ GoRouter setup

├── firebase\_options.dart           \# Generated by FlutterFire CLI

│

├── core/

│   ├── constants/

│   │   ├── app\_constants.dart      \# API URLs, timeouts, limits

│   │   ├── app\_colors.dart         \# Design tokens

│   │   └── app\_text\_styles.dart

│   ├── errors/

│   │   ├── app\_exception.dart

│   │   └── failure.dart

│   ├── extensions/                 \# Dart extensions

│   ├── utils/

│   │   ├── date\_formatter.dart

│   │   ├── file\_utils.dart

│   │   └── validators.dart

│   └── network/

│       ├── dio\_client.dart

│       ├── pocketbase\_client.dart  \# Singleton PB client

│       └── connectivity\_service.dart

│

├── data/

│   ├── local/

│   │   ├── database/

│   │   │   ├── app\_database.dart   \# Drift DB definition

│   │   │   ├── tables/             \# One file per Drift table

│   │   │   └── daos/               \# Data Access Objects

│   │   └── secure\_storage/

│   │       └── secure\_storage\_service.dart  \# flutter\_secure\_storage

│   ├── remote/

│   │   └── pocketbase/

│   │       ├── pb\_auth\_datasource.dart

│   │       ├── pb\_message\_datasource.dart

│   │       ├── pb\_user\_datasource.dart

│   │       ├── pb\_media\_datasource.dart

│   │       └── pb\_realtime\_datasource.dart

│   └── models/                     \# JSON-serializable data models

│       ├── user\_model.dart

│       ├── message\_model.dart

│       ├── conversation\_model.dart

│       └── ...

│

├── domain/

│   ├── entities/                   \# Pure Dart domain objects

│   │   ├── user.dart

│   │   ├── message.dart

│   │   └── ...

│   └── repositories/               \# Abstract interfaces

│       ├── auth\_repository.dart

│       ├── message\_repository.dart

│       └── ...

│

├── infrastructure/

│   └── repositories/               \# Concrete implementations

│       ├── auth\_repository\_impl.dart

│       ├── message\_repository\_impl.dart

│       └── ...

│

├── features/

│   ├── auth/

│   │   ├── screens/

│   │   ├── widgets/

│   │   └── providers/

│   ├── home/                       \# Contact list screen

│   ├── chat/                       \# Chat screen

│   ├── group\_chat/

│   ├── profile/

│   ├── settings/

│   ├── media\_viewer/

│   ├── starred\_messages/

│   ├── search/

│   └── friend\_requests/

│

├── services/

│   ├── fcm\_service.dart

│   ├── background\_service.dart     \# flutter\_background\_service

│   ├── encryption\_service.dart     \# Calls isolates internally

│   ├── notification\_service.dart

│   └── update\_checker\_service.dart \# GitHub Releases version check

│

└── providers/

    └── global\_providers.dart       \# App-wide Riverpod providers

---

## 5\. Design System

### Inspiration

GNOME HIG (Human Interface Guidelines), macOS, iOS — clean, airy, purposeful.  
No skeuomorphism. No excessive gradients. Whitespace is intentional.

### Themes

Three themes required: **Light**, **Dark**, **AMOLED** (pure black backgrounds).  
All themes defined as `ThemeData` objects in `core/constants/app_colors.dart`.  
Theme persisted via Riverpod \+ Drift. No `shared_preferences` for theme — use Drift.

### Typography

**Font:** `Inter` (via google\_fonts package)

- No calligraphy, no decorative fonts  
- Fallback: system default sans-serif

| Style | Size | Weight |
| :---- | :---- | :---- |
| Display | 24sp | SemiBold (600) |
| Title | 18sp | SemiBold (600) |
| Body | 15sp | Regular (400) |
| Caption | 12sp | Regular (400) |
| Micro | 11sp | Regular (400) |

### Color Tokens (Light Theme Base)

// Primary

primaryColor: Color(0xFF5E6AD2)       // Soft indigo — modern, calm

primaryVariant: Color(0xFF4A55C0)

// Surfaces

background: Color(0xFFF5F5F7)          // macOS-like off-white

surface: Color(0xFFFFFFFF)

surfaceVariant: Color(0xFFEEEEF3)

// Chat bubbles

sentBubble: Color(0xFF5E6AD2)          // Primary indigo

receivedBubble: Color(0xFFFFFFFF)      // White with subtle shadow

// Text

onPrimary: Color(0xFFFFFFFF)

onBackground: Color(0xFF1A1A2E)

onSurface: Color(0xFF1A1A2E)

secondaryText: Color(0xFF6B7280)

// Indicators

tickSent: Color(0xFF9CA3AF)            // Grey

tickDelivered: Color(0xFF9CA3AF)       // Grey double tick

tickRead: Color(0xFF5E6AD2)            // Primary color double tick

// AMOLED

amoledBackground: Color(0xFF000000)

amoledSurface: Color(0xFF0D0D0D)

### Motion & Animation

- Use `flutter_animate` for entry/exit animations  
- Message bubble entry: slide up \+ fade, 150ms, ease-out  
- Screen transitions: shared element where possible, otherwise fade+slide  
- **No janky animations.** If an animation causes frame drops, remove it.  
- All list scrolling must maintain 60fps. Use `ListView.builder` always.

### Spacing System (8pt grid)

`4, 8, 12, 16, 20, 24, 32, 48, 64` — all paddings/margins must use these values.

---

## 6\. Feature Specification

### 6.1 Authentication

- **Email \+ Password** sign in / register via PocketBase native auth  
- **Google Sign-In** via `google_sign_in` package → exchange token with PocketBase `/api/collections/users/auth-with-oauth2`  
- On first login: prompt user to set display name and profile picture  
- A unique **6-character alphanumeric friend code** is auto-generated on account creation (stored on user record, uppercase, e.g. `CHAI42`)  
- **App Lock:** Biometric / PIN lock using `local_auth` package. Optional, user-toggled in settings.

### 6.2 Finding Friends & Requests

- User can search by typing a friend code  
- User can **scan a QR code** (camera) or **upload QR from gallery**  
- Each user's QR code encodes their friend code \+ deep link: `kuchbhi://add/CHAI42`  
- Sending a request creates a `friend_requests` record  
- Recipient sees a notification \+ in-app badge  
- Recipient can **Accept** or **Decline**  
- Accepted → creates `friendships` record for both users  
- User can set a **custom nickname** for any friend (stored locally in Drift, not server)

### 6.3 Conversations

- **1-on-1 chats** and **Group chats** (max 15 members)  
- Conversations list (Home screen) shows:  
  - Profile picture  
  - Display name (or custom nickname if set)  
  - Last message preview (truncated, shows "📷 Photo", "🎤 Voice", etc. for media)  
  - Timestamp of last message  
  - Unread message count badge  
  - Online / Last seen indicator  
  - Pinned conversations float to top

### 6.4 Messaging

- **Text messages** with Unicode \+ emoji support  
- **Swipe to reply** — swipe right on any message to quote-reply  
- **Long press menu:** Reply, Copy, Star, Pin, Forward, Delete for me, Delete for everyone, React  
- **Message reactions** — emoji picker, show reaction counts below message  
- **Read receipts:** Single tick (sent), Double tick grey (delivered), Double tick colored (read)  
- **Typing indicator** — animated dots, debounced 2s  
- **Online status:** "In chat", "Online", "Last seen \[time\]"  
- **Link previews** — auto-fetch OG metadata for URLs, show card below message  
- **Message drafts** — auto-saved per conversation when app is backgrounded  
- **Disappearing messages** — configurable per chat: Off / 24h / 7 days / 30 days  
- **Pinned messages** — pin up to 3 messages per chat, shown in a collapsible banner at top  
- **Starred messages** — global starred messages page \+ per-chat filter  
- **Search messages** — full-text search within a conversation  
- **Polls** — create polls in chats, multiple choice, shows live vote counts  
- **Message status correction:** If delivered tick never updates because chat wasn't open, FCM background handler forces the update. See Section 9\.

### 6.5 Media

- **Photos:** Camera or gallery picker. Compress before upload. Toggle: Normal / High Quality.  
- **Videos:** Camera or gallery. Compress before upload. Toggle: Normal / High Quality.  
- **Voice messages:** In-app recorder with waveform display. Max 5 minutes. Playback speed: 1x / 1.5x / 2x.  
- **In-app media viewer:** Full screen. Pinch to zoom for photos. Standard video controls. "Open in external app" button.  
- **Media expiry banner:** Show "Expires in X days" on media older than 70% of retention period.  
- **Media & Docs page:** Per-chat tab view filtering by Photos / Videos / Voice / Docs.

### 6.6 Groups

- Create group: name, optional icon, add friends  
- Admin features: Add/remove members, promote to admin, change group name/icon  
- Multiple admins allowed  
- Leave group option  
- "Only admins can message" toggle (admin-controlled)  
- Group info page with member list

### 6.7 Profile & Settings

- Profile picture (upload from gallery, crop in-app)  
- Display name  
- About/bio (short text)  
- Friend code display \+ QR code display (shareable)  
- Custom nicknames for friends (local only)  
- **App Themes:** Light / Dark / AMOLED  
- **Chat Wallpaper:** Per-chat custom wallpaper or global default  
- **Notification settings:** Per-chat mute (1h / 8h / 1 week / always)  
- **Storage management:** Show cached media size, clear cache button  
- **Blocked users list**  
- **Export chat** as .txt file  
- **Delete account:** Hard delete — removes all messages, media, auth record, FCM tokens. Shows confirmation dialog with typed confirmation ("DELETE").

### 6.8 Unique Features & Easter Eggs

- **"Chai Break" status** — quick-set status with chai cup animation  
- **Scheduled messages** — compose \+ pick datetime, sends automatically  
- **Chat milestones** — confetti animation at 1,000 / 5,000 / 10,000 messages  
- **Konami-style easter egg** — typing "kuch bhi" in the search bar triggers a brief animation  
- **Long press app version** in About page — plays a short haptic pattern  
- **Group named "Avengers"** — auto-applies a special dark theme to that group  
- **Voice message speed control** — 1x / 1.5x / 2x (as mentioned in features)  
- **In-app update banner** — GitHub Releases API version check on app launch

### 6.9 Offline & Sync

- All messages stored in local Drift DB  
- Pending messages queued locally, sent with exponential backoff when online  
- `connectivity_plus` monitors network state  
- On reconnect: fetch missed messages, update statuses  
- Show "Waiting for connection..." subtle banner when offline (not an error dialog)

---

## 7\. PocketBase Schema

**Admin note:** All collections are created in PocketBase Admin UI at [https://kuch-bhi.duckdns.org/\_/](https://kuch-bhi.duckdns.org/_/) Rules use PocketBase filter syntax. `null` \= admin only. `""` \= public (anyone).

---

### 7.1 Collection: `users` (Auth Collection — extends built-in)

| Field | Type | Options |
| :---- | :---- | :---- |
| `id` | Auto (PB) | PK |
| `email` | Email | Required, unique |
| `username` | Text | Required, unique, min 3 |
| `display_name` | Text | Required, max 50 |
| `avatar` | File | Optional, max 5MB, images only |
| `about` | Text | Optional, max 150 |
| `friend_code` | Text | Required, unique, exactly 6 chars, uppercase |
| `fcm_token` | Text | Optional (updated on each app launch) |
| `last_seen` | DateTime | Optional |
| `is_online` | Bool | Default: false |
| `typing_in` | Text | Optional |
| `current_chat` | Text | Optional |
| `private_key_encrypted` | Text | Nullable|
| `private_key_salt` | Text | Nullable|
| `created` | Auto (PB) |  |
| `updated` | Auto (PB) |  |

**Rules:**

listRule:   @request.auth.id \!= ""

viewRule:   @request.auth.id \!= ""

createRule: ""

updateRule: @request.auth.id \= id

deleteRule: @request.auth.id \= id

---

### 7.2 Collection: `friend_requests`

| Field | Type | Options |
| :---- | :---- | :---- |
| `id` | Auto (PB) | PK |
| `from_user` | Relation → users | Required, cascade delete |
| `to_user` | Relation → users | Required, cascade delete |
| `status` | Select | pending / accepted / declined |
| `created` | Auto (PB) |  |
| `updated` | Auto (PB) |  |

**Rules:**

listRule:   @request.auth.id \= from\_user || @request.auth.id \= to\_user

viewRule:   @request.auth.id \= from\_user || @request.auth.id \= to\_user

createRule: @request.auth.id \= from\_user && @request.auth.id \!= to\_user

updateRule: @request.auth.id \= to\_user && status \= "pending"

deleteRule: @request.auth.id \= from\_user || @request.auth.id \= to\_user

---

### 7.3 Collection: `friendships`

| Field | Type | Options |
| :---- | :---- | :---- |
| `id` | Auto (PB) | PK |
| `user_a` | Relation → users | Required, cascade delete |
| `user_b` | Relation → users | Required, cascade delete |
| `created` | Auto (PB) |  |

**Rules:**

listRule:   @request.auth.id \= user\_a || @request.auth.id \= user\_b

viewRule:   @request.auth.id \= user\_a || @request.auth.id \= user\_b

createRule: @request.auth.id \= user\_a

updateRule: null

deleteRule: @request.auth.id \= user\_a || @request.auth.id \= user\_b

Note: When a friend request is accepted, create one `friendships` record. user\_a \= requester, user\_b \= acceptor.

---

### 7.4 Collection: `conversations`

| Field | Type | Options |
| :---- | :---- | :---- |
| `id` | Auto (PB) | PK |
| `type` | Select | direct / group |
| `name` | Text | Optional (groups only), max 50 |
| `icon` | File | Optional (groups only) |
| `created_by` | Relation → users | Required |
| `only_admins_can_message` | Boolean | Optional (groups only) default: false|
| `last_message_preview` | Text | Optional, max 200 (plain text preview) |
| `last_message_at` | DateTime | Optional |
| `disappearing_duration` | Number | 0 \= off, or seconds (86400/604800/2592000) |
| `created` | Auto (PB) |  |
| `updated` | Auto (PB) |  |

**Rules:**

listRule:   @collection.conversation\_members.user\_id ?= @request.auth.id

viewRule:   @collection.conversation\_members.user\_id ?= @request.auth.id

createRule: @request.auth.id \!= ""

updateRule: @collection.conversation\_members.user\_id ?= @request.auth.id

deleteRule: null

---

### 7.5 Collection: `conversation_members`

| Field | Type | Options |
| :---- | :---- | :---- |
| `id` | Auto (PB) | PK |
| `conversation_id` | Relation → conversations | Required, cascade delete |
| `user_id` | Relation → users | Required, cascade delete |
| `role` | Select | member / admin |
| `joined_at` | DateTime | Auto-set on create |
| `muted_until` | DateTime | Optional |
| `last_read_message_id` | Text | Optional (message ID) |
| `created` | Auto (PB) |  |

**Rules:**

listRule:   @request.auth.id \= user\_id || @collection.conversation\_members.user\_id ?= @request.auth.id

viewRule:   @request.auth.id \= user\_id

createRule: @request.auth.id \!= ""

updateRule: @request.auth.id \= user\_id

deleteRule: @request.auth.id \= user\_id

---

### 7.6 Collection: `messages`

| Field | Type | Options |
| :---- | :---- | :---- |
| `id` | Auto (PB) | PK |
| `conversation_id` | Relation → conversations | Required, cascade delete |
| `sender_id` | Relation → users | Required, cascade delete |
| `type` | Select | text / image / video / voice / poll / system |
| `encrypted_body` | Text | Required for text, base64 encoded ciphertext |
| `iv` | Text | Required, base64 encoded AES IV |
| `reply_to_id` | Text | Optional, message ID |
| `reply_preview` | Text | Optional, encrypted short preview of replied msg |
| `is_deleted_for_everyone` | Bool | Default: false |
| `deleted_for_user_ids` | JSON | Array of user IDs who deleted for themselves |
| `is_pinned` | Bool | Default: false |
| `is_starred_by` | JSON | Array of user IDs who starred this message |
| `expires_at` | DateTime | Optional, for disappearing messages |
| `created` | Auto (PB) |  |
| `updated` | Auto (PB) |  |

**Rules:**

listRule:   @collection.conversation\_members.user\_id ?= @request.auth.id && @collection.conversation\_members.conversation\_id \= conversation\_id

viewRule:   @collection.conversation\_members.user\_id ?= @request.auth.id

createRule: @request.auth.id \= sender\_id && @collection.conversation\_members.user\_id ?= @request.auth.id

updateRule: @request.auth.id \= sender\_id || @collection.conversation\_members.role \= "admin"

deleteRule: null

---

### 7.7 Collection: `message_media`

| Field | Type | Options |
| :---- | :---- | :---- |
| `id` | Auto (PB) | PK |
| `message_id` | Relation → messages | Required, cascade delete |
| `conversation_id` | Relation → conversations | Required (for media viewer queries) |
| `file` | File | Required, max 100MB |
| `media_type` | Select | image / video / voice / document |
| `media_id` | Text |  |
| `file_name` | Text | Required |
| `file_size` | Number | Bytes |
| `duration_seconds` | Number | Optional (video/voice) |
| `thumbnail` | File | Optional (video/image) |
| `quality` | Select | normal / high |
| `expires_at` | DateTime | Required — set based on media retention policy |
| `created` | Auto (PB) |  |

**Rules:**

listRule:   @collection.conversation\_members.user\_id ?= @request.auth.id

viewRule:   @collection.conversation\_members.user\_id ?= @request.auth.id

createRule: @request.auth.id \!= ""

updateRule: null

deleteRule: null

---

### 7.8 Collection: `message_receipts`

This collection is the backbone of the read receipt system.

| Field | Type | Options |
| :---- | :---- | :---- |
| `id` | Auto (PB) | PK |
| `message_id` | Text | Required (not a relation — avoids cascade issues) |
| `conversation_id` | Text | Required (for batch queries) |
| `recipient_id` | Relation → users | Required |
| `delivered_at` | DateTime | Optional — set by FCM background handler |
| `read_at` | DateTime | Optional — set when recipient opens the chat |
| `created` | Auto (PB) |  |
| `updated` | Auto (PB) |  |

**Rules:**

listRule:   @request.auth.id \= recipient\_id || @collection.messages.sender\_id ?= @request.auth.id

viewRule:   @request.auth.id \= recipient\_id

createRule: @request.auth.id \!= ""

updateRule: @request.auth.id \= recipient\_id

deleteRule: null

---

### 7.9 Collection: `reactions`

| Field | Type | Options |
| :---- | :---- | :---- |
| `id` | Auto (PB) | PK |
| `message_id` | Text | Required |
| `conversation_id` | Text | Required |
| `user_id` | Relation → users | Required, cascade delete |
| `emoji` | Text | Required, max 10 chars |
| `created` | Auto (PB) |  |

**Rules:**

listRule:   @collection.conversation\_members.user\_id ?= @request.auth.id

viewRule:   @collection.conversation\_members.user\_id ?= @request.auth.id

createRule: @request.auth.id \= user\_id

updateRule: @request.auth.id \= user\_id

deleteRule: @request.auth.id \= user\_id

---

### 7.10 Collection: `polls`

| Field | Type | Options |
| :---- | :---- | :---- |
| `id` | Auto (PB) | PK |
| `message_id` | Text | Required |
| `conversation_id` | Text | Required |
| `question` | Text | Required, max 200 |
| `options` | JSON | Array of {id, text} objects |
| `votes` | JSON | Map of {option\_id: \[user\_ids\]} |
| `is_closed` | Bool | Default: false |
| `created_by` | Relation → users | Required |
| `created` | Auto (PB) |  |
| `updated` | Auto (PB) |  |

**Rules:**

listRule:   @collection.conversation\_members.user\_id ?= @request.auth.id

viewRule:   @collection.conversation\_members.user\_id ?= @request.auth.id

createRule: @request.auth.id \= created\_by

updateRule: @collection.conversation\_members.user\_id ?= @request.auth.id

deleteRule: @request.auth.id \= created\_by

---

### 7.11 Collection: `blocked_users`

| Field | Type | Options |
| :---- | :---- | :---- |
| `id` | Auto (PB) | PK |
| `blocker_id` | Relation → users | Required, cascade delete |
| `blocked_id` | Relation → users | Required, cascade delete |
| `created` | Auto (PB) |  |

**Rules:**

listRule:   @request.auth.id \= blocker\_id

viewRule:   @request.auth.id \= blocker\_id

createRule: @request.auth.id \= blocker\_id

updateRule: null

deleteRule: @request.auth.id \= blocker\_id

---

### 7.12 Collection: `scheduled_messages`

| Field | Type | Options |
| :---- | :---- | :---- |
| `id` | Auto (PB) | PK |
| `sender_id` | Relation → users | Required, cascade delete |
| `conversation_id` | Relation → conversations | Required, cascade delete |
| `encrypted_body` | Text | Required |
| `iv` | Text | Required |
| `send_at` | DateTime | Required |
| `sent` | Bool | Default: false |
| `created` | Auto (PB) |  |

**Rules:**

listRule:   @request.auth.id \= sender\_id

viewRule:   @request.auth.id \= sender\_id

createRule: @request.auth.id \= sender\_id

updateRule: @request.auth.id \= sender\_id

deleteRule: @request.auth.id \= sender\_id

---


### 7.13 Collection: `group_keys`

| Field | Type | Options |
| :---- | :---- | :---- |
| `id` | Auto (PB) | PK |
| `conversation_id` | Relation → conversations | Required, cascade delete |
| `user_id` | Relation → users | Required, cascade delete |
| `encrypted_key` | Text | Required  format: ivBase64:ciphertextBase64 |
| `encrypted_by_user_id` | Relation → users | Required (the admin who created it) |
| `key_version` | Number | Required, default: 1 |
| `created` | Auto (PB) |  |
| `updated` | Auto (PB) |  |



**Rules:**

listRule:   @request.auth.id = user_id.id

viewRule:   @request.auth.id = user_id.id

createRule: @request.auth.id != ""

updateRule: @request.auth.id != ""

deleteRule: null

---


### 7.14 Collection: `deleted_messages_for_me`

| Field | Type | Options |
| :---- | :---- | :---- |
| `id` | Auto (PB) | PK |
| `user_id` | Relation → users | Required, cascade delete |
| `message_id` | Text | Required - server message id |
| `conversation_id` | Text | Required |
| `created` | Auto (PB) |  |
| `updated` | Auto (PB) |  |

**Rules:**

listRule:   @request.auth.id = user_id.id

viewRule:   @request.auth.id = user_id.id

createRule: @request.auth.id != ""

updateRule: null

deleteRule: @request.auth.id = user_id.id


### 7.15 Collection: `starred_messages`

| Field | Type | Options |
| :---- | :---- | :---- |
| `id` | Auto (PB) | PK |
| `user_id` | Relation → users | Required, cascade delete |
| `message_id` | Text | Required - server message id |
| `conversation_id` | Text | Required |
| `message_preview` | Text | Plaintext preview — so starred screen doesn't need to re-decrypt |
| `sender_id` | Text | For "sent by You vs Contact" label |
| `starred_at` | DateTime | Auto:@now |
| `created` | Auto (PB) |  |
| `updated` | Auto (PB) |  |

**Rules:**

listRule:   @request.auth.id = user_id.id

viewRule:   @request.auth.id = user_id.id

createRule: @request.auth.id != ""

updateRule: null

deleteRule: @request.auth.id = user_id.id



### 7.16 PocketBase Hooks / Scheduled Jobs

These need to be implemented as PocketBase hooks (JS hooks file) or an external cron script:

1. **Media expiry deletion** — daily job, deletes `message_media` records where `expires_at < now()`  
2. **Disappearing messages** — hourly job, deletes `messages` where `expires_at < now()`  
3. **Online status reset** — if `last_seen` \> 5 minutes ago, set `is_online = false`  
4. **Scheduled messages sender** — every minute, find unsent `scheduled_messages` where `send_at <= now()`, send them

---

## 8\. Encryption Specification

### Algorithm

- **Key Exchange:** X25519 ECDH (Elliptic Curve Diffie-Hellman)  
- **Message Encryption:** AES-256-GCM (authenticated encryption)  
- **Key Derivation:** HKDF-SHA256

### Key Management

On first login:

  → Generate X25519 key pair

  → Store private key in flutter\_secure\_storage (hardware-backed keystore on Android)

  → Upload public key to users.public\_key field (add this field to users collection)

On first message to a new contact:

  → Fetch their public key from PocketBase

  → Perform X25519 ECDH → shared\_secret

  → Derive encryption\_key via HKDF(shared\_secret, "kuchbhi-v1")

  → Cache derived key in flutter\_secure\_storage keyed by contact's user ID

Encrypting a message:

  → Generate random 12-byte IV

  → AES-256-GCM encrypt(plaintext, encryption\_key, iv) → ciphertext

  → Store: base64(ciphertext) as encrypted\_body, base64(iv) as iv

Decrypting a message:

  → Retrieve cached encryption\_key for sender

  → AES-256-GCM decrypt(base64decode(encrypted\_body), encryption\_key, base64decode(iv))

For groups:

  → Generate a random AES-256 group key on group creation

  → Encrypt the group key with each member's public key individually

  → Store encrypted group keys in a group\_keys collection (add this)

### Add to Schema: `group_keys` collection

| Field | Type |
| :---- | :---- |
| `group_id` | Text (conversation ID) |
| `member_id` | Relation → users |
| `encrypted_key` | Text (base64) — group key encrypted with member's public key |

**Rules:**

listRule:   @request.auth.id \= member\_id

viewRule:   @request.auth.id \= member\_id

createRule: @request.auth.id \!= ""

updateRule: null

deleteRule: null

### Performance Note

All crypto operations MUST run in a Dart isolate via `Isolate.run()` or `compute()`.  
Never run encryption/decryption on the main thread. This was the cause of UI jank in the previous version.

---

## 9\. FCM & Notification Architecture

### The Delivered Receipt Problem (Priority Fix)

**Root cause of the previous bug:** Delivered status was only updated when the chat was open. The app was not handling FCM background messages.

**Solution:**

flutter\_background\_service \+ FCM background handler

  → Fires even when app is killed

  → On receiving any FCM message:

     1\. Parse message\_id from FCM data payload

     2\. Call PocketBase: PATCH message\_receipts where message\_id \= X, set delivered\_at \= now()

     3\. This triggers PocketBase real-time → sender's app updates tick to double tick

### FCM Message Types

All FCM messages use **data-only payloads** (no notification payload).  
This ensures the background handler always fires, even on Android 13+ with notification permissions denied.

// New message FCM payload

{

  "type": "new\_message",

  "message\_id": "abc123",

  "conversation\_id": "xyz789",

  "sender\_id": "user456",

  "sender\_name": "Arjun"

}

// Friend request FCM payload

{

  "type": "friend\_request",

  "request\_id": "req001",

  "from\_user\_id": "user123",

  "from\_user\_name": "Priya"

}

### Background Handler

In `main.dart`:

@pragma('vm:entry-point')

Future\<void\> firebaseMessagingBackgroundHandler(RemoteMessage message) async {

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Mark as delivered in PocketBase

  // Show local notification via flutter\_local\_notifications

}

### Notification Channels (Android)

| Channel | ID | Importance | Purpose |
| :---- | :---- | :---- | :---- |
| Messages | `kb_messages` | High | New chat messages |
| Friend Requests | `kb_requests` | Default | New friend requests |
| System | `kb_system` | Low | Updates, sync events |

---

## 10\. Google OAuth Flow

PocketBase's built-in OAuth redirect flow does not work inside a Flutter in-app webview.

**Correct Flow:**

// 1\. Use google\_sign\_in package

final GoogleSignIn \_googleSignIn \= GoogleSignIn(

  scopes: \['email', 'profile'\],

);

final GoogleSignInAccount? account \= await \_googleSignIn.signIn();

final GoogleSignInAuthentication auth \= await account\!.authentication;

final String idToken \= auth.idToken\!;

// 2\. Send idToken to PocketBase

final pb \= PocketBaseClient.instance;

final authData \= await pb.collection('users').authWithOAuth2(

  'google',

  (url) async {

    // This callback is NOT used in this flow

    // We override with the token directly

  },

  createData: {

    'display\_name': account.displayName ?? '',

  },

);

// 3\. Alternatively, use the raw HTTP endpoint

// POST /api/collections/users/auth-with-oauth2

// Body: { provider: "google", code: idToken, redirectUrl: "" }

**Verify this flow works with PocketBase 0.37.5 before starting development. Test in Phase 0\.**

---

## 11\. Media Handling

### Compression Settings

| Type | Normal Quality | High Quality |
| :---- | :---- | :---- |
| Image | JPEG 60%, max 1280px | JPEG 90%, max 2560px |
| Video | 720p, 1.5Mbps | 1080p, 4Mbps |
| Voice | Opus 64kbps | Opus 128kbps |

### Media Retention Policy

| Type | Server Retention |
| :---- | :---- |
| Voice messages | 60 days |
| Photos (normal) | 60 days |
| Photos (high) | 30 days |
| Videos (normal) | 30 days |
| Videos (high) | 15 days |
| Documents | 60 days |
| Text messages | Indefinite |

`expires_at` is set at upload time. PocketBase cron job deletes expired records and files daily.

### Local Caching

- `cached_network_image` for profile pictures and image thumbnails  
- Downloaded media saved to app-specific external storage (`getExternalStorageDirectory()`)  
- Show "Expires in X days" label when remaining time \< 30% of retention period

---

## 12\. Adaptive Layout Specification

### Breakpoints

| Name | Width | Layout |
| :---- | :---- | :---- |
| Compact | \< 600dp | Single panel (standard phone) |
| Medium | 600–840dp | Two-panel (list \+ chat side by side) |
| Expanded | \> 840dp | Two-panel with wider chat |

### Two-Panel Layout (Medium/Expanded)

- Left panel (fixed 360dp): Conversations list  
- Right panel (remaining): Active chat, or a "Select a conversation" empty state  
- Use `NavigationDrawer` pattern from Material 3

### Z Fold 5 Specific

- Detect fold state using `flutter_window_manager` or `device_info_plus`  
- Cover screen → Compact layout  
- Inner screen unfolded → Medium/Expanded layout  
- Handle layout state changes without losing scroll position or message drafts

---

## 13\. Phased Development Plan

**Rule:** Each phase must be fully tested and signed off before the next phase begins.  
**Rule:** Never skip steps. Never merge incomplete phases.

---

### Phase 0: Infrastructure Setup (Do This Before ANY Code)

- [ ] Create Firebase project → enable FCM → download `google-services.json`  
- [ ] Enable Google Sign-In in Firebase Console \+ Google Cloud Console  
- [ ] Verify Google OAuth flow with PocketBase 0.37.5 (manual test via curl/Postman)  
- [ ] Create all PocketBase collections per Section 7 schema  
- [ ] Set all collection rules per Section 7  
- [ ] Add `public_key` field to users collection  
- [ ] Set up PocketBase cron hooks (media expiry, disappearing messages)  
- [ ] Verify PocketBase real-time subscriptions work (test via PB admin UI)  
- [ ] Set up Oracle VM cron job to keep VM alive  
- [ ] Set up automated PocketBase backup script (daily backup of pb\_data to a second location)  
- [ ] Create GitHub repository, set up GitHub Releases workflow

---

### Phase 1: Project Skeleton

- [ ] Create Flutter project: `flutter create --org com.chai kuch_bhi`  
- [ ] Set up folder structure per Section 4  
- [ ] Add all dependencies per Section 2  
- [ ] Configure `go_router` with all route definitions (even empty screens)  
- [ ] Set up Riverpod `ProviderScope` at root  
- [ ] Set up Drift database with all tables (empty, just structure)  
- [ ] Set up PocketBase client singleton  
- [ ] Set up theme system (Light / Dark / AMOLED) with Inter font  
- [ ] Set up flavors or environment config (dev vs prod base URL)  
- [ ] Run on Android emulator: app opens, no crashes, correct theme

---

### Phase 2: Authentication

- [ ] Email \+ password sign in screen  
- [ ] Email \+ password register screen (with friend code auto-generation)  
- [ ] Google Sign-In button → full OAuth flow per Section 10  
- [ ] Auth state persistence (auto-login on relaunch)  
- [ ] App Lock (biometric/PIN) — optional user setting  
- [ ] Profile setup screen (name \+ avatar) on first login  
- [ ] Logout

**Test:** Sign up, close app, reopen → auto logged in. Test Google OAuth.

---

### Phase 3: Friend System

- [ ] Friend code display on profile  
- [ ] QR code generation from friend code  
- [ ] Search by friend code  
- [ ] QR scanner (camera)  
- [ ] QR from gallery (image picker → decode QR)  
- [ ] Send friend request  
- [ ] Receive friend request (real-time via PocketBase subscription)  
- [ ] Accept / decline request  
- [ ] Friends list  
- [ ] Block / unblock user  
- [ ] Custom nickname (local Drift storage)

**Test:** Two test devices. Full request → accept flow. Verify real-time update.

---

### Phase 4: Core Messaging (1-on-1)

- [ ] Create conversation on first message  
- [ ] Send text message → encrypt → upload to PocketBase  
- [ ] Receive message via real-time subscription → decrypt → display  
- [ ] Local Drift DB persistence for all messages  
- [ ] Offline message queue with retry  
- [ ] Single tick (sent) indicator  
- [ ] FCM background handler → mark delivered → double tick  
- [ ] Open chat → mark read → colored double tick  
- [ ] Typing indicator (debounced)  
- [ ] Online / Last seen status  
- [ ] "In chat" indicator when both users are in the same chat

**Test:** Full message send/receive. Kill app → receive message → reopen → delivered tick appears correctly. This is the most critical test.

---

### Phase 5: Advanced Messaging

- [ ] Swipe to reply  
- [ ] Long press menu (Reply, Copy, Star, Pin, Forward, Delete for me, Delete for everyone, React)  
- [ ] Message reactions  
- [ ] Link previews  
- [ ] Message search within conversation  
- [ ] Starred messages page  
- [ ] Pinned messages banner  
- [ ] Disappearing messages setting
- [ ] No text box when only emojis are sent.

---

### Phase 6: Media Messaging

- [ ] Photo sharing (with compression, quality toggle)  
- [ ] Video sharing (with compression, quality toggle)  
- [ ] Voice message recording \+ playback (with speed control)  
- [ ] In-app media viewer (full screen photo/video)  
- [ ] Media & Docs page (per-chat, filtered by type)  
- [ ] Media expiry indicator

---

### Phase 7: Group Chats

- [ ] Create group  
- [ ] Group encryption (group key system per Section 8\)  
- [ ] Add/remove members  
- [ ] Admin roles  
- [ ] Group settings page  
- [ ] "Only admins can message" toggle

---

### Phase 8: Polls & Scheduled Messages

- [ ] Poll creation in chat  
- [ ] Poll voting  
- [ ] Scheduled messages (compose \+ datetime picker)  
- [ ] Background service sends scheduled messages

---

### Phase 9: UI Polish & Adaptive Layout

- [ ] Tablet / Z Fold 5 two-panel layout (Section 12\)  
- [ ] Chat wallpaper support  
- [ ] All animations and transitions  
- [ ] AMOLED theme  
- [ ] Easter eggs

---

### Phase 10: Settings & Utilities

- [ ] Full settings page  
- [ ] Per-chat notification mute  
- [ ] Storage management page  
- [ ] Export chat as .txt  
- [ ] In-app GitHub Releases update checker  
- [ ] Delete account (full cascade)

---

### Phase 11: Testing & Hardening

- [ ] Test on low-end Android device (2GB RAM target)  
- [ ] Test with spotty network (airplane mode toggling)  
- [ ] Verify all receipt states work end-to-end  
- [ ] Verify encryption/decryption with 3+ users simultaneously  
- [ ] Memory profiling — fix any leaks  
- [ ] Fix any remaining jank (target: stable 60fps)

---

## 14\. Coding Agent Rules & Protocols

**These rules are non-negotiable. Follow them exactly.**

### General Rules

1. Read this entire document before writing any code.  
2. Do not install any package not listed in Section 2 without explicit developer approval.  
3. Do not modify the PocketBase schema after Phase 0 without a migration plan.  
4. Never put business logic in a Widget class.  
5. Never run crypto, compression, or heavy I/O on the main isolate.  
6. Use `const` constructors on every widget that can be const.  
7. Use `ListView.builder` (never `Column` with mapped children) for any list that could have more than 10 items.  
8. All strings shown to the user must come from a constants file or localization — no hardcoded UI strings in widget files.  
9. Every function must have a doc comment explaining what it does.  
10. No `print()` statements in production code. Use a proper logger.

### Error Handling Rules

11. Every async function must handle errors with try/catch.  
12. Network errors must never crash the app — show a user-friendly message.  
13. Decryption failure must show "Message could not be decrypted" — never a crash.  
14. If a PocketBase call fails, log it and fail gracefully.

### Testing Rules

15. After completing each Phase, run the app on a physical Android device.  
16. Test the current phase's features end-to-end before reporting completion.  
17. Do not start the next phase unless the current one passes all tests.

### Git Rules

18. One commit per completed sub-task.  
19. Commit message format: `[Phase X] Brief description`  
20. Never commit with broken code.

### What to Do When Stuck

21. If you are unsure about an implementation decision, STOP and ask the developer.  
22. Do not guess at PocketBase rule syntax — refer to Section 7\.  
23. Do not guess at encryption implementation — refer to Section 8 exactly.

---

## 15\. Setup Checklist

Complete these in order before writing any Flutter code:

### Firebase / FCM

- [ ] Go to [https://console.firebase.google.com](https://console.firebase.google.com)  
- [ ] Create project: `kuch-bhi`  
- [ ] Add Android app with package name `com.chai.kuch_bhi`  
- [ ] Download `google-services.json` → place in `android/app/`  
- [ ] Enable Cloud Messaging in Firebase Console  
- [ ] Enable Google Sign-In provider in Firebase → Authentication → Sign-in methods  
- [ ] Note down: Server key (for PocketBase FCM integration), Sender ID

### Google Cloud Console

- [ ] Go to [https://console.cloud.google.com](https://console.cloud.google.com)  
- [ ] Select the Firebase-linked project  
- [ ] APIs & Services → Enable: Google Sign-In API  
- [ ] OAuth Consent Screen → set app name to "Kuch Bhi", add test users  
- [ ] Create OAuth 2.0 Client ID → Android type → package name `com.chai.kuch_bhi` \+ SHA-1 fingerprint

### PocketBase

- [ ] Log in to [https://kuch-bhi.duckdns.org/\_/](https://kuch-bhi.duckdns.org/_/)  
- [ ] Create all collections per Section 7 in exact order  
- [ ] Set all rules per Section 7  
- [ ] Test real-time subscriptions via the PocketBase admin logs  
- [ ] Create a test user manually to verify auth works

### Oracle VM

- [ ] Set up cron: `*/30 * * * * curl -s http://localhost:8090/api/health`  
- [ ] Set up daily backup: `0 2 * * * tar -czf /backup/pb_data_$(date +\%Y\%m\%d).tar.gz /path/to/pb_data`

### Flutter

- [ ] `flutter --version` — confirm on stable channel  
- [ ] `flutterfire configure` — links Flutter project to Firebase  
- [ ] Confirm `google-services.json` is in place  
- [ ] First build succeeds: `flutter run`

---

## 16\. Known Pitfalls & Solutions

| Problem | Solution |
| :---- | :---- |
| Delivered tick never updates if chat not open | FCM data-only background handler updates receipt. See Section 9\. |
| Flutter UI jank / frame drops | No crypto on main thread. `const` widgets everywhere. `ListView.builder` always. |
| PocketBase Google OAuth doesn't work with in-app browser | Use `google_sign_in` package \+ token exchange. See Section 10\. |
| Oracle VM gets terminated | Keep-alive cron job every 30 minutes. |
| Messages not loading after app reopen | Offline-first: load from Drift DB immediately, sync remote in background. |
| Encryption too slow | Run in background isolate via `Isolate.run()`. AES-GCM is hardware-accelerated. |
| Media storage fills up | Server-side expiry with `expires_at` field \+ daily cron deletion job. |
| Multiple devices showing duplicate messages | Use message ID deduplication in Drift upsert, not insert. |
| Background service killed on Android | Use `flutter_background_service` with foreground service mode \+ wake lock. |
| Z Fold 5 layout breaks on unfold | Listen to `MediaQuery` width changes in `LayoutBuilder`, rebuild layout panel.  |
| NDK clang "Exec format error" on Arch/CachyOS | Use NDK version 30.0.14904198. Set ndkVersion in build.gradle.kts |
| Sub-packages (jni, mobile\_scanner etc.) use NDK 28 on Arch/CachyOS | Add subprojects NDK override block to android/build.gradle |
| Any package hardcoding NDK 28 fails on Arch/CachyOS | Symlink \~/Android/Sdk/ndk/28.2.13676358 → 30.0.14904198 |

---

*End of Project Bible v1.0*  
