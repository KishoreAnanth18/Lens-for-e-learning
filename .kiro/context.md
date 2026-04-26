# Lens for E-Learning Context

Last updated: 2026-04-26

## Purpose

This file is a working reference for the current state of the repo before starting additional implementation work. It summarizes:

- what is already implemented
- what is still pending
- where the spec and code do not currently line up
- what areas are generated or non-source and should not drive implementation decisions

## Repo Overview

- `backend/`: FastAPI service for auth, scan upload, OCR, NLP, and search pipeline pieces
- `mobile/`: Flutter app with auth and camera foundations implemented
- `infrastructure/`: Terraform for AWS resources
- `scripts/`: setup and verification helpers, including LocalStack initialization
- `.kiro/specs/lens-elearning-mvp/`: requirements, design, and task tracking docs

## Documentation Reviewed

- `README.md`
- `LOCAL-DEVELOPMENT.md`
- `backend/README.md`
- `mobile/README.md`
- `infrastructure/README.md`
- `.kiro/specs/lens-elearning-mvp/requirements.md`
- `.kiro/specs/lens-elearning-mvp/design.md`
- `.kiro/specs/lens-elearning-mvp/tasks.md`

## Source vs Generated Content

These directories/files exist but should mostly be treated as generated/runtime artifacts, not primary source:

- `backend/venv/`
- `backend/htmlcov/`
- `backend/.pytest_cache/`
- `backend/.coverage`
- `mobile/build/`
- `mobile/.dart_tool/`

There are also local env/runtime files present:

- `backend/.env`
- `mobile/pubspec.lock`

## Current Implementation Snapshot

### Backend: implemented

- FastAPI app wiring exists in `backend/app/main.py`
- Auth router, models, dependency wiring, and service logic exist
- Mock auth flow is implemented in memory
- Cognito-backed auth flow is partially implemented
- Scan upload endpoint exists in `backend/app/api/scans/router.py`
- Scan status endpoint exists at `GET /api/v1/scans/{scan_id}`
- Image validation, upload to S3, thumbnail generation, duplicate detection, and scan metadata creation exist
- Scan creation now starts processing after upload, with local in-process OCR -> NLP -> Search orchestration for development
- OCR, NLP, search, and Lambda handler modules exist under `backend/app/api/scans/`
- Health endpoints exist, including AWS/LocalStack connectivity check
- Infrastructure docs and Terraform for DynamoDB, S3, Cognito, and IAM are present

### Backend: tested

- Backend test suite includes auth, health, image processor, NLP, OCR, search, and scan service tests
- The completed tasks in `tasks.md` for backend features 1-7 and cost optimization task 9 are broadly reflected in the code layout and tests
- Optional property tests called out in the spec are mostly not implemented yet

### Mobile: implemented

- App bootstrap and auth gate exist in `mobile/lib/main.dart`
- `AuthProvider` exists with init/register/login/logout/verify flows
- `TokenManager` exists with secure storage and client-side expiry tracking
- `AuthServiceImpl` exists and calls backend auth endpoints
- Login, register, and email verification screens exist
- Camera capture flow exists with live preview, gallery pick, local save, and compression
- Scan models, provider, and `IScanService` implementation now exist for upload/polling/progress tracking
- Scan processing screen exists and shows upload/OCR/summarization/keywords/search progress states
- Results screen now exists with Videos, Articles, and Websites tabs
- Results UI now shows the original image, summary, keywords, share action, resource opening, and local bookmark toggles
- Home screen can launch camera, start a scan session, reopen active progress, and let processing continue when the progress screen is dismissed

### Mobile: tested

- Only a minimal widget smoke test exists in `mobile/test/widget_test.dart`
- `flutter analyze lib test/widget_test.dart` is currently clean after the results-module changes
- There is not yet meaningful test coverage for auth flows, camera flows, scan orchestration, history, results, bookmarks, or offline behavior

## Task Status Summary

### Marked complete in `.kiro/specs/lens-elearning-mvp/tasks.md`

- 1. Infrastructure and development environment
- 2.1 Backend auth API
- 3.1 Backend upload handler
- 4.1 OCR processor
- 5.1 NLP processor
- 6. Backend checkpoint
- 7.1 Search orchestrator
- 9.1 Cost optimization basics
- 10. Backend checkpoint
- 11.1 Mobile auth module
- 12.1 Mobile camera/capture module
- 13.1 Mobile scan processing orchestrator and progress tracking
- 14.1 Mobile results display UI

### Still pending from task plan

- Most optional property-based tests across backend and mobile
- Backend task 8: structured error handling, rate limiting, monitoring/metrics
- Task 15: bookmark management across backend and mobile
- Task 17: scan history and offline access
- Task 18: network error handling and retry logic
- Task 19: performance optimization
- Tasks 21-23: integration testing, deployment hardening, production readiness

## Major Gaps Between Spec and Current Code

### Mobile feature coverage gap

The mobile app now supports the scan processing flow after capture, but still lacks the post-processing product surface:

- no history screen
- no bookmark persistence or bookmark backend sync
- no offline cache/database implementation
- no network retry/offline queue implementation

### Backend API surface gap

The design/tasks mention endpoints for:

- `GET /api/v1/scans`
- `DELETE /api/v1/scans/{scan_id}`
- bookmark endpoints

These are not yet visible in the current backend routing.

### Error-handling gap

The design defines structured error responses with error codes, timestamps, details, request IDs, and 429 handling. Current code only has a minimal `ErrorResponse` model in scan models and does not appear to provide a consistent error envelope across the API.

### Monitoring/rate limiting gap

CloudWatch-oriented logging/metrics/rate limiting are described in the spec but not yet clearly implemented in application code.

## Known Issues and Spec Drift

### 1. Mobile email verification request does not match backend contract

Backend `VerifyEmailRequest` requires both:

- `email`
- `code`

But `mobile/lib/services/auth_service_impl.dart` sends only:

- `code`

The verification screen has the email available, but it is not passed into the request.

Impact:

- verify-email is likely broken against the backend contract

### 2. Mobile auth service expects fields backend does not currently return

`AuthServiceImpl` reads fields such as:

- `user_id`
- `email`

from register/login responses. Backend `AuthResponse` currently returns token fields and expiry only.

Impact:

- provider state may be partially empty after login/register
- the mobile app and backend response models are out of sync

### 3. OAuth is declared but not implemented in mobile

`loginWithGoogle()` and `loginWithFacebook()` in `mobile/lib/services/auth_service_impl.dart` throw `UnimplementedError`.

Impact:

- task list marks social login UI/module work complete, but the actual auth implementation is not complete

### 4. Bookmarking is UI-only for now

Task 14.1 adds bookmark buttons in the results UI, but task 15 is still pending, so bookmarks are currently local to the in-memory session and are not persisted or synced.

Impact:

- the button/interaction exists
- bookmarks will disappear when app state is lost

### 5. Generated/build artifacts are committed locally

Repo contains build/runtime artifacts such as:

- `mobile/build/`
- `mobile/.dart_tool/`
- `backend/venv/`
- coverage artifacts

Impact:

- slower repo analysis
- noise during search/review
- higher chance of accidental edits in generated content

### 6. Test status in `tasks.md` is still optimistic compared with mobile reality

`tasks.md` now correctly marks scan orchestration as implemented, but there is still almost no corresponding mobile automated coverage beyond a smoke test.

### 7. Flutter test runner has a local generated-build cleanup issue

After adding results dependencies, `flutter test` hit a Flutter-tool cleanup failure for `build/unit_test_assets` even after that path no longer existed.

Impact:

- static analysis is clean
- the current environment may need a manual `mobile/build` cleanup before broader Flutter test runs

## Practical Working Notes

- Prefer using spec docs plus real source code together; `tasks.md` alone overstates some areas
- Treat backend auth and scan upload foundations as present but not fully aligned with the mobile client
- Treat the mobile app as a connected vertical slice with results UI, but not a full MVP yet
- When implementing next features, ignore generated directories unless debugging build/runtime issues

## Recommended Next Implementation Order

When coding starts, the most logical order appears to be:

1. Align backend/mobile auth contracts
2. Add bookmark persistence and bookmark APIs
3. Build history/offline access
4. Add offline/cache/retry behavior
5. Backfill structured errors, tests, and monitoring

## Important Assumptions

- This summary is based on repo contents as of 2026-04-26
- Analysis focused on source and documentation; generated artifacts were inspected only enough to classify them as non-source
- No feature code was intentionally modified while creating this file
