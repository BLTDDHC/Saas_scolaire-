import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web startup clears stale Flutter caches before loading the app',
      () async {
    final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
    final executable = bootstrap
        .replaceAll('{{flutter_js}}', '')
        .replaceAll(
          '{{flutter_build_config}}',
          'globalThis._flutter = {'
              'loader: {load: async () => globalThis.events.push("load")}'
              '};',
        );
    const harness = r'''
globalThis.events = [];
globalThis.window = globalThis;
Object.defineProperty(globalThis, 'navigator', {value: {
  serviceWorker: {
    getRegistrations: async () => [
      {unregister: async () => globalThis.events.push('unregister-a')},
      {unregister: async () => globalThis.events.push('unregister-b')},
    ],
  },
}, configurable: true});
globalThis.caches = {
  keys: async () => ['flutter-app-cache', 'legacy-cache'],
  delete: async (key) => globalThis.events.push(`delete-${key}`),
};
const source = Buffer.from(process.env.BOOTSTRAP_SOURCE, 'base64')
  .toString('utf8');
eval(source);
await globalThis.godfirstStartup;
process.stdout.write(JSON.stringify(globalThis.events));
''';
    final result = await Process.run(
      'node',
      const ['--input-type=module', '--eval', harness],
      environment: {
        'BOOTSTRAP_SOURCE': base64Encode(utf8.encode(executable)),
      },
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(
      jsonDecode(result.stdout.toString()),
      [
        'unregister-a',
        'unregister-b',
        'delete-flutter-app-cache',
        'delete-legacy-cache',
        'load',
      ],
    );
  });
}
