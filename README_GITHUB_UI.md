# Cashier POS - UI update package

- Updated Material 3 color palette to a clean green/mint style and rounded cards.
- Added the seven supplied screenshots under `assets/ui_reference/` as design references.
- The screenshots are reference images; Flutter does not automatically convert screenshots into interactive UI.
- Existing application screens and business logic are retained. Review and test Firebase, Bluetooth printer, and Android build locally before deployment.

## Build
Run these commands from the directory containing `pubspec.yaml`:

```powershell
flutter pub get
flutter run
```

`pubspec.yaml` already declares `assets/`, so the reference images are included as assets.
