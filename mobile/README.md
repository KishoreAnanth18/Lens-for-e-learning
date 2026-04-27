# Lens for E-Learning Mobile App

Flutter mobile application for Lens for E-Learning MVP.

## Getting Started

### Prerequisites
- Flutter SDK 3.0.0 or higher
- Dart SDK 3.0.0 or higher
- Android Studio / Xcode for mobile development

### Installation

1. Install dependencies:
```bash
flutter pub get
```

2. Run the app:
```bash
flutter run
```

For a physical Android device, pass your machine's local network IP as the backend base URL:
```bash
flutter run --dart-define=BASE_URL=http://192.168.1.X:8000
```

Notes:
- `http://10.0.2.2:8000` is only for the Android emulator
- Replace `192.168.1.23` with your current machine IP on the same Wi-Fi/LAN as the device

### Testing

Run unit tests:
```bash
flutter test
```

Run tests with coverage:
```bash
flutter test --coverage
```

### Building

Build for Android:
```bash
flutter build apk
```

Build for iOS:
```bash
flutter build ios
```
