# Offline Bill Numbering (v0.4.3)

Two phones of the same shop work offline. The OLD scheme allocated
`MAX(no) + 1` on each phone, so both phones could save "bill #12"
while offline. v0.4.1 added a post-sync healer; v0.4.3 goes further -
**the collision can no longer happen**:

## Per-device slots

Every registered device owns one slot of 100000 numbers
(`users/{uid}.registeredDevices` list position):

| Slot | Range | Who uses it |
|---|---|---|
| 0 | 1 .. 99,999 | legacy rows + shops with exactly ONE registered device (plain numbering, unchanged look) |
| 1 | 100,000 .. 199,999 | 1st device of a multi-device shop |
| 2 | 200,000 .. 299,999 | 2nd device |
| 9 | 900,000 .. 999,999 | fallback: device not yet in registeredDevices (fresh offline install) |

Rules that make this safe:

* The Firestore rules (`firestore.rules`) only allow the
  `registeredDevices` list to GROW or SHRINK - never a wholesale swap -
  so the slot positions are stable across devices.
* Slots are written into the local `meta` table by AccessService on
  every account refresh (login, live snapshot, verify-on-sync tick).
* Number allocation is `MAX(col)+1` restricted to the device's own
  range (`lib/data/repo.dart`, `_nextInSlot`), applied to
  `bill_no`, `purchase_no`, `sales_returns.return_no` and
  `purchase_returns.return_no`.
* **Purane numbers kabhi nahi badalte.** Legacy bills keep 1, 2, 3...;
  only NEW numbers move into the device's slot. A single-device shop
  (slot 0) sees no visual change at all.
* The v0.4.1 duplicate healer still runs after every sync as a
  belt-and-braces net for rows created by older app versions and the
  slot-9 fallback corner - and it now also covers the two RETURN
  ledgers (sales_returns + purchase_returns), which were the gap found
  in the independent audit.

## Mixed-version note

Until BOTH phones install the update, an old-version phone still uses
plain MAX+1 (it can pick 100,002 next to a new phone's 100,001). The
healer resolves such pairs deterministically after the first sync
(oldest keeps the number). Update both phones promptly; after that,
collisions are impossible by construction.
