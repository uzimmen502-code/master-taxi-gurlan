# Social Module — "Mening yaqinlarim" (relatives + circles + dating + family tree)

Hub: `lib/features/circles/screens/circles_hub_screen.dart` (cards: Qarindosh / Sinfdosh / Kursdosh / Hamkasb / Dating). Schema: `mem:firestore_schema`. CFs: `mem:cloud_functions`.
Dating card title: `'Танишув, мулоқат ва оила қуриш'`.

## Circles (generic engine: classmates/coursemates/colleagues)
- `features/circles/` — `circle_screen.dart` (tabs: members/feed/events/album/chat), repo + controller. Firestore `circles/{id}` + subcollections members/posts/events/album/chat/subgroups (see schema). type ∈ classmates|coursemates|colleagues.
- Pure Firestore (NO cloud functions); writes guarded by rules (self-write members, member-scoped). Auto-join logic for class circle by school+grad-year.
- GOTCHA: dialogs must dispose TextEditingController in try/finally (leak fixed in `_report`/`_createEvent`).

## Relatives (private, V1)
- `features/relatives/` — personal relative profiles, call, birthday reminders, photo album, events. Firestore `relatives/{uid}/people/{id}` (+ `/photos`), `relatives/{uid}/events/{id}` — OWNER-ONLY.
- Person fields incl. fatherId/motherId/spouseId (nasab links chosen manually via "🌳 Насаб боғланиши" dropdown), relationship side (ota/ona tomon).
- OS push for birthdays/events via flutter_local_notifications.
- `relatives/people` is the user's PRIVATE source; mirrored to shared `tree_persons` by CF `onRelativePersonWrite`.

## Dating (Tanishuv — MVP, CF-only writes)
- `features/dating/screens/` incl. `dating_profile_view_screen.dart`. Firestore `dating_profiles/{uid}`, `dating_interests`, `dating_matches`(+messages), `dating_blocks/{uid}/list/{targetId}`.
- Scope: user-defined; moderation: admin approve (status pending→approved); photos: open; interaction: interest/like; audience: opposite gender.
- CFs: saveDatingProfile (→pending), setDatingActive, adminModerateDatingProfile, sendDatingInterest (mutual→match), respondDatingInterest. Admin UI `admin_web/screens/dating_moderation_screen.dart`.
- GOTCHA: report dialog disposes controller in try/finally.

## Family Tree (Nasab daraxti — GLOBAL graph, Phases F1–F5 done)
Architecture: per-user private `relatives/people` + SHARED global `tree_persons` graph keyed by `componentId`. `users/{uid}` carries treeComponentId, treePersonId, treeMigratedAt.
- UI: `family_tree_screen.dart` (combines personal `relatives/people` + shared component, personal precedence), `family_tree_view.dart` (CUSTOM genealogy layout, NOT graphview), `tree_history_screen.dart` (audit + undo).
- `family_tree_view.dart` rendering: couple-aware tidy-tree layout + CustomPainter. Spouses placed side-by-side joined by a dark-green (#1B5E20) horizontal line; parent↔child edges are orthogonal 90° only (vertical drop → horizontal sibling bus → vertical risers). Couples derived from spouseId + inferred co-parent pairs. Layout uses primary parent (father else mother) for tidy positioning (`_Unit.children`); EDGES are drawn per-person via `_Unit.edgeChildren` so EVERY child connects to BOTH father AND mother (even if in different units/generations) — no missing upward line. Pan/zoom via InteractiveViewer(constrained:false)+TransformationController+auto-fit. graphview package no longer used anywhere.
- Collections: tree_persons (nodes; survivorId on merge), tree_link_invites (two-sided), tree_redirects (oldId→survivor), tree_history (audit). All CF-only writes.
- CFs by phase:
  - F1 ensureMyTree (create component+self node), onRelativePersonWrite (mirror relatives→tree_persons, redirect-aware).
  - F2 sendTreeLinkInvite/respondTreeLinkInvite (two-sided consent → component+node merge victim→survivor, writes tree_redirects + tree_history type=link).
  - F3 mergeTreePersons (dedup nodes within component, history type=merge).
  - F4 undoTreeOperation (reverse link/merge/edit/create from tree_history).
  - F5 saveTreeNode (any component member edits/creates node; mirrors to owner relatives/people WITHOUT clobbering; history create/edit).
- Privacy: link = mutual consent (invite→accept); linked members see WHOLE shared tree; any member can edit shared network.
- GOTCHAS: family_tree_view uses translateByDouble/scaleByDouble (Matrix4 translate/scale deprecated). Personal relatives/people takes precedence over mirror when combining. Merge logic victim→survivor must update tree_redirects to avoid mirror inconsistency.
