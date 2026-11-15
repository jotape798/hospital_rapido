import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubs_saude/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    accessibility.highContrast = false;
    accessibility.fontSizeScale = 1;
  });
  test('valida CPF, nome, telefone e senha', () {
    expect(isValidCpf('529.982.247-25'), isTrue);
    expect(isValidCpf('11111111111'), isFalse);
    expect(requiredName('Maria-Silva Santos'), isNull);
    expect(requiredName('Maria 123'), isNotNull);
    expect(phoneRule('123'), isNotNull);
    expect(strongPassword('Paciente@123'), isTrue);
  });
  testWidgets('login mantém marca e aceita apenas CPF', (tester) async {
    await tester.pumpWidget(const UbsApp());
    expect(find.text('Acesse sua conta'), findsOneWidget);
    expect(find.text('UBS'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('CPF'), findsOneWidget);
    expect(find.textContaining('CNS'), findsNothing);
    await tester.enterText(find.byType(TextFormField).first, '52998224725');
    expect(find.text('529.982.247-25'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '11111111111');
    await tester.ensureVisible(find.text('Entrar'));
    await tester.tap(find.text('Entrar'));
    await tester.pump();
    expect(find.text('CPF inválido. Confira os 11 números.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('recuperação usa e-mail cadastrado', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RecoveryPage()));
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('E-mail cadastrado'), findsOneWidget);
    expect(find.textContaining('CPF'), findsNothing);
  });
  testWidgets('cadastro não apresenta CNS', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RegisterPage()));
    expect(find.textContaining('CNS'), findsNothing);
    expect(find.byType(WaveBackground), findsOneWidget);
  });
  testWidgets('ondas ficam restritas às telas de acesso', (tester) async {
    await tester.pumpWidget(const UbsApp(home: RecoveryPage()));
    expect(find.byType(WaveBackground), findsOneWidget);

    await tester.pumpWidget(const UbsApp(
        home: EmailVerificationPage(
            email: 'usuario.ficticio@example.invalid', sendOnOpen: false)));
    expect(find.byType(WaveBackground), findsNothing);

    await tester.pumpWidget(const UbsApp(
        home: ResponsiveAppShell(
            title: 'Área interna',
            wideNavigationMode: WideNavigationMode.contentOnly,
            body: SizedBox())));
    expect(find.byType(WaveBackground), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('fonte global, reset e contraste persistem na navegação',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const UbsApp());
    await tester.tap(find.text('Preferências de acessibilidade'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A+'));
    await tester.pumpAndSettle();
    expect(accessibility.fontSizeScale, 1.15);
    await tester.tap(find.text('A-'));
    await tester.pumpAndSettle();
    expect(accessibility.fontSizeScale, 1);
    await tester.tap(find.text('A-'));
    await tester.pumpAndSettle();
    expect(accessibility.fontSizeScale, .85);
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    expect(accessibility.fontSizeScale, 1);
    accessibility.setContrast(true);
    accessibility.setFontScale(1.3);
    await tester.pumpAndSettle();
    expect(find.byType(WaveBackground), findsOneWidget);
    expect(
        Theme.of(tester.element(find.byType(Scaffold))).scaffoldBackgroundColor,
        Colors.black);
    await tester.tap(find.text('Preferências de acessibilidade'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cadastrar-se'));
    await tester.tap(find.text('Cadastrar-se'));
    await tester.pumpAndSettle();
    expect(find.text('Criar conta'), findsOneWidget);
    expect(
        MediaQuery.textScalerOf(tester.element(find.text('Criar conta')))
            .scale(10),
        13);
    expect(find.byType(WaveBackground), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('login cabe em celular com fonte máxima', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    accessibility.fontSizeScale = 1.3;
    await tester.pumpWidget(const UbsApp());
    await tester.pumpAndSettle();
  });
}
