# Golden tests

This directory holds reference PNGs for `matchesGoldenFile` tests.

## Adding a golden test

1. Pick a small, deterministic widget (avoid raw text where possible — font
   rendering differs between platforms).
2. Place the test file next to the widget under `test/`.
3. Reference goldens with a relative path from the test file:

   ```dart
   await expectLater(
     find.byType(MyWidget),
     matchesGoldenFile('../../goldens/my_widget.png'),
   );
   ```

4. Run on Linux (matches CI) to generate baselines:

   ```bash
   flutter test --update-goldens path/to/test.dart
   ```

5. Commit the PNGs in this directory.

## Cross-platform caveat

Flutter's text and icon rasterization is not byte-identical across macOS,
Linux, and Windows. Baselines committed here MUST be generated on the same
platform that CI runs on (Linux, see `.github/workflows/ci.yml`). On
developer machines, skip them with:

```bash
flutter test --exclude-tags=golden
```

and tag golden tests accordingly:

```dart
testWidgets('renders X', (tester) async { ... }, tags: 'golden');
```
