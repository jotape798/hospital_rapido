import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubs_saude/main.dart';
import 'package:ubs_saude/services/api_service.dart';

void main() {
  setUpAll(() async {
    final fonts = Platform.environment['UBS_TEST_FONTS'];
    if (fonts != null) {
      final textFont = FontLoader('Roboto')
        ..addFont(File('$fonts/roboto-regular.ttf')
            .readAsBytes()
            .then((v) => ByteData.sublistView(v)));
      final icons = FontLoader('MaterialIcons')
        ..addFont(File('$fonts/materialicons-regular.otf')
            .readAsBytes()
            .then((v) => ByteData.sublistView(v)));
      await textFont.load();
      await icons.load();
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    accessibility.highContrast = false;
    accessibility.fontSizeScale = 1;
    ApiService.session = null;
  });

  test('nova sessão remove só preferências de CPF e preserva demais dados',
      () async {
    SharedPreferences.setMockInitialValues({
      'ubs_cpf': '52998224725',
      'ubs_remember_user': true,
      'ubs_token': 'test-token',
      'ubs_high_contrast': true
    });
    expect(await ApiService.restoreSession(), false);
    final p = await SharedPreferences.getInstance();
    expect(p.containsKey('ubs_cpf'), false);
    expect(p.containsKey('ubs_remember_user'), false);
    expect(p.getString('ubs_token'), 'test-token');
    expect(p.getBool('ubs_high_contrast'), true);
    expect(ApiService.session, isNull);
  });

  test('comparações normalizadas do responsável e idade', () {
    expect(guardianCpfRule('529.982.247-25', '52998224725'),
        'O CPF do responsável deve ser diferente do CPF do paciente.');
    expect(guardianNameRule('  JOÃO   SILVA ', 'Joao Silva'),
        'O nome do responsável deve ser diferente do nome do paciente.');
    expect(guardianEmailRule(' A@EXAMPLE.COM ', 'a@example.com'),
        'O e-mail do responsável deve ser diferente do e-mail do paciente.');
    expect(guardianPhoneRule('(11) 99999-8888', '11999998888'),
        'O telefone do responsável deve ser diferente do telefone do paciente.');
    expect(guardianEmailRule('', 'a@example.com'),
        'Informe o e-mail válido do responsável legal.');
    expect(guardianEmailRule('invalid', 'a@example.com'), isNotNull);
    expect(guardianCpfRule('', '52998224725'), isNotNull);
    expect(guardianBirthRule('2015-01-01'), isNotNull);
    expect(guardianBirthRule('1980-01-01'), isNull);
  });

  testWidgets(
      'login vazio sem lembrar usuário; erro recebe foco e mantém entrada',
      (tester) async {
    await tester.pumpWidget(const UbsApp());
    expect(find.text('Lembrar do meu usuário'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    final cpf = find.byType(TextFormField).first;
    expect(tester.widget<TextFormField>(cpf).controller!.text, '');
    await tester.enterText(cpf, '11111111111');
    await tester.ensureVisible(find.text('Entrar'));
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextFormField>(cpf).controller!.text, '111.111.111-11');
    expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .focusNode
            .hasFocus,
        true);
    final semantics = tester.ensureSemantics();
    expect(
        find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true),
        findsWidgets);
    semantics.dispose();
  });

  for (final size in [const Size(360, 800), const Size(1280, 900)]) {
    testWidgets('contraste preto imediato, fontes e retorno $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      accessibility.highContrast = true;
      final boundaryKey = GlobalKey();
      await tester
          .pumpWidget(RepaintBoundary(key: boundaryKey, child: const UbsApp()));
      await tester.pumpAndSettle();
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          Colors.black);
      final painters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<WavePainter>();
      expect(painters.single.highContrast, true);
      for (final scale in [.85, 1.0, 1.3]) {
        accessibility.setFontScale(scale);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      accessibility.setContrast(false);
      await tester.pumpAndSettle();
      expect(
          Theme.of(tester.element(find.byType(Scaffold)))
              .inputDecorationTheme
              .fillColor,
          Colors.white);
      accessibility.setContrast(true);
      await tester.pumpAndSettle();
      final boundary = boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final pixels = await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('test-renders')..createSync(recursive: true);
        await File('${dir.path}/login-contraste-${size.width.toInt()}.png')
            .writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
        return bytes!.buffer.asUint8List().sublist(0, 3);
      });
      expect(pixels, [0, 0, 0]);
      await tester.ensureVisible(find.text('Esqueceu a senha?'));
      await tester.tap(find.text('Esqueceu a senha?'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Voltar'));
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(accessibility.highContrast, true);
      expect(find.text('Acesse sua conta'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('recuperação solicita e-mail e valida entrada', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RecoveryPage()));
    expect(find.text('E-mail cadastrado'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'email-invalido');
    await tester.ensureVisible(find.text('Enviar código'));
    await tester.tap(find.text('Enviar código'));
    await tester.pumpAndSettle();
    expect(find.text('Informe um e-mail válido.'), findsOneWidget);
    expect(find.text('Código de verificação'), findsNothing);
  });

  testWidgets('teclado navega com Tab e Shift Tab', (tester) async {
    await tester.pumpWidget(const UbsApp());
    await tester.tap(find.byType(TextFormField).first);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
        tester
            .widget<EditableText>(find.byType(EditableText).last)
            .focusNode
            .hasFocus,
        true);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .focusNode
            .hasFocus,
        true);
  });
}
