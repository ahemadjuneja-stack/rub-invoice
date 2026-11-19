# Remote Control (WhatsApp-style, no-update changes)

The app watches one Firestore document: **`config/app`**. Edit it from the
Firebase Console on your phone and every installed app picks the change up
within seconds - no new APK needed.

## Create the document (one time)

Firebase Console -> Firestore Database -> Start collection:

- Collection ID: `config`
- Document ID: `app`
- Add fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `notice` | string | Yellow announcement banner on the Billing tab. Empty string = hidden. |
| `min_version` | string | Force-update gate. If the installed version is older, the app opens a non-dismissable update screen with background download + Install. Empty string = off. |
| `features` | map | Per-feature on/off switches. Any key not listed = ON. |
| `auto_approve` | boolean | When `true` (default, also when the doc/field is missing) new registrations activate themselves instantly - no admin step. Set `false` to make every new account wait for admin approval. |

## Feature keys

`inventory`, `ledger`, `reports`, `backup`

(Menu tiles / list entries are hidden when the key is `false`.)

## Examples

Hide Reports and Backup for everyone, show a notice:

```
notice:      "GST bill format is live! Update from Menu -> Check Updates."
min_version: ""
features:    { reports: false, backup: false }
```

Force everyone below v0.3.0 to update (the app downloads the APK in the
background and shows a single Install button):

```
min_version: "0.3.0"
```

Clear everything:

```
notice: "", min_version: "", features: {}
```

## Security

`docs/firestore.rules` includes a `config/{doc}` block: every client can
read (flags hold no private data, and they apply even before sign-in),
only the Admin UID can write. Publish the rules once after adding it.
The Firebase Console document editor always bypasses rules, so the admin
can edit `config/app` even from a fresh phone.
