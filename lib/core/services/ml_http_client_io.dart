import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// HTTP client for the PRISM API on Android/iOS/desktop.
///
/// When [caPemBase64] is set (build flag PRISM_API_CA_PEM_B64, produced by
/// ml/scripts/make_local_tls.sh), ONLY that self-hosted CA is trusted for the
/// API (certificate pinning to the project's own CA). This allows free,
/// self-hosted HTTPS without a paid certificate or domain. Otherwise the
/// platform's normal trust store is used.
http.Client createMlHttpClient(String caPemBase64) {
  if (caPemBase64.isEmpty) return http.Client();
  final context = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificatesBytes(base64Decode(caPemBase64));
  return IOClient(HttpClient(context: context));
}
