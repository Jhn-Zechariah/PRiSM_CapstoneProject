import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:prism_app/core/services/ml_http_client_io.dart';

/// Live check of CA pinning against a self-hosted HTTPS API. Runs only when
/// PRISM_TLS_TEST_URL (e.g. https://127.0.0.1:8766) and PRISM_TLS_TEST_CA (path
/// to prism-ca.pem from ml/scripts/make_local_tls.sh) are set; otherwise skipped.
void main() {
  final url = Platform.environment['PRISM_TLS_TEST_URL'];
  final caPath = Platform.environment['PRISM_TLS_TEST_CA'];
  final live = url != null && caPath != null;

  test('no CA configured gives a default client', () {
    expect(createMlHttpClient(''), isA<http.Client>());
  });

  test('invalid CA data is rejected', () {
    expect(() => createMlHttpClient(base64Encode(utf8.encode('not a cert'))), throwsA(anything));
  });

  test('pinned CA: trusted server succeeds', () async {
    final client = createMlHttpClient(base64Encode(File(caPath!).readAsBytesSync()));
    final r = await client.get(Uri.parse('$url/health'));
    client.close();
    expect(r.statusCode, 200);
    expect(r.body, contains('ok'));
  }, skip: live ? false : 'set PRISM_TLS_TEST_URL and PRISM_TLS_TEST_CA');

  test('without the CA the self-signed server is rejected', () async {
    final client = http.Client();
    await expectLater(client.get(Uri.parse('$url/health')), throwsA(isA<HandshakeException>()));
    client.close();
  }, skip: live ? false : 'set PRISM_TLS_TEST_URL and PRISM_TLS_TEST_CA');
}
