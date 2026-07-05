# Social Module — "Mening yaqinlarim" (relatives + circles + dating + family tree)

Hub: `lib/features/circles/screens/circles_hub_screen.dart` (cards: Qarindosh / Sinfdosh / Kursdosh / Hamkasb / Dating). Schema: `mem:firestore_schema`. CFs: `mem:cloud_functions`.
Dating card title: `'Танишув, мулоқат ва оила қуриш'`.

## Circles (generic engine: classmates/coursemates/colleagues)
- `features/circles/` — `circle_screen.dart` (tabs: members/feed/events/album/chat), repo + controller. Firestore `circles/{id}` + subcollections members/posts/events/album/chat/subgroups (see schema). type ∈ classmates|coursemates|colleagues.
- Pure Firestore (NO cloud functions); writes guarded by rules (self-write members, member-scoped). Auto-join logic for class circle by school+grad-year.
- "My circles" list uses `collectionGroup('members') where userId == self` (`watchMyCircleIds`). CRITICAL: collectionGroup queries are NOT authorized by the nested `match /circles/{id}/members/{mid}` rule — they REQUIRE a top-level recursive rule `match /{path=**}/members/{memberId} { allow read: if resource.data.userId == circleUserId(); }`. Without it the list is empty (PERMISSION_DENIED) so circles look like they "disappear" after leaving the screen, even though membership persists. circleUserId() = phone digits from `request.auth.token.phone_number`.
- GOTCHA: dialogs must dispose TextEditingController in try/finally (leak fixed in `_report`/`_createEvent`).

## Relatives (private, V1)
- `features/relatives/` — personal relative profiles, call, birthday reminders, photo album, events. Firestore `relatives/{uid}/people/{id}` (+ `/photos`), `relatives/{uid}/events/{id}` — OWNER-ONLY.
- Person fields incl. fatherId/motherId/spouseId (nasab links chosen manually via "🌳 Насаб боғланиши" dropdown), relationship side (ota/ona tomon).
- OS push for birthdays/events via flutter_local_notifications.
- `relatives/people` is the user's PRIVATE source; mirrored to shared `tree_persons` by CF `onRelativePersonWrite`.
- Phone in relatives list → CF maintains `relative_phone_watchers`; on new user profile or owner login (`ensureMyTree`) one-time FCM: owner «қариндош иловада», new user «қариндошлар кутмоқда» → push opens `RelativesScreen`.

## Dating (Tanishuv — MVP, CF-only writes)
- `features/dating/screens/` incl. `dating_profile_view_screen.dart`. Firestore `dating_profiles/{uid}`, `dating_interests`, `dating_matches`(+messages), `dating_blocks/{uid}/list/{targetId}`.
- Scope: user-defined; moderation: admin approve (status pending→approved); photos: open; interaction: interest/like; audience: opposite gender.
- CFs: saveDatingProfile, setDatingActive, setDatingAgePreference, deleteDatingProfile (profile+photos+interests+matches+blocks), adminModerateDatingProfile, ...
- GOTCHA: report dialog disposes controller in try/finally.

## Family Tree (Nasab daraxti — GLOBAL graph, Phases F1–F5 done)
Architecture: per-user private `relatives/people` + SHARED global `tree_persons` graph keyed by `componentId`. `users/{uid}` carries treeComponentId, treePersonId, treeMigratedAt.
- UI: `family_tree_screen.dart` (combines personal `relatives/people` + shared component, personal precedence), `family_tree_view.dart` (CUSTOM genealogy layout, NOT graphview), `tree_history_screen.dart` (audit + undo).
- `family_tree_view.dart`: slot layout + corridor Y. **Rules:** gen from `fatherId`/`motherId` per person (`_assignGenerationsFromPersonLinks`); child card always below parent; marriage outer = symbol only (stem inside padding); BFS per child to **that child's person card** (`preferShortestDirect: false`, no L-shortcut fallback); every segment validated vs person card interior.
- Collections: tree_persons (nodes; survivorId on merge), tree_link_invites (two-sided), tree_redirects (oldId→survivor), tree_history (audit). All CF-only writes.
- CFs by phase:
  - F1 ensureMyTree (create component+self node), onRelativePersonWrite (mirror relatives→tree_persons, redirect-aware).
  - F2 sendTreeLinkInvite/respondTreeLinkInvite (two-sided consent → component+node merge victim→survivor, writes tree_redirects + tree_history type=link).
  - F3 mergeTreePersons (dedup nodes within component, history type=merge).
  - F4 undoTreeOperation (reverse link/merge/edit/create from tree_history).
  - F5 saveTreeNode (any component member edits/creates node; mirrors to owner relatives/people WITHOUT clobbering; history create/edit).
- Privacy: link = mutual consent (invite→accept); linked members see WHOLE shared tree; any member can edit shared network.
- Phase-1 (FamilySearch-inspired): `addRelativePerson` single-id create; tree tab display prefers component for genealogy fields; link/merge rewrite `relatives` refs + remove placeholder; invite FCM + auto sheet on RelativesScreen; rules block client delete on `relatives/people`.
- Phase-2: client `tree_redirects` resolve for tree display; link dropdowns from personal+component (`buildLinkCandidates`); dedup by name+birth+gender with confirm dialog; `saveTreeNode` create via relatives mirror; undo link/merge restores `relatives/people` snapshots + ref changes.
- GOTCHAS: family_tree_view uses translateByDouble/scaleByDouble (Matrix4 translate/scale deprecated). Personal relatives/people takes precedence over mirror when combining on LIST tab; TREE tab prefers component for fatherId/motherId/spouseId/name. Merge logic victim→survivor must update tree_redirects to avoid mirror inconsistency.
