import 'package:flutter_inappwebview_android/flutter_inappwebview_android.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('serializes the internal storage path handler without recursion', () {
    final handler = AndroidInternalStoragePathHandler(
      PlatformInternalStoragePathHandlerCreationParams(
        const PlatformPathHandlerCreationParams(path: '/ws/'),
        directory: '/tmp/document-preview',
      ),
    );

    expect(handler.toMap(), containsPair('path', '/ws/'));
    expect(handler.toMap(), containsPair('directory', '/tmp/document-preview'));
    handler.dispose();
  });
}
