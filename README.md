# Store Inspection System

Fresh modular monolith MVP for store inspections. This repository was created from new Rails and Flutter generator output, without copying an existing project.

## Prerequisites

- Ruby 3.4+
- Bundler
- SQLite
- Flutter stable channel
- Xcode or Android Studio for mobile simulators

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

If using mise:

```bash
mise exec flutter@latest -- flutter pub get
```

## Database Setup

SQLite is used for development and test. Active Storage uses local disk storage.

```bash
cd backend
bin/rails db:drop db:create db:migrate db:seed
```

Seed command:

```bash
bin/rails db:seed
```

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

- Admin: `admin@storepilot.test` / `password123`
- Inspector: `inspector@storepilot.test` / `password123`

## Architecture Overview

The backend is a Rails API modular monolith. Core models are `User`, `Store`, `ChecklistTemplate`, `ChecklistItem`, `Inspection`, `InspectionResponse`, and `InspectionPhoto`. Authentication uses bearer tokens. Admin-only dashboard access is enforced in the API controller layer. Images are stored through Active Storage, so local disk can later be swapped for S3. SQLite can later be swapped for PostgreSQL through Rails database configuration.

The Flutter app keeps core responsibilities separated:

- `lib/api` API client
- `lib/auth` authentication state
- `lib/drafts` local SQLite draft storage
- `lib/photos` camera/photo picker
- `lib/annotations` image annotation state
- `lib/inspections` inspection state
- `lib/screens` workflow UI

## MVP Workflow

The critical workflow is backed by real database/API calls:

```text
Login -> Store -> Start Inspection -> Checklist -> Photo/Annotation -> Comment -> Score -> Submit -> History -> Dashboard
```
