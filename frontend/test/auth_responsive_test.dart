import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubs_saude/main.dart';
import 'package:ubs_saude/models/api_models.dart';
import 'package:ubs_saude/services/api_service.dart';

class PendingLoginApi extends ApiService {
  int loginCalls = 0;
  final completion = Completer<Session>();

  @override
  Future<Session> login(String document, String password) {
    loginCalls++;
    return completion.future;
  }
}

class RegistrationApi extends ApiService {
  int registerCalls = 0;
  int loginCalls = 0;

  @override
  Future<Map<String, dynamic>> register(Map<String, dynamic> data) async {
    registerCalls++;
    return {
      'message': 'Cadastro iniciado. Confirme seu e-mail para entrar.',
      'email': data['email'],
      'verification_token': 'opaque-registration-token-with-enough-entropy',
      'resend_after_seconds': 60,
    };
  }

  @override
  Future<Session> login(String document, String password) async {
    loginCalls++;
    throw StateError('O cadastro não pode realizar login automático.');
  }
}

Future<void> setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    accessibility.highContrast = false;
    accessibility.fontSizeScale = 1;
    ApiService.session = null;
  });

  tearDown(() {
    accessibility.highContrast = false;
    accessibility.fontSizeScale = 1;
  });

  testWidgets('login_matches_compact_and_wide_hierarchy', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [
      const Size(390, 800),
      const Size(768, 900),
      const Size(1280, 900),
    ]) {
      await setViewport(tester, size);
      await tester.pumpWidget(const UbsApp(home: LoginPage()));
      expect(find.bySemanticsLabel('UBS Rápida, saúde perto de você'),
          findsOneWidget);
      expect(find.text('Acesse sua conta'), findsOneWidget);
      expect(find.byType(AppActionButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('login fica no topo responsivo e mantém rolagem de proteção',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await setViewport(tester, const Size(1366, 768));
    await tester.pumpWidget(const UbsApp(home: LoginPage()));
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byKey(const Key('login-card'))).top, 40);
    expect(find.byKey(const Key('top-aligned-auth-scroll')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login não mostra força e mantém Entrar estável ao digitar',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await setViewport(tester, const Size(768, 900));
    await tester.pumpWidget(const UbsApp(home: LoginPage()));

    final submit = find.byType(AppActionButton);
    final passwordField = find.byType(TextFormField).at(1);
    expect(find.byType(PasswordStrengthIndicator), findsNothing);
    expect(find.textContaining('Força da senha'), findsNothing);
    final positionBefore = tester.getTopLeft(submit);

    await tester.enterText(passwordField, 'Paciente@123');
    await tester.pump();
    expect(tester.getTopLeft(submit), positionBefore);

    await tester.tap(find.byTooltip('Mostrar senha'));
    await tester.pump();
    expect(find.byTooltip('Ocultar senha'), findsOneWidget);
    expect(find.byType(PasswordStrengthIndicator), findsNothing);
    expect(tester.getTopLeft(submit), positionBefore);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cadastro preserva indicador de força da senha', (tester) async {
    await tester.pumpWidget(const UbsApp(home: RegisterPage()));
    expect(find.text('Etapa 1 de 3 · Dados pessoais'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome completo'), 'Maria da Silva');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'CPF'), '52998224725');
    final birthField = find.widgetWithText(TextFormField, 'Data de nascimento');
    await tester.ensureVisible(birthField);
    await tester.pumpAndSettle();
    await tester.tap(birthField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continuar'));
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.text('Etapa 2 de 3 · Contato'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'E-mail'), 'maria@example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Telefone / celular'),
        '11987654321');
    await tester.ensureVisible(find.text('Continuar'));
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.text('Etapa 3 de 3 · Acesso à conta'), findsOneWidget);
    expect(find.byType(PasswordRules), findsOneWidget);

    await tester.tap(find.byKey(const Key('registration-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('registration-back')));
    await tester.pumpAndSettle();
    expect(find.text('Maria da Silva'), findsOneWidget);
    expect(find.text('529.982.247-25'), findsOneWidget);
  });

  testWidgets('cadastro confirma antes de descartar dados preenchidos',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await setViewport(tester, const Size(800, 800));
    await tester.pumpWidget(const UbsApp(home: RegisterPage()));
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome completo'), 'Maria da Silva');

    final loginLink = find.text('Já tem uma conta? Fazer login');
    await tester.ensureVisible(loginLink);
    await tester.pumpAndSettle();
    await tester.tap(loginLink);
    await tester.pumpAndSettle();
    expect(find.text('Sair do cadastro?'), findsOneWidget);
    expect(find.text('Continuar cadastro'), findsOneWidget);
    expect(find.text('Descartar dados'), findsOneWidget);

    await tester.tap(find.text('Continuar cadastro'));
    await tester.pumpAndSettle();
    expect(find.text('Criar conta'), findsOneWidget);
    expect(find.text('Maria da Silva'), findsOneWidget);
  });

  testWidgets('registration_wraps_at_390_with_max_text_scale', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await setViewport(tester, const Size(390, 800));
    accessibility.fontSizeScale = 1.30;
    await tester.pumpWidget(const UbsApp(home: RegisterPage()));
    await tester.pump();

    expect(find.text('Criar conta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cadastro completo cabe em 1920x1080 sem rolagem residual',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await setViewport(tester, const Size(1920, 1080));
    await tester.pumpWidget(const UbsApp(home: RegisterPage()));
    await tester.pumpAndSettle();

    final scrollable = find
        .descendant(
            of: find.byKey(const Key('top-aligned-auth-scroll')),
            matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    final card = tester.getRect(find.byKey(const Key('registration-card')));
    final login = tester.getRect(find.text('Já tem uma conta? Fazer login'));

    expect(position.maxScrollExtent, 0);
    expect(card.top, 72);
    expect(login.bottom, lessThan(1080));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cadastro sobe etapa curta e preserva margem antes das ondas',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await setViewport(tester, const Size(1366, 768));
    await tester.pumpWidget(const UbsApp(home: RegisterPage()));
    await tester.pumpAndSettle();

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

    final card = tester.getRect(find.byKey(const Key('registration-card')));
    expect(find.text('Etapa 2 de 3 · Contato'), findsOneWidget);
    expect(card.top, 40);
    expect(card.bottom, lessThan(768 * .88 - 16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cadastro mantém rolagem em altura baixa e em 320/360 A+',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await setViewport(tester, const Size(800, 600));
    await tester.pumpWidget(const UbsApp(home: RegisterPage()));
    await tester.pumpAndSettle();
    var scrollable = find
        .descendant(
            of: find.byKey(const Key('top-aligned-auth-scroll')),
            matching: find.byType(Scrollable))
        .first;
    expect(tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
        greaterThan(0));
    await tester.ensureVisible(find.text('Já tem uma conta? Fazer login'));
    expect(find.text('Já tem uma conta? Fazer login'), findsOneWidget);
    expect(tester.takeException(), isNull);

    accessibility.setFontScale(1.3);
    for (final width in [320.0, 360.0]) {
      await setViewport(tester, Size(width, 800));
      await tester.pumpWidget(
          UbsApp(home: RegisterPage(key: ValueKey('register-$width'))));
      await tester.pumpAndSettle();
      scrollable = find
          .descendant(
              of: find.byKey(const Key('top-aligned-auth-scroll')),
              matching: find.byType(Scrollable))
          .first;
      expect(scrollable, findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('registration-next')));
      expect(find.byKey(const Key('registration-next')), findsOneWidget);
      final exception = tester.takeException();
      expect(exception, isNull,
          reason: exception is FlutterError
              ? 'largura $width: ${exception.toStringDeep()}'
              : 'largura $width');
    }
  });

  testWidgets('cadastro calcula idoso e marca condições como pendentes',
      (tester) async {
    await tester.pumpWidget(const UbsApp(home: RegisterPage()));
    expect(
        find.text(
            'A prioridade para pessoa idosa é calculada automaticamente pela data de nascimento.'),
        findsOneWidget);
    expect(
        find.text(
            'Você pode informar mais de uma condição. A prioridade somente será aplicada após confirmação presencial pela Recepção.'),
        findsOneWidget);
    expect(find.text('Idoso 60+'), findsNothing);
    final pcd = find.widgetWithText(CheckboxListTile, 'PCD');
    await tester.ensureVisible(pcd);
    await tester.tap(pcd);
    await tester.pump();
    expect(find.text('Aguardando confirmação presencial'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cadastro concluído exige verificação antes do login',
      (tester) async {
    final api = RegistrationApi();
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
        find.widgetWithText(TextFormField, 'E-mail'), 'maria@example.com');
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
    await tester.pumpAndSettle();

    expect(api.registerCalls, 1);
    expect(api.loginCalls, 0);
    expect(find.text('Verifique seu e-mail'), findsOneWidget);
    expect(find.textContaining('Reenviar código em'), findsOneWidget);
    expect(find.byKey(const Key('email-verification-code')), findsOneWidget);
  });

  testWidgets('recovery_keeps_primary_action_visible', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await setViewport(tester, const Size(390, 800));
    await tester.pumpWidget(const UbsApp(home: RecoveryPage()));

    final action = find.byType(AppActionButton);
    expect(action, findsOneWidget);
    expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('email_verification_keeps_code_semantics', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await setViewport(tester, const Size(390, 800));
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const UbsApp(
      home: EmailVerificationPage(
        email: 'maria@example.com',
        sendOnOpen: false,
      ),
    ));

    expect(find.bySemanticsLabel('Código de verificação de seis dígitos'),
        findsOneWidget);
    expect(find.byType(AppActionButton), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('login_disables_only_submit_while_request_is_pending',
      (tester) async {
    final api = PendingLoginApi();
    await tester.pumpWidget(UbsApp(home: LoginPage(api: api)));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '52998224725');
    await tester.enterText(fields.at(1), 'Paciente@123');
    final submit = find.text('Entrar →');
    await tester.tap(submit);
    await tester.tap(submit);
    await tester.pump();

    expect(api.loginCalls, 1);
    expect(fields, findsNWidgets(2));
    expect(find.text('Aguarde…'), findsOneWidget);

    api.completion.completeError(const ApiException('Falha controlada.'));
    await tester.pump();
  });
}
