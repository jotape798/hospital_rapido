import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubs_saude/main.dart';
import 'package:ubs_saude/models/api_models.dart';
import 'package:ubs_saude/services/api_service.dart';

class _ConsultationsApi extends ApiService {
  _ConsultationsApi({this.hasAppointment = true});

  final bool hasAppointment;
  int appointmentCalls = 0;
  late final scheduledAt = DateTime.now().add(const Duration(days: 3));

  Appointment get consultation => Appointment.fromJson({
        'id': 42,
        'specialty': 'Clínica Geral',
        'professional': 'Dra. Ana Souza',
        'doctor_id': 8,
        'scheduled_at': scheduledAt.toIso8601String(),
        'status': 'agendado',
      });

  @override
  Future<PatientSummary> summary() async => PatientSummary.fromJson({
        'patient': {
          'name': 'Victor Teste',
          'masked_cpf': '***.***.***-25',
          'birth_date': '1990-03-15',
          'email': 'victor@example.test',
          'phone': '11999998888',
        },
        'next_appointment': hasAppointment
            ? {
                'id': 42,
                'specialty': 'Clínica Geral',
                'professional': 'Dra. Ana Souza',
                'doctor_id': 8,
                'scheduled_at': scheduledAt.toIso8601String(),
                'status': 'agendado',
              }
            : null,
      });

  @override
  Future<List<Appointment>> appointments() async {
    appointmentCalls++;
    return hasAppointment ? [consultation] : [];
  }
}

Future<void> _openConsultations(WidgetTester tester, _ConsultationsApi api,
    {Widget Function(Widget child)? appBuilder}) async {
  final dashboard = PatientDashboard(api: api);
  await tester
      .pumpWidget(appBuilder?.call(dashboard) ?? UbsApp(home: dashboard));
  await tester.pump();
  await tester.tap(find.byKey(const Key('wide-navigation-menu-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Consultas').last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    accessibility.setContrast(false);
    accessibility.setFontScale(1);
  });

  tearDown(() {
    accessibility.setContrast(false);
    accessibility.setFontScale(1);
  });

  testWidgets(
      'Minhas consultas aparece uma vez, é acessível e mantém lista e detalhes',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final api = _ConsultationsApi();
    await _openConsultations(tester, api);

    expect(find.text('Minhas consultas'), findsOneWidget);
    expect(find.bySemanticsLabel('Minhas consultas'), findsOneWidget);
    expect(find.text('Próximas'), findsOneWidget);
    expect(find.text('Dra. Ana Souza'), findsOneWidget);
    expect(api.appointmentCalls, 1);

    final bodyTop =
        tester.getTopLeft(find.byKey(const Key('patient-body-scroll-view'))).dy;
    final firstSectionTop = tester.getTopLeft(find.text('Próximas')).dy;
    expect(firstSectionTop - bodyTop, lessThan(64),
        reason: 'A remoção do título interno não deve deixar espaço vazio.');

    await tester.tap(find.text('Ver detalhes').first);
    await tester.pumpAndSettle();
    expect(find.text('Detalhes da consulta'), findsOneWidget);
    expect(find.text('Cancelar consulta'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('estado vazio mantém um único título acessível', (tester) async {
    final semantics = tester.ensureSemantics();
    await _openConsultations(tester, _ConsultationsApi(hasAppointment: false));

    expect(find.text('Minhas consultas'), findsOneWidget);
    expect(find.bySemanticsLabel('Minhas consultas'), findsOneWidget);
    expect(find.text('Nenhuma consulta nesta categoria.'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('título único não causa overflow nas larguras exigidas',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final width in [390.0, 768.0, 1366.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await _openConsultations(tester, _ConsultationsApi());

      expect(find.text('Minhas consultas'), findsOneWidget,
          reason: 'largura $width');
      expect(find.text('Próximas'), findsOneWidget, reason: 'largura $width');
      expect(tester.takeException(), isNull, reason: 'largura $width');
    }
  });

  testWidgets('tema escuro, alto contraste e texto ampliado continuam usáveis',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;

    await _openConsultations(tester, _ConsultationsApi(),
        appBuilder: (child) => MaterialApp(
            theme: ThemeData.dark(useMaterial3: true), home: child));
    expect(find.text('Minhas consultas'), findsOneWidget);
    expect(tester.takeException(), isNull);

    accessibility.setContrast(true);
    accessibility.setFontScale(1.3);
    await _openConsultations(tester, _ConsultationsApi());
    expect(find.text('Minhas consultas'), findsOneWidget);
    expect(find.text('Próximas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('navegação por teclado alcança os controles da seção',
      (tester) async {
    await _openConsultations(tester, _ConsultationsApi());

    var reachedDetails = false;
    final detailsButton = tester
        .element(find.widgetWithText(OutlinedButton, 'Ver detalhes').first);
    for (var attempt = 0; attempt < 30 && !reachedDetails; attempt++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      final focusedContext = FocusManager.instance.primaryFocus?.context;
      if (identical(focusedContext, detailsButton)) {
        reachedDetails = true;
      }
      focusedContext?.visitAncestorElements((element) {
        if (identical(element, detailsButton)) {
          reachedDetails = true;
          return false;
        }
        return true;
      });
    }
    expect(reachedDetails, isTrue);
    expect(tester.takeException(), isNull);
  });
}
