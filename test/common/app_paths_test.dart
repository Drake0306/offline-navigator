import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/common/app_paths.dart';

void main() {
  test('needsRefresh true when no stamp, false after writeStamp', () async {
    final dir = await Directory.systemTemp.createTemp('appdir');
    final paths = AppPaths(root: dir.path);

    expect(await paths.needsRefresh('v1'), isTrue);
    await paths.writeStamp('v1');
    expect(await paths.needsRefresh('v1'), isFalse);
    // Version bump forces refresh.
    expect(await paths.needsRefresh('v2'), isTrue);
  });
}
