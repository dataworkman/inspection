# PRD Phase Plan

## Phase 1: Rails API Foundation

Rails API app with SQLite, Active Record, Active Storage, authentication, role authorization, organization-scoped models, seed data, and `/api/v1` routing.

Checks:

```bash
cd backend
bundle install
bin/rails db:drop db:create db:migrate db:seed
bin/rails test
bin/rubocop
```

Status: passed. Commit: `4aa26b0`.

## Phase 2: Flutter Foundation

Fresh Flutter app generated with `flutter create`. Login, bottom navigation, store list, template loading, and inspection start are wired to the Rails API.

Checks:

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
```

Status: passed. Commit: `87bccbd`.

## Phase 3: Core Inspection Engine

Template-based checklist, 1-5 scoring, N/A support, automatic backend score calculation, and local draft save.

Status: passed. Commit: `a8d7139`.

## Phase 4: Evidence

Camera/photo picker, original and annotated image upload contract, annotation metadata, and MVP annotation toolbar with pen, arrow, circle, rectangle, text, color-ready state, stroke width, undo, redo, and clear.

Status: passed. Commit: `df67ef8`.

## Phase 5: Corrective Actions

Corrective action API, creation from inspection responses, action list, severity, status, due date, and status update support.

Status: passed. Commit: `7dea7ef`.

## Phase 6: HQ Visibility

Dashboard KPIs, store ranking, attention required signals, open/critical corrective action counts, store inspection history, latest/previous score, score change, and score trend data.

Status: passed. Commit: `81d61c9`.

## Phase 7: QA

End-to-end Rails integration test covers admin store/template creation, inspector inspection flow, scoring, photo upload, corrective action creation, submit, dashboard, store history, and action status update. Flutter source passes dependency resolution, static analysis, and widget tests.

Status: passed.
