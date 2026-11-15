import 'package:flutter/foundation.dart';

class ApiConfig {
  static const _configuredUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
  static const environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  static final String baseUrl = validateUrl(
    _configuredUrl,
    production: environment.toLowerCase() == 'production',
  );

  @visibleForTesting
  static String validateUrl(String value, {bool production = false}) {
    final normalized = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.hasFragment ||
        uri.hasQuery ||
        uri.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        value,
        'API_BASE_URL',
        'Informe uma URL HTTP ou HTTPS completa, sem consulta ou fragmento.',
      );
    }
    if (production && uri.scheme.toLowerCase() != 'https') {
      throw ArgumentError.value(
        value,
        'API_BASE_URL',
        'A API deve usar HTTPS em produção.',
      );
    }
    return normalized;
  }
}
