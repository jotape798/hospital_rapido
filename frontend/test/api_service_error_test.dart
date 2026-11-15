import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ubs_saude/models/api_models.dart';
import 'package:ubs_saude/services/api_service.dart';

void main() {
  Future<ApiException> registerError(
    int statusCode,
    Object body, {
    bool json = true,
  }) async {
    final client = MockClient((_) async => http.Response(
          json ? jsonEncode(body) : body.toString(),
          statusCode,
          headers: {'content-type': 'application/json'},
        ));
    try {
      await ApiService(client: client).register(const {});
      fail('O cadastro deveria falhar.');
    } on ApiException catch (error) {
      return error;
    }
  }

  test('cadastro diferencia validação de dados', () async {
    final error = await registerError(422, {
      'detail': {'field': 'email', 'message': 'Confira o e-mail informado.'}
    });

    expect(error.statusCode, 422);
    expect(error.field, 'email');
    expect(error.message, 'Confira o e-mail informado.');
  });

  test('cadastro diferencia CPF ou e-mail já cadastrado', () async {
    final error = await registerError(
        409, {'detail': 'CPF ou e-mail já cadastrado. Entre com sua conta.'});

    expect(error.statusCode, 409);
    expect(error.message, contains('já cadastrado'));
  });

  test('cadastro diferencia falha no envio do e-mail', () async {
    final error = await registerError(503,
        {'detail': 'Não foi possível enviar o código de verificação agora.'});

    expect(error.statusCode, 503);
    expect(error.message, contains('enviar o código de verificação'));
  });

  test('cadastro não exibe detalhe de erro interno', () async {
    final error = await registerError(
        500, {'detail': 'detalhe interno que não deve chegar à interface'});

    expect(error.statusCode, 500);
    expect(error.message,
        'A UBS encontrou um erro interno. Tente novamente mais tarde.');
    expect(error.message, isNot(contains('detalhe interno')));
  });

  test('cadastro diferencia ausência de conexão', () async {
    final client = MockClient((request) async {
      throw http.ClientException('falha de transporte', request.url);
    });

    expect(
      () => ApiService(client: client).register(const {}),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'Sem conexão com a UBS. Confira a rede e se o sistema está iniciado.',
        ),
      ),
    );
  });
}
