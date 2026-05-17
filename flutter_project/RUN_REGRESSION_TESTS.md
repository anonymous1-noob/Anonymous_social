
# Regression Test Execution Guide

## 1. Install Dependencies

```bash
flutter pub get
```

---

## 2. Run All Unit Tests

```bash
flutter test
```

---

## 3. Run Specific Test File

Example:

```bash
flutter test test/providers/feed_provider_test.dart
```

---

## 4. Run Integration Tests

Start emulator/device first.

```bash
flutter test integration_test/full_app_flow_test.dart
```

---

## 5. Recommended Pre-Release Flow

```bash
flutter clean
flutter pub get
flutter analyze
flutter test
flutter test integration_test
```

---

## 6. CI/CD Example

GitHub Actions Example:

```yaml
name: Flutter Regression Tests

on:
  push:
    branches:
      - main

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: 'stable'

      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
```

---

## 7. Recommended Improvements

- Add mock Supabase services
- Add golden tests
- Add Firebase Crashlytics
- Add performance benchmarks
- Add automated EdgeRank validation
- Add API contract testing

