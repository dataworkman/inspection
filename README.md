# Bakery & Restaurant Inspection Platform

Fresh modular monolith MVP for franchise HQ inspection management. The repository was created as a new project with Rails and Flutter generator output; no existing bakery/storepilot project was copied.

## Prerequisites

- Ruby 3.4+
- Bundler
- SQLite
- Flutter stable channel
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

Tailscale URL on this machine:

```text
http://100.107.174.72:3002
```

## Flutter Run Command

```bash
cd mobile
flutter run --dart-define=API_BASE_URL=http://100.107.174.72:3002
```

With mise:

```bash
mise exec flutter@latest -- flutter run --dart-define=API_BASE_URL=http://100.107.174.72:3002
```

## Demo Login Accounts

- HQ Admin: `admin@bakery-inspection.test` / `password123`
- Inspector: `inspector@bakery-inspection.test` / `password123`
- Store Manager: `manager@bakery-inspection.test` / `password123`

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
