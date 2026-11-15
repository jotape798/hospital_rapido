import 'package:flutter_test/flutter_test.dart';
import 'package:ubs_saude/config/api_config.dart';

void main() {
  group('ApiConfig.validateUrl', () {
    test('aceita HTTP local no desenvolvimento e remove barra final', () {
      expect(
        ApiConfig.validateUrl('http://127.0.0.1:8000/'),
        'http://127.0.0.1:8000',
      );
    });

    test('aceita HTTPS remoto em produção', () {
      expect(
        ApiConfig.validateUrl(
          'https://api.ubs.example',
          production: true,
        ),
        'https://api.ubs.example',
      );
    });

    test('rejeita host incompleto, consulta e esquema inseguro em produção',
        () {
      expect(
          () => ApiConfig.validateUrl('localhost:8000'), throwsArgumentError);
      expect(
        () => ApiConfig.validateUrl('https://api.example?q=segredo'),
        throwsArgumentError,
      );
      expect(
        () => ApiConfig.validateUrl(
          'http://api.example',
          production: true,
        ),
        throwsArgumentError,
      );
    });
  });
}
