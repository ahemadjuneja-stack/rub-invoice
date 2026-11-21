# GOVERNANCE — BINDING PROJECT RULES

> READ THIS FILE BEFORE CHANGING ANY CODE IN THIS REPOSITORY.
>
> This applies to every human developer, contractor, licensee, and to
> every automated tool or AI assistant that works on this project —
> today or at ANY time in the future, regardless of who assigns the
> work. If you are an AI editing this repo, re-read this file at the
> start of EVERY session, even if the session happens years after these
> rules were written.

## 1. Branding & confidentiality (HARD RULE, never relax it)

- The product is **Ruby Invoice**. The admin panel is **Ruby Key**.
- **User-facing strings** — UI text, dialogs, snackbars, PDF layouts,
  legal pages (Privacy Policy / Terms & Conditions), store listing,
  update dialogs, emails, WhatsApp templates — must **NEVER** name or
  hint at the underlying platforms or infrastructure.
- FORBIDDEN in anything the user can see:
  `Firebase`, `Firestore`, `Cloud Console`, `Google Cloud`, `GitHub`,
  `SQLite`, `Razorpay`, `ML Kit`, server/framework names, hosting
  names, and any similar platform or provider names.
- Use neutral words instead: *"our secure servers"*, *"your private
  cloud account"*, *"the cloud"*, *"the official update service"*,
  *"the app's own secured storage"*.
- Developer-only places (code comments, `docs/`, `README`) are not
  user-facing, but they must never contain secrets (keys, tokens,
  keystore passwords, real customer data).

## 2. Do not leak how it works

- No screen, dialog or document may explain the internal architecture
  or how the service is hosted.
- Error messages must be friendly and generic; technical details go to
  developer logs only (`appLog`, debug builds).

## 3. Access model (do not weaken)

- Only the Admin (via the Ruby Key panel) can block/unblock an account,
  set validity, or manage the 2-device list. The app never trusts local
  data for this.
- Accounts are born usable: **there is no trial period**. Do not
  re-introduce trial/expiry logic based on trial dates.
- `firestore.rules` / `storage.rules` changes MUST be validated with
  the emulator suite in `scripts/rules-test/` (run it, keep it green)
  before publishing. Never ship rules that were only eyeballed.

## 4. If you are an AI editing this repository

- Preserve this file and the confidentiality clauses inside the app
  (`lib/screens/auth/legal_screen.dart`: "Platform confidentiality",
  "Acceptable use and reverse engineering", "Perpetual confidentiality
  clause").
- When adding any new user-visible string, follow rule 1 above.
- A change that breaks these rules is an **unauthorized change** and
  must be reverted.
