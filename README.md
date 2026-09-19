# Bakery & Restaurant Inspection Platform

Fresh modular monolith MVP for franchise HQ inspection management. The repository was created as a new project with Rails and Flutter generator output; no existing bakery/storepilot project was copied.

## Prerequisites

- Ruby 3.4+
- Bundler
- SQLite
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

Seed data creates Demo Bakery Group, three stores, Bakery Standard Inspection v1, four weighted categories, 20 questions, and demo users.

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

## Scoring

Answers use a 1..`max_score` scale; `0` means "not answered". Each category is scored as a percentage of its own possible points (question weights apply inside the category), and the total is the category-weight average of those percentages, so category weights are shares of the total no matter how many questions a category has. N/A and unanswered items are left out. A score above a question's `max_score` is rejected. Submitting fails with 422 while a `required` question is unanswered or a `photo_required` / `comment_required` question lacks its photo or comment (N/A items are exempt).

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
