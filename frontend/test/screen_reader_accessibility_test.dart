import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubs_saude/main.dart';
import 'package:ubs_saude/services/api_service.dart';

void main() {
  bool primaryFocusIsInside(WidgetTester tester, Key key) {
    var found = false;
    FocusManager.instance.primaryFocus?.context
        ?.visitAncestorElements((element) {
      if (element.widget.key == key) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    accessibility.highContrast = false;
    accessibility.fontSizeScale = 1;
    accessibility.screenReaderSupport = false;
    ApiService.session = null;
  });

  testWidgets('opção de leitor de tela alterna, anuncia e persiste',
      (tester) async {
    final announcements = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
        SystemChannels.accessibility, (message) async {
      if (message is Map && message['type'] == 'announce') {
        final data = message['data'];
        if (data is Map && data['message'] is String) {
          announcements.add(data['message'] as String);
        }
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility, null));

    await tester.pumpWidget(const UbsApp());
    final semantics = tester.ensureSemantics();
    await tester.tap(find.text('Preferências de acessibilidade'));
    await tester.pumpAndSettle();

    expect(find.text('Otimizar para leitor de tela'), findsOneWidget);
    expect(
        find.bySemanticsLabel('Otimizar para leitor de tela'), findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics &&
            widget.properties.label == 'Otimizar para leitor de tela' &&
            widget.properties.hint ==
                'Melhora a leitura do sistema por Narrador, TalkBack e leitores de tela compatíveis'),
        findsOneWidget);

    tester.semantics
        .tap(find.semantics.byLabel('Otimizar para leitor de tela'));
    await tester.pumpAndSettle();
    expect(accessibility.screenReaderSupport, isTrue);
    expect(announcements, contains('Otimização para leitor de tela ativada'));
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('ubs_screen_reader'), isTrue);

    tester.semantics
        .tap(find.semantics.byLabel('Otimizar para leitor de tela'));
    await tester.pumpAndSettle();
    expect(accessibility.screenReaderSupport, isFalse);
    expect(
        announcements, contains('Otimização para leitor de tela desativada'));

    accessibility.setReaderSupport(true);
    await tester.pumpAndSettle();

    accessibility.screenReaderSupport = false;
    await accessibility.load();
    expect(accessibility.screenReaderSupport, isTrue);
    semantics.dispose();
  });

  testWidgets('menu é operável por Tab, Shift Tab e Enter sem prender foco',
      (tester) async {
    await tester.pumpWidget(const UbsApp());

    var reachedMenu = false;
    for (var attempt = 0; attempt < 20 && !reachedMenu; attempt++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      reachedMenu =
          primaryFocusIsInside(tester, const Key('accessibility-menu-button'));
    }
    expect(reachedMenu, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Fechar preferências de acessibilidade'),
        findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics &&
            widget.key == const Key('accessibility-menu-semantics') &&
            widget.properties.expanded == true),
        findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
        primaryFocusIsInside(tester, const Key('accessibility-font-decrease')),
        isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(primaryFocusIsInside(tester, const Key('accessibility-menu-button')),
        isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Abrir preferências de acessibilidade'),
        findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.hasPrimaryFocus, isTrue,
        reason: 'O botão que fechou o painel deve continuar com o foco.');
  });

  testWidgets('login e cadastro mantêm rótulos essenciais com modo desligado',
      (tester) async {
    await tester.pumpWidget(const UbsApp());
    final semantics = tester.ensureSemantics();

    expect(find.bySemanticsLabel('CPF, obrigatório'), findsOneWidget);
    expect(find.bySemanticsLabel('Senha, obrigatória'), findsOneWidget);
    expect(find.bySemanticsLabel('Entrar no sistema'), findsOneWidget);
    expect(find.bySemanticsLabel('Criar cadastro'), findsOneWidget);
    expect(find.byTooltip('Mostrar senha'), findsOneWidget);

    await tester.ensureVisible(find.bySemanticsLabel('Criar cadastro'));
    await tester.tap(find.bySemanticsLabel('Criar cadastro'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('CPF, obrigatório'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('registration-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('registration-next')), findsOneWidget);

    await tester.tap(find.byKey(const Key('registration-next')));
    await tester.pumpAndSettle();
    expect(
        find.text('Informe nome e sobrenome, apenas letras.'), findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics && widget.properties.liveRegion == true),
        findsWidgets);

    semantics.dispose();
  });

  testWidgets('fundo de ondas é explicitamente decorativo', (tester) async {
    await tester.pumpWidget(const UbsApp());
    final decorative = find.descendant(
        of: find.byType(WaveBackground),
        matching: find.byType(ExcludeSemantics));
    expect(decorative, findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(WaveBackground),
            matching: find.byType(IgnorePointer)),
        findsOneWidget);
  });

  testWidgets('ação ocupada informa carregamento e estado desativado',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: AppActionButton(
                label: 'Enviar', onPressed: null, busy: true))));
    final semantics = tester.ensureSemantics();

    expect(find.bySemanticsLabel('Enviar, carregando'), findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics &&
            widget.properties.label == 'Enviar, carregando' &&
            widget.properties.liveRegion == true),
        findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);

    semantics.dispose();
  });
}
