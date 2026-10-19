import 'package:http/http.dart' as http;

/// Web builds: the browser's trust store applies; custom CA pinning is not
/// possible from Dart on the web.
http.Client createMlHttpClient(String caPemBase64) => http.Client();
