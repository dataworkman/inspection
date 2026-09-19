# Bakery & Restaurant Inspection Platform

Fresh modular monolith MVP for franchise HQ inspection management. The repository was created as a new project with Rails and Flutter generator output; no existing bakery/storepilot project was copied.

## Prerequisites

- Ruby 3.4+
- Bundler
- SQLite
- libvips (image variants; required to boot the app in production, e.g. `apt-get install libvips`)
- Flutter stable channel (3.44+ for the bundled Android Gradle setup: AGP 9, Gradle 9.1, JDK 17)
- Xcode or Android Studio for iOS/Android simulators

## Rails Setup

```bash
cd backend
bundle install
bin/rails db:prepare
bin/rails db:seed
```

## Flutter Setup

```bash
cd mobile
flutter pub get
```

With mise:

```bash
mise exec flutter@latest -- flutter pub get
```

## Database Setup

MVP uses SQLite and Active Storage local disk. The Rails models avoid DB-specific SQL so PostgreSQL and S3 can be added later.

```bash
cd backend
bin/rails db:drop db:create db:migrate db:seed
```

Seed command:

```bash
bin/rails db:seed
```

Seed data creates Demo Bakery Group, three stores, Bakery Standard Inspection v1, four weighted categories, 20 questions, and demo users. The seeds are skipped in production (they contain known passwords) unless `SEED_DEMO_DATA=1` is set.

## Backend Run Command

```bash
cd backend
bin/rails server -b 0.0.0.0 -p 3002
```

The mobile app finds the API through `--dart-define=API_BASE_URL=...` (see below). Use the address your device can reach: `http://localhost:3002` for web/iOS simulator, `http://10.0.2.2:3002` for the Android emulator, or your machine's LAN/VPN IP for a physical device.

## Flutter Run Command

```bash
cd mobile
flutter run --dart-define=API_BASE_URL=http://<host>:3002
```

With mise:

```bash
mise exec flutter@latest -- flutter run --dart-define=API_BASE_URL=http://<host>:3002
```

`API_BASE_URL` defaults to `http://localhost:3002`. Plain HTTP works in debug/profile builds only; Android release builds block cleartext traffic, so point release builds at an HTTPS URL. The login form is prefilled with the demo inspector account in debug builds only.

## Configuration

| Variable | Where | Purpose |
| --- | --- | --- |
| `API_BASE_URL` | Flutter `--dart-define` | Backend address. Defaults to `http://localhost:3002`; use HTTPS for release builds. |
| `API_TOKEN_TTL_DAYS` | backend | Lifetime of a login session (default 30). |
| `CORS_ORIGINS` | backend | Comma-separated browser origins allowed to call the API. Unset means *any* origin in development/test and *none* in production (native apps are not affected). |
| `SEED_DEMO_DATA` | backend | Set to `1` to allow `db:seed` to create the demo data in production. |
| `SQLITE_DIR` | backend | Directory of the production SQLite files (default `storage`); put it on a persistent volume. |

## Demo Login Accounts

- HQ Admin: `admin@bakery-inspection.test` / `password123`
- Inspector: `inspector@bakery-inspection.test` / `password123`
- Store Manager: `manager@bakery-inspection.test` / `password123`

## Roles

| Role | Can do |
| --- | --- |
| `admin` | Everything inside their organization: stores, templates, dashboard, all inspections, all corrective actions. |
| `inspector` | Start and complete their own inspections (answers, photos, submit); create corrective actions on them and update actions on inspections they can see. |
| `store_manager` | Read stores/templates. See only corrective actions assigned to them and move those to `In Progress` or `Resolved`. Cannot run inspections or mark actions `Verified`. |

Every request is scoped to the caller's organization. Deactivated users and users without an organization are rejected. Submitted inspections are read-only (409).

## Sessions

A login returns a bearer token that expires after `API_TOKEN_TTL_DAYS`. Only a SHA-256 digest is stored, a user can be signed in on several devices at once (the newest 10 sessions are kept), and `DELETE /api/v1/auth/logout` revokes just the calling device's token. Login attempts are limited to 20 per 5 minutes per address and 8 per 15 minutes per account (HTTP 429 with `Retry-After`). Deactivated users are rejected immediately.

## Inspection templates

Templates are data. Editing the categories or questions of a template that inspections already use creates a new version (`version + 1`, a full copy with your edits) and deactivates the old one, so running and past inspections keep the questions, weights and max scores they were started with while new inspections use the new version. Templates nobody has used yet, and metadata-only changes (name, description, active), are edited in place.

## Scoring

Answers use a 1..`max_score` scale; `0` means "not answered". Each category is scored as a percentage of its own possible points (question weights apply inside the category), and the total is the category-weight average of those percentages, so category weights are shares of the total no matter how many questions a category has. N/A and unanswered items are left out. A score above a question's `max_score` is rejected. Submitting fails with 422 while a `required` question is unanswered or a `photo_required` / `comment_required` question lacks its photo or comment (N/A items are exempt).

## Mobile app behavior

- Answers, comments and the Pass toggle are saved as you go (typing is debounced). Anything that cannot be sent is kept in the device's local database, shown with a retry banner, retried automatically every 20 seconds, resent after the app is restarted, and flushed before an inspection is submitted.
- Unfinished inspections can be resumed from the store list or History, and, without a connection, from "Saved on this device" on the Stores tab. Starting a new inspection, attaching photos and submitting need the server.
- A session that is rejected by the server (expired or revoked) returns to the login screen; being offline never signs you out. Logging out revokes the token on the server, clears the previous user's data from the device, and warns first if edits could not be sent. Local data left by a different user is discarded at login.
- Corrective actions are created from a checklist item (title, details, severity, due date) and their status is changed from the Actions tab, limited to what the user's role may set.

## End-to-end test against a live backend

`mobile/test/e2e/live_server_test.dart` drives the app's real client code (`ApiClient`, `AuthState`, `InspectionState`) against a running backend: login and session restore, lists, starting and answering an inspection, photo upload, corrective actions, submission and scoring, the admin dashboard, store manager permissions, logout/revocation, and offline behavior. It is skipped unless a server address is given:

```bash
cd backend && bin/rails db:seed && bin/rails server -p 3002
cd mobile && E2E_BASE_URL=http://127.0.0.1:3002 flutter test test/e2e
```

It creates its own store, so it can be re-run; login is rate limited per account, so restart the server if you run it many times in a row.

## Continuous Integration

GitHub Actions workflows live in the repository root `.github/workflows/` (GitHub ignores nested ones):

- `backend.yml`: Brakeman, bundler-audit, RuboCop, Rails tests, seed load, and a check that `backend/db/schema.rb` is exactly what the migrations produce.
- `mobile.yml`: `flutter analyze` and `flutter test` on the pinned Flutter version.

Whenever you add a migration, commit the regenerated `db/schema.rb` with it.

## Architecture Overview

The backend is a Rails API modular monolith under `/api/v1`. Core models are `Organization`, `User`, `Store`, `InspectionTemplate`, `InspectionCategory`, `InspectionQuestion`, `Inspection`, `InspectionResponse`, `InspectionPhoto`, and `CorrectiveAction`. Authentication uses bearer tokens. Role checks distinguish admin, inspector, and store manager paths. Organization IDs scope operational data.

Inspection templates are data-driven, not hard-coded in application logic. Scoring supports 1-5 answers, N/A exclusion from the denominator, category/question weights, automatic 100-point score calculation, and grades. Photos use Active Storage with separate `original_image` and `annotated_image` attachments plus JSON annotation metadata.

The Flutter app keeps responsibilities separated:

- `lib/api` API client
- `lib/auth` authentication state
- `lib/drafts` local SQLite draft storage
- `lib/photos` camera/photo picker
- `lib/annotations` image annotation state and tools
- `lib/inspections` inspection state
- `lib/screens` workflow UI

## MVP Workflow

The critical workflow is backed by real database/API calls:

```text
Admin login -> Store create -> Template create -> Inspector login -> Store select -> Inspection start -> Checklist scoring -> Photo/annotation -> Comment -> Corrective Action -> Submit -> Dashboard -> Store history -> Action status update
```
