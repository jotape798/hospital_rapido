import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubs_saude/main.dart';
import 'package:ubs_saude/models/api_models.dart';
import 'package:ubs_saude/services/api_service.dart';

class VerificationApi extends ApiService {
  VerificationApi({this.validationError});

  final String? validationError;
  int registerCalls = 0;
  int resendCalls = 0;
  int requestCalls = 0;
  String? correctedEmail;

  @override
  Future<Map<String, dynamic>> register(Map<String, dynamic> data) async {
    registerCalls++;
    return {
      'email': data['email'].toString().trim().toLowerCase(),
      'verification_token': 'opaque-registration-token-with-enough-entropy',
      'resend_after_seconds': 60,
      'message': 'Cadastro iniciado. Confirme seu e-mail para entrar.',
    };
  }

  @override
  Future<String> validateEmailVerification(String email, String code) async {
    if (validationError != null) {
      throw ApiException(validationError!, statusCode: 400);
    }
    return 'E-mail validado com sucesso. Você já pode entrar.';
  }

  @override
  Future<int> requestEmailVerification(String email) async {
    requestCalls++;
    return 60;
  }

  @override
  Future<int> resendEmailVerification(String email) async {
    resendCalls++;
    return 60;
  }

  @override
  Future<void> correctRegistrationEmail(
      String verificationToken, String newEmail) async {
    correctedEmail = newEmail;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    accessibility.highContrast = false;
    accessibility.fontSizeScale = 1;
  });

  testWidgets('tela explica verificação e oferece campo e reenvio',
      (tester) async {
    await tester.pumpWidget(const UbsApp(
        home: EmailVerificationPage(
            email: 'paciente@example.com', sendOnOpen: false)));
    expect(find.text('Verifique seu e-mail'), findsOneWidget);
    expect(find.textContaining('paciente@example.com'), findsOneWidget);
    expect(find.byKey(const Key('email-verification-code')), findsOneWidget);
    expect(find.text('Validar código'), findsOneWidget);
    expect(find.text('Reenviar código'), findsOneWidget);
    expect(find.text('Voltar e corrigir o e-mail'), findsOneWidget);
    final resend = tester
        .widget<OutlinedButton>(find.byKey(const Key('resend-email-code')));
    expect(resend.onPressed, isNotNull);
  });

  testWidgets('código incompleto mostra erro acessível sem chamar a rede',
      (tester) async {
    await tester.pumpWidget(const UbsApp(
        home: EmailVerificationPage(
            email: 'paciente@example.com', sendOnOpen: false)));
    await tester.enterText(
        find.byKey(const Key('email-verification-code')), '123');
    await tester.tap(find.text('Validar código'));
    await tester.pump();
    expect(find.text('Digite os 6 números do código.'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Código de verificação de seis dígitos'),
        findsOneWidget);
    semantics.dispose();
  });

  testWidgets('campo aceita somente seis dígitos', (tester) async {
    await tester.pumpWidget(const UbsApp(
        home: EmailVerificationPage(
            email: 'paciente@example.com', sendOnOpen: false)));
    await tester.enterText(
        find.byKey(const Key('email-verification-code')), '12a3456789');
    expect(
        tester
            .widget<TextFormField>(
                find.byKey(const Key('email-verification-code')))
            .controller!
            .text,
        '123456');
  });

  testWidgets('código correto conclui a confirmação', (tester) async {
    final api = VerificationApi();
    await tester.pumpWidget(UbsApp(
        home: EmailVerificationPage(
            email: 'paciente@example.com', sendOnOpen: false, api: api)));
    await tester.enterText(
        find.byKey(const Key('email-verification-code')), '123456');
    await tester.tap(find.text('Validar código'));
    await tester.pump();
    expect(find.text('E-mail confirmado'), findsOneWidget);
    expect(find.text('Ir para o login'), findsOneWidget);
  });

  testWidgets('erro do backend é apresentado sem concluir o fluxo',
      (tester) async {
    final api =
        VerificationApi(validationError: 'Código inválido ou expirado.');
    await tester.pumpWidget(UbsApp(
        home: EmailVerificationPage(
            email: 'paciente@example.com', sendOnOpen: false, api: api)));
    await tester.enterText(
        find.byKey(const Key('email-verification-code')), '999999');
    await tester.tap(find.text('Validar código'));
    await tester.pump();
    expect(find.text('Código inválido ou expirado.'), findsOneWidget);
    expect(find.text('Verifique seu e-mail'), findsOneWidget);
  });

  testWidgets('cadastro com código já enviado inicia espera de reenvio',
      (tester) async {
    await tester.pumpWidget(const UbsApp(
        home: EmailVerificationPage(
            email: 'paciente@example.com',
            sendOnOpen: false,
            initialResendSeconds: 60)));
    await tester.pump();
    expect(find.textContaining('Código enviado'), findsOneWidget);
    expect(find.text('Reenviar código em 60s'), findsOneWidget);
    final resend = tester
        .widget<OutlinedButton>(find.byKey(const Key('resend-email-code')));
    expect(resend.onPressed, isNull);
  });

  testWidgets('reenvio fica bloqueado durante a contagem', (tester) async {
    final api = VerificationApi();
    await tester.pumpWidget(UbsApp(
        home: EmailVerificationPage(
            email: 'paciente@example.com',
            sendOnOpen: false,
            initialResendSeconds: 60,
            api: api)));
    await tester.pump();
    final resend = tester
        .widget<OutlinedButton>(find.byKey(const Key('resend-email-code')));
    expect(resend.onPressed, isNull);
    expect(api.resendCalls, 0);
  });

  testWidgets('correção do e-mail usa token opaco e solicita novo código',
      (tester) async {
    final api = VerificationApi();
    await tester.pumpWidget(UbsApp(
        home: EmailVerificationPage(
            email: 'errado@example.com',
            sendOnOpen: false,
            verificationToken: 'opaque-registration-token-with-enough-entropy',
            api: api)));
    await tester.tap(find.text('Voltar e corrigir o e-mail'));
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextFormField, 'Novo e-mail');
    await tester.enterText(field, 'certo@example.com');
    await tester.tap(find.text('Salvar e reenviar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(api.correctedEmail, 'certo@example.com');
    expect(api.requestCalls, 1);
    expect(
        find.text(
            'Enviamos um código de 6 dígitos para certo@example.com. Ele vale por 10 minutos.'),
        findsOneWidget);
  });

  testWidgets('cadastro avança para confirmação sem login automático',
      (tester) async {
    final api = VerificationApi();
    await tester.pumpWidget(UbsApp(home: RegisterPage(api: api)));
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome completo'), 'Maria da Silva');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'CPF'), '52998224725');
    await tester.tap(find.widgetWithText(TextFormField, 'Data de nascimento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('registration-next')));
    await tester.tap(find.byKey(const Key('registration-next')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'E-mail'), 'Maria@Example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Telefone / celular'),
        '11987654321');
    await tester.ensureVisible(find.byKey(const Key('registration-next')));
    await tester.tap(find.byKey(const Key('registration-next')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Senha'), 'Paciente@123');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirmar senha'), 'Paciente@123');
    await tester.ensureVisible(find.text('Cadastrar'));
    await tester.tap(find.text('Cadastrar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(api.registerCalls, 1);
    expect(find.byType(EmailVerificationPage), findsOneWidget);
    expect(find.text('Verifique seu e-mail'), findsOneWidget);
    expect(find.textContaining('maria@example.com'), findsOneWidget);
    expect(find.byKey(const Key('email-verification-code')), findsOneWidget);
  });

  testWidgets('alto contraste e fonte ampliada não quebram a tela',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    accessibility.highContrast = true;
    accessibility.fontSizeScale = 1.3;
    await tester.pumpWidget(const UbsApp(
        home: EmailVerificationPage(
            email: 'paciente@example.com', sendOnOpen: false)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        Colors.black);
  });

  testWidgets('tela não apresenta overflow nas larguras exigidas',
      (tester) async {
    for (final width in [390.0, 768.0, 1366.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(UbsApp(
          home: EmailVerificationPage(
              key: ValueKey(width),
              email: 'paciente@example.com',
              sendOnOpen: false)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'largura $width');
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}
