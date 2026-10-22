import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ThirdPartyNoticesPage extends StatelessWidget {
  const ThirdPartyNoticesPage({super.key});

  static const _licenseAssets = [
    'LICENSE-caladea',
    'LICENSE-dejavu',
    'LICENSE-liberation',
    'LICENSE-pptxjs',
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Open-source notices')),
    body: FutureBuilder<List<(String, String)>>(
      future: _loadNotices(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'The open-source notices could not be loaded. Please try again.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (final item in snapshot.data!) ...[
              Text(item.$1, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              SelectableText(item.$2),
              const SizedBox(height: 24),
            ],
          ],
        );
      },
    ),
  );

  Future<List<(String, String)>> _loadNotices() async {
    final notices = await rootBundle.loadString(
      'assets/THIRD_PARTY_NOTICES.md',
    );
    final licenses = await Future.wait(
      _licenseAssets.map(
        (name) => rootBundle.loadString(
          'packages/offline_document_viewer/assets/licenses/$name',
        ),
      ),
    );
    return [
      ('Third-party notices', notices),
      for (var index = 0; index < _licenseAssets.length; index++)
        (_licenseAssets[index], licenses[index]),
    ];
  }
}
