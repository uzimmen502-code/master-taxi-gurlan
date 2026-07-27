# Social Module — "Mening yaqinlarim" (relatives + circles + dating + family tree)

Hub: `lib/features/circles/screens/circles_hub_screen.dart` (cards: Sinfdosh / Kursdosh / Hamkasb / Qarindosh). Tanishuv — faqat bosh ekran grid (`home_screen` → **Telegram** `https://t.me/bilish_tanish_bot`, not in-app `DatingHomeScreen`). Schema: `mem:firestore_schema`. CFs: `mem:cloud_functions`.
Dating card title: `'Танишув, мулоқат ва оила қуриш'`.

## Circles (generic engine: classmates/coursemates/colleagues)
- `features/circles/` — `circle_screen.dart` (tabs: members/feed/events/album/chat), repo + controller. Firestore `circles/{id}` + subcollections members/posts/events/album/chat/subgroups (see schema). type ∈ classmates|coursemates|colleagues.
- Pure Firestore (NO cloud functions); writes guarded by rules (self-write members, member-scoped). Auto-join logic for class circle by school+grad-year.
- "My circles" list uses `collectionGroup('members') where userId == self` (`watchMyCircleIds`). CRITICAL: collectionGroup queries are NOT authorized by the nested `match /circles/{id}/members/{mid}` rule — they REQUIRE a top-level recursive rule `match /{path=**}/members/{memberId} { allow read: if resource.data.userId == circleUserId(); }`. Without it the list is empty (PERMISSION_DENIED) so circles look like they "disappear" after leaving the screen, even though membership persists. circleUserId() = phone digits from `request.auth.token.phone_number`.
- GOTCHA: dialogs must dispose TextEditingController in try/finally (leak fixed in `_report`/`_createEvent`).

## Relatives (private, V1)
- `features/relatives/` — personal relative profiles, call, birthday reminders, photo album, events. Firestore `relatives/{uid}/people/{id}` (+ `/photos`), `relatives/{uid}/events/{id}` — OWNER-ONLY.
- Person fields: **firstName / lastName / patronymic** (шариф optional) + composed `fullName`; birthDate **manual** `kk.oo.yyyy` (optional). Smart ortho: `RelativeNameSmart` (normalize + Levenshtein); form suggests similar names (fix/merge/keep); tree dedup uses fuzzy groups.
- Person fields incl. fatherId/motherId/spouseId (nasab links chosen manually via "🌳 Насаб боғланиши" dropdown), relationship side (ota/ona tomon).
- OS push for birthdays/events via flutter_local_notifications.
- `relatives/people` is the user's PRIVATE source; mirrored to shared `tree_persons` by CF `onRelativePersonWrite`.
- Phone in relatives list → CF maintains `relative_phone_watchers`; on new user profile or owner login (`ensureMyTree`) one-time FCM: owner «қариндош иловада», new user «қариндошлар кутмоқда» → push opens `RelativesScreen`.
- **`ensureMyTree` call sites (2026-07):** NOT on Home cold start. Called from `RelativesScreen._loadPhone` (nasab/relatives open) + relative-related flows in `profile_controller`. Home no longer triggers the CF.
- **L10n (Phase 2 done):** all UI strings in `features/relatives/` use `context.tr('rel_*')` via `l10n_extension.dart` + `relatives/l10n/relatives_l10n.dart` helpers; ~122 keys in `assets/lang/*.json`; merge script `tools/merge_relatives_l10n.js`. Server-side history summaries / RelativeEventType.label (model) still raw where CF-generated.

## Dating (Tanishuv)
- **Home entry (2026-07):** `onDating` opens external Telegram bot `https://t.me/bilish_tanish_bot` via `url_launcher` (`LaunchMode.externalApplication`). In-app dating screens/CFs remain in repo for future integration.
- `features/dating/screens/` incl. `dating_profile_view_screen.dart`. Firestore `dating_profiles/{uid}`, `dating_interests`, `dating_matches`(+messages), `dating_blocks/{uid}/list/{targetId}`.
- Scope: user-defined; moderation: admin approve (status pending→approved); photos: open; interaction: interest/like; audience: opposite gender.
- CFs: saveDatingProfile, setDatingActive, setDatingAgePreference, deleteDatingProfile (profile+photos+interests+matches+blocks), adminModerateDatingProfile, ...
- GOTCHA: report dialog disposes controller in try/finally.
- **Youth promo push (18–23):** `DatingYouthPromoService.maybeShowOnAppOpen` — local notification on home init + app resume; age from `user_birth_date` / Firestore `users.birthDate`; rotates `dating_youth_promo_1..10` via OfflineL10n (uz_Cyrl/uz_Latn/ru); tap → still `DatingHomeScreen` (`type=dating_youth_promo`) via `push_navigation` (not yet Telegram). Skips driver/courier/admin. Debounce 4s.

## Family Tree (Nasab daraxti — GLOBAL graph, Phases F1–F5 done)
Architecture: per-user private `relatives/people` + SHARED global `tree_persons` graph keyed by `componentId`. `users/{uid}` carries treeComponentId, treePersonId, treeMigratedAt.
- UI: `family_tree_screen.dart` (combines personal `relatives/people` + shared component, personal precedence), `family_tree_view.dart` (CUSTOM genealogy layout, NOT graphview), `tree_history_screen.dart` (audit + undo).
- **Line routing (2026-07-13):** classic per-family geometry — vertical stem + horizontal bus (`allocateBusY` / `allocateStemX` by `laneId`+`corridorId=gen`) + child drops. Band segments registered; `route()` BFS skips occupied (T-junction OK). Dynamic `laneStepFor` (16–28) per gen. **Edge attach:** parent bottom center / child top center (no `linePad` gap). Bus Y range from card coords only (not raw `_corridorTop` — cards are `+_pad` translated). Obstacles = raw card rects. Fallback BFS if bus range empty. Tests: `test/features/relatives/family_tree_routing_test.dart`.
- Collections: tree_persons (nodes; survivorId on merge), tree_link_invites (two-sided), tree_redirects (oldId→survivor), tree_history (audit). All CF-only writes.
- CFs by phase: F1 ensureMyTree + onRelativePersonWrite; F2 send/respondTreeLinkInvite; F3 mergeTreePersons; F4 undoTreeOperation; F5 saveTreeNode.
- Privacy: link = mutual consent; linked members see WHOLE shared tree.
- Phase-1/2/3: addRelativePerson, redirects, GEDCOM/PNG/PDF export.
- GOTCHAS: translateByDouble/scaleByDouble; TREE tab prefers component for genealogy fields (CRM fields personal); merge must update tree_redirects.
- Cleanup 2026-07: removed unused `watchSentInvites`; `TreeNodeEditScreen` edit-only (no dead create); invites auto-sheet only when `openTreeInvites` (push); deleted unused `HomeTickerBar`+`home_ticker_layout` (home uses `HomeInfoTicker`).
- P0 2026-07: owned person edit → `saveTreeNode` (genealogy) + `updatePersonCrm` (phone/address/side/notes); `RelativeFormScreen` tabs Шахсий|Насаб; tree node sheet single Edit (own→form, other→TreeNodeEdit); `family_tree_view_parts.dart` extracted painters/node models.
- P1 2026-07: no full-collection `watchRedirects`; `TreeRepository.fetchRedirectsForIds` + `collectTreeRelatedIds`; `FamilyTreeBundleSource` single stream for tree screen; link candidates use scoped redirects.
- P2 2026-07: tree export → Relatives AppBar overflow (`TreeExportHandle`); Home tile opens `RelativesScreen` (circles via AppBar → CirclesHub, Relatives first in hub); invite accept privacy dialog; claimed+claimed = explain dialog only (no auto-merge).
