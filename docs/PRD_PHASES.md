# PRD Phase Plan

## Phase 1: Rails API Foundation

Rails API app with SQLite, Active Record, Active Storage, token authentication, role authorization, seed data, and `/api/v1` routing.

Checks:

```bash
cd backend
bundle install
bin/rails db:prepare
bin/rails db:seed
bin/rails test
bin/rubocop
```

Status: passed.

## Phase 2: Real Inspection Workflow API

Real database/API workflow: Login -> Store -> Start Inspection -> Checklist -> Photo/Annotation -> Comment -> Score -> Submit -> History -> Dashboard.

Check:

```bash
cd backend
bin/rails test test/integration/api_v1_workflow_test.rb
```

Status: passed.

## Phase 3: Flutter Mobile Workflow

Fresh Flutter app generated with `flutter create`; no existing project copied. Layers are split into API client, auth state, local draft storage, photo picker, annotation state, and inspection state.

Checks:

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
```

Status: passed.
