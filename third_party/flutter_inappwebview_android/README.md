# flutter\_inappwebview\_android

The Android WebView implementation of [`flutter_inappwebview`](https://pub.dev/packages/flutter_inappwebview).

## Usage

This package is [endorsed](https://flutter.dev/docs/development/packages-and-plugins/developing-packages#endorsed-federated-plugin),
which means you can simply use `flutter_inappwebview`
normally. This package will be automatically included in your app when you do,
so you do not need to add it to your `pubspec.yaml`.

However, if you `import` this package to use any of its APIs directly, you
should add it to your `pubspec.yaml` as usual.

## Scanno patch

This is version 1.1.3 with one upstream fix applied from commit
`bc3197fcb059e102988e6c85721c53c1e38cef81`: the Android internal-storage path
handler now calls `super.toMap()` rather than recursively calling itself.
This local copy remains licensed under the included Apache 2.0 license.