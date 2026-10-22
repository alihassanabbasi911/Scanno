import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/documents/application/document_providers.dart';
import '../features/documents/domain/incoming_document.dart';
import '../features/documents/presentation/document_library_page.dart';
import '../features/documents/presentation/document_reader_page.dart';
import '../features/documents/presentation/third_party_notices_page.dart';
import 'scanno_theme.dart';

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const DocumentLibraryPage(),
    ),
    GoRoute(
      path: '/documents/:id',
      builder: (context, state) =>
          DocumentReaderPage(documentId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/incoming',
      builder: (context, state) {
        final incoming = state.extra;
        if (incoming is! IncomingDocument) {
          return const IncomingDocumentErrorPage(
            message: 'Scanno could not open the shared document.',
          );
        }
        return DocumentReaderPage(incoming: incoming);
      },
    ),
    GoRoute(
      path: '/incoming/error',
      builder: (context, state) => IncomingDocumentErrorPage(
        message: state.extra is String
            ? state.extra as String
            : 'Scanno could not open the shared document.',
      ),
    ),
    GoRoute(
      path: '/licenses',
      builder: (context, state) => const ThirdPartyNoticesPage(),
    ),
  ],
);

class ScannoApp extends ConsumerStatefulWidget {
  const ScannoApp({super.key});

  @override
  ConsumerState<ScannoApp> createState() => _ScannoAppState();
}

class _ScannoAppState extends ConsumerState<ScannoApp> {
  StreamSubscription<IncomingDocumentResult>? _incomingSubscription;

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _incomingSubscription = ref
        .read(incomingDocumentServiceProvider)
        .events
        .listen(
          (result) {
            if (!mounted) return;
            final incoming = result.document;
            if (incoming != null) {
              _router.go('/incoming', extra: incoming);
            } else {
              _router.go(
                '/incoming/error',
                extra:
                    result.error ??
                    'Scanno could not open the shared document.',
              );
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (mounted) {
              _router.go(
                '/incoming/error',
                extra: 'Scanno could not process the shared document.',
              );
            }
          },
        );
  }

  @override
  void dispose() {
    _incomingSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Scanno',
      theme: scannoTheme,
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
    );
  }
}
