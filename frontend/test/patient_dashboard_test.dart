import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubs_saude/main.dart';
import 'package:ubs_saude/models/api_models.dart';
import 'package:ubs_saude/services/api_service.dart';

class FakePatientApi extends ApiService {
  FakePatientApi({
    this.hasAppointment = true,
    this.specialtyName = 'Clínica geral',
    this.professionalName = 'Dra. Ana Souza',
    this.emptySpecialties = false,
    this.emptyDates = false,
    this.availableHours,
    this.priorityConditions = const [],
  });
  bool hasAppointment;
  final String specialtyName;
  final String professionalName;
  final bool emptySpecialties;
  final bool emptyDates;
  final List<int>? availableHours;
  List<Map<String, dynamic>> priorityConditions;
  bool offline = false, expired = false;
  int summaryCalls = 0;
  int appointmentCalls = 0;
  int bookings = 0;
  int cancellations = 0;
  int professionalSpecialtyCalls = 0;
  int availableTimeCalls = 0;
  Completer<void>? bookingCompleter;
  String status = 'agendado';
  late final at = DateTime.now().add(const Duration(days: 3));
  Appointment get item => Appointment.fromJson({
        'id': 12,
        'specialty': specialtyName,
        'professional': professionalName,
        'doctor_id': 8,
        'scheduled_at': at.toIso8601String(),
        'status': status,
      });
  PatientSummary get result => PatientSummary.fromJson({
        'patient': {
          'name': 'Victor Teste',
          'masked_cpf': '***.***.***-25',
          'birth_date': '1990-03-15',
          'email': 'victor@example.test',
          'phone': '11999998888',
          'priority_conditions': priorityConditions,
        },
        'next_appointment': hasAppointment
            ? {
                'id': 12,
                'specialty': specialtyName,
                'professional': professionalName,
                'doctor_id': 8,
                'scheduled_at': at.toIso8601String(),
                'status': status,
              }
            : null,
      });
  @override
  Future<PatientSummary> summary() async {
    summaryCalls++;
    if (expired) {
      throw const ApiException('Sessão expirada.', statusCode: 401);
    }
    if (offline) {
      throw const ApiException('Sem conexão.');
    }
    return result;
  }

  @override
  Future<List<Appointment>> appointments() async {
    appointmentCalls++;
    return hasAppointment ? [item] : [];
  }

  @override
  Future<List<Map<String, dynamic>>> specialties() async => emptySpecialties
      ? []
      : [
          {'id': 1, 'name': specialtyName}
        ];
  @override
  Future<List<Map<String, dynamic>>> professionals(String specialty) async => [
        {'id': 8, 'name': professionalName}
      ];
  @override
  Future<List<Map<String, dynamic>>> bookingProfessionals() async => [
        {'id': 8, 'name': professionalName}
      ];
  @override
  Future<List<Map<String, dynamic>>> specialtiesForProfessional(
      int professionalId) async {
    professionalSpecialtyCalls++;
    return [
      {'id': 1, 'name': specialtyName}
    ];
  }

  @override
  Future<List<DateTime>> availableDates(String specialty, int doctorId) async =>
      emptyDates ? [] : [at];
  @override
  Future<List<Slot>> availableTimes(
      String specialty, int doctorId, DateTime day) async {
    availableTimeCalls++;
    return (availableHours ?? [at.hour])
        .map((hour) => Slot.fromJson({
              'doctor_id': 8,
              'doctor_name': professionalName,
              'specialty': specialtyName,
              'scheduled_at':
                  DateTime(at.year, at.month, at.day, hour).toIso8601String()
            }))
        .toList();
  }

  @override
  Future<void> book(Slot slot) async {
    bookings++;
    if (bookingCompleter != null) await bookingCompleter!.future;
    hasAppointment = true;
  }

  @override
  Future<String> cancel(int id) async {
    cancellations++;
    status = 'cancelado';
    return 'Consulta cancelada com sucesso.';
  }
}

void main() {
  test('todos os status oficiais possuem rótulo textual', () {
    expect(statusLabel('agendado'), 'Agendada');
    expect(statusLabel('em_espera'), 'Check-in realizado');
    expect(statusLabel('em_triagem'), 'Em triagem');
    expect(statusLabel('em_atendimento'), 'Em atendimento');
    expect(statusLabel('concluido'), 'Concluída');
    expect(statusLabel('cancelado'), 'Cancelada');
    expect(statusLabel('falta'), 'Falta');
  });

  test('especialidades usam apresentação canônica sem duplicar opções', () {
    expect(specialtyDisplayName('Clínica gera'), 'Clínica Geral');
    expect(specialtyDisplayName('Clínica geral'), 'Clínica Geral');
    expect(specialtyDisplayName('Clínica Geral'), 'Clínica Geral');
    expect(specialtyDisplayName('UTI Adulto'), 'UTI Adulto');
    expect(
        uniqueSpecialtyOptions([
          {'id': 1, 'name': 'Clínica gera'},
          {'id': 2, 'name': 'Clínica Geral'},
        ]),
        hasLength(1));
  });

  testWidgets('patient_wide_layout_prioritizes_next_appointment',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(MaterialApp(home: PatientDashboard(api: FakePatientApi())));
    await tester.pump();
    expect(find.byType(ResponsiveAppShell), findsOneWidget);
    expect(
        find.byKey(const Key('wide-navigation-menu-button')), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Próxima consulta'), findsOneWidget);
    expect(find.text('Agendar consulta'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelamento é destrutivo e exige confirmação clara',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakePatientApi();
    await tester.pumpWidget(UbsApp(home: PatientDashboard(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ver detalhes').first);
    await tester.pumpAndSettle();
    expect(find.text('Cancelar consulta'), findsOneWidget);
    expect(find.bySemanticsLabel('Cancelar consulta, ação destrutiva'),
        findsOneWidget);
    final destructive = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Cancelar consulta'));
    final context = tester.element(find.text('Cancelar consulta'));
    final destructiveColor = Theme.of(context).colorScheme.error;
    expect(destructive.style?.backgroundColor?.resolve(<WidgetState>{}),
        destructiveColor);

    await tester.tap(find.text('Cancelar consulta'));
    await tester.pumpAndSettle();
    expect(find.text('Manter consulta'), findsNothing);
    expect(find.text('Voltar'), findsOneWidget);
    expect(find.text('Confirmar cancelamento'), findsOneWidget);
    expect(find.bySemanticsLabel('Confirmar cancelamento, ação destrutiva'),
        findsOneWidget);
    final confirmDestructive = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Confirmar cancelamento'));
    expect(confirmDestructive.autofocus, isFalse);
    expect(confirmDestructive.style?.backgroundColor?.resolve(<WidgetState>{}),
        destructiveColor);
    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();
    expect(api.cancellations, 0);

    await tester.tap(find.text('Ver detalhes').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar consulta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar cancelamento'));
    await tester.pumpAndSettle();
    expect(api.cancellations, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu do paciente fica fixo no canto superior esquerdo',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(MaterialApp(home: PatientDashboard(api: FakePatientApi())));
    await tester.pump();

    final menu = find.byKey(const Key('wide-navigation-menu-button'));
    final menuRect = tester.getRect(menu);
    final titleRect = tester.getRect(find.text('Olá, Victor!'));
    final brandRect = tester
        .getRect(find.bySemanticsLabel('UBS Rápida, saúde perto de você'));

    expect(menu, findsOneWidget);
    expect(menuRect.left, lessThanOrEqualTo(24));
    expect(menuRect.top, lessThanOrEqualTo(16));
    expect(menuRect.size,
        const Size(AppSizes.minTouchTarget, AppSizes.minTouchTarget));
    expect(menuRect.overlaps(titleRect), isFalse);
    expect(menuRect.overlaps(brandRect), isFalse);

    var menuHasKeyboardFocus = false;
    for (var attempt = 0; attempt < 20 && !menuHasKeyboardFocus; attempt++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      FocusManager.instance.primaryFocus?.context
          ?.visitAncestorElements((element) {
        if (element.widget.key == const Key('wide-navigation-menu-button')) {
          menuHasKeyboardFocus = true;
          return false;
        }
        return true;
      });
    }
    expect(menuHasKeyboardFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('patient_compact_layout_keeps_booking_action_48px',
      (tester) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: PatientDashboard(api: FakePatientApi(hasAppointment: false))));
    await tester.pump();
    final action =
        find.widgetWithText(AppActionButton, 'Agendar consulta').first;
    expect(action, findsOneWidget);
    expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cabeçalho e rolagem do paciente permanecem íntegros em 320 A+',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    accessibility.setFontScale(1.3);
    addTearDown(() => accessibility.setFontScale(1));
    await tester
        .pumpWidget(UbsApp(home: PatientDashboard(api: FakePatientApi())));
    await tester.pump();

    final logo = tester
        .getRect(find.bySemanticsLabel('UBS Rápida, saúde perto de você'));
    final greeting = tester.getRect(find.text('Olá, Victor!'));
    final menu =
        tester.getRect(find.byKey(const Key('wide-navigation-menu-button')));
    expect(logo.left, greaterThanOrEqualTo(0));
    expect(logo.right, lessThanOrEqualTo(320));
    expect(greeting.left, greaterThanOrEqualTo(0));
    expect(greeting.right, lessThanOrEqualTo(320));
    expect(menu.overlaps(logo), isFalse);
    expect(menu.overlaps(greeting), isFalse);

    final scroll = tester.widget<SingleChildScrollView>(
        find.byKey(const Key('patient-body-scroll-view')));
    expect(scroll.scrollDirection, Axis.vertical);
    expect((scroll.padding as EdgeInsets).right,
        greaterThanOrEqualTo(AppSpacing.xs));
    final scrollbar = tester
        .widget<Scrollbar>(find.byKey(const Key('patient-body-scrollbar')));
    expect(scrollbar.thumbVisibility, isFalse);
    expect(scrollbar.interactive, isFalse);
    expect(scrollbar.controller!.offset, 0);

    await tester.tap(find.byKey(const Key('wide-navigation-menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consultas').last);
    await tester.pumpAndSettle();
    expect(scrollbar.controller!.offset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('agendamento expõe campos, horário, vaga e confirmação',
      (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakePatientApi(
        hasAppointment: false, availableHours: const [7, 8, 13, 17]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BookingPanel(api: api, old: null, onChanged: () {}))));
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();

    expect(find.text('Como prefere começar?'), findsOneWidget);
    expect(
        find.text(
            'Escolha a área de atendimento e depois um profissional disponível.'),
        findsOneWidget);
    expect(find.byKey(const Key('booking-filter-mode')), findsOneWidget);
    final formTheme =
        Theme.of(tester.element(find.byKey(const Key('booking-specialty'))))
            .inputDecorationTheme;
    final guidance =
        tester.widget<Text>(find.byKey(const Key('booking-filter-guidance')));
    expect(formTheme.labelStyle?.fontSize, 16);
    expect(formTheme.hintStyle?.fontSize, 16);
    expect(formTheme.helperStyle?.fontSize, 14);
    expect(guidance.style?.fontSize, 16);

    expect(find.bySemanticsLabel(RegExp('Especialidade para agendamento')),
        findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clínica Geral').last);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('Profissional para agendamento')),
        findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dra. Ana Souza').last);
    await tester.pumpAndSettle();
    final specialtyRect =
        tester.getRect(find.byType(DropdownButtonFormField<String>));
    final professionalRect =
        tester.getRect(find.byType(DropdownButtonFormField<int>));
    final dateRect =
        tester.getRect(find.byType(DropdownButtonFormField<DateTime>));
    expect(specialtyRect.top, lessThan(professionalRect.top));
    expect(professionalRect.top, lessThan(dateRect.top));
    expect(
        find.bySemanticsLabel(RegExp('Data para agendamento')), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<DateTime>));
    await tester.pumpAndSettle();
    expect(find.text(showBookingDate(api.at)), findsOneWidget);
    await tester.tap(find.text(showBookingDate(api.at)).last);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r'\d\d:\d\d, Disponível')),
        findsNWidgets(4));
    expect(find.text('4. Escolha um horário'), findsOneWidget);
    expect(find.textContaining('4 horários disponíveis'), findsOneWidget);
    expect(find.text('Manhã'), findsOneWidget);
    expect(find.text('Tarde'), findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics &&
            widget.properties.label == 'Agendar consulta'),
        findsOneWidget);

    semantics.dispose();
  });

  testWidgets('agendamento explica especialidades inativas e ausência de vagas',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BookingPanel(
                api: FakePatientApi(emptySpecialties: true),
                old: null,
                onChanged: () {}))));
    await tester.pumpAndSettle();
    expect(
        find.text('Nenhuma especialidade ativa disponível para agendamento.'),
        findsOneWidget);

    final api = FakePatientApi(emptyDates: true);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BookingPanel(
                key: const ValueKey('empty-dates-booking'),
                api: api,
                old: null,
                onChanged: () {}))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clínica Geral').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(api.professionalName).last);
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Não há vagas disponíveis para este profissional. Tente outro filtro.'),
        findsOneWidget);
    final emptyMessage = tester.widget<Text>(find.text(
        'Não há vagas disponíveis para este profissional. Tente outro filtro.'));
    expect(emptyMessage.style?.fontSize, 16);
    expect(emptyMessage.style?.height, 1.45);
    expect(find.byKey(const Key('next-available-date')), findsNothing);
  });

  testWidgets('agendamento mantém modo e ação visíveis em 320px com A+',
      (tester) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    accessibility.setFontScale(1.3);
    addTearDown(() => accessibility.setFontScale(1));
    await tester.pumpWidget(UbsApp(
        home: Scaffold(
            body: BookingPanel(
                api: FakePatientApi(hasAppointment: false),
                old: null,
                onChanged: () {}))));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('booking-filter-mode')), findsOneWidget);
    expect(find.text('Confirmar agendamento'), findsOneWidget);
    await tester.tap(find.text('Profissional').first);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('booking-professional-first'),
            skipOffstage: false),
        findsOneWidget);
    expect(find.text('Confirmar agendamento'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('próxima data disponível carrega o primeiro dia com vaga',
      (tester) async {
    final api = FakePatientApi(hasAppointment: false);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BookingPanel(api: api, old: null, onChanged: () {}))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clínica Geral').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(api.professionalName).last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('next-available-date')), findsOneWidget);
    expect(api.availableTimeCalls, 0);
    await tester.tap(find.byKey(const Key('next-available-date')));
    await tester.pumpAndSettle();
    expect(api.availableTimeCalls, 1);
    expect(
        find.byType(AvailabilitySlotCard, skipOffstage: false), findsOneWidget);
  });

  testWidgets('resumo chega ao fim sem passar sob a ação fixa em A+',
      (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    accessibility.setFontScale(1.3);
    addTearDown(() => accessibility.setFontScale(1));
    final api = FakePatientApi(
        hasAppointment: false,
        specialtyName: 'Clínica geral',
        professionalName:
            'Dra. Ana Souza da Unidade Integrada de Saúde da Família');
    await tester.pumpWidget(UbsApp(
        home: Scaffold(
            body: BookingPanel(api: api, old: null, onChanged: () {}))));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clínica Geral').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(DropdownButtonFormField<int>));
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(api.professionalName).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(DropdownButtonFormField<DateTime>));
    await tester.tap(find.byType(DropdownButtonFormField<DateTime>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(showBookingDate(api.at)).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(AvailabilitySlotCard));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AvailabilitySlotCard));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('booking-summary')), findsOneWidget);

    final end = find.byKey(const Key('booking-summary-scroll-end'),
        skipOffstage: false);
    final action = find.text('Confirmar agendamento');
    await tester.scrollUntilVisible(end, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('booking-summary')), findsOneWidget);
    expect(end, findsOneWidget);
    expect(action, findsOneWidget);
    expect(tester.getBottomLeft(end).dy,
        lessThanOrEqualTo(tester.getTopLeft(action).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cabeçalho do paciente mantém somente a ação de sair',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: PatientDashboard(api: FakePatientApi(hasAppointment: false))));
    await tester.pump();

    final header = find.byType(ResponsivePageHeader);
    expect(find.descendant(of: header, matching: find.text('Sair')),
        findsOneWidget);
    expect(find.descendant(of: header, matching: find.text('Agendar consulta')),
        findsNothing);
    expect(find.text('Agendar consulta'), findsWidgets,
        reason: 'Os atalhos de agendamento do conteúdo devem permanecer.');
    expect(tester.takeException(), isNull);
  });

  testWidgets('long_professional_and_specialty_wrap_without_overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakePatientApi(
      specialtyName: 'Clínica médica integrada da família e comunidade',
      professionalName: 'Dra. Ana Carolina de Souza Albuquerque Ferreira',
    );
    await tester.pumpWidget(MaterialApp(home: PatientDashboard(api: api)));
    await tester.pump();
    expect(find.text(api.specialtyName), findsOneWidget);
    expect(find.text(api.professionalName), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('max_text_scale_keeps_status_and_action_visible', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    accessibility.fontSizeScale = 1.5;
    addTearDown(() => accessibility.fontSizeScale = 1);
    await tester
        .pumpWidget(MaterialApp(home: PatientDashboard(api: FakePatientApi())));
    await tester.pump();
    expect(find.text('Agendada'), findsWidgets);
    expect(find.text('Agendar consulta'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'status do paciente atualiza em cinco segundos, recupera de erro e cancela timer',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakePatientApi();
    await tester.pumpWidget(MaterialApp(home: PatientDashboard(api: api)));
    await tester.pump();
    expect(find.text('Olá, Victor!'), findsOneWidget);
    expect(find.text('Dra. Ana Souza'), findsOneWidget);
    expect(find.text('Minhas consultas'), findsOneWidget);
    expect(api.summaryCalls, 1);
    expect(api.appointmentCalls, 1);
    await tester.tap(find.text('Acompanhar status'));
    await tester.pump();
    expect(find.text('Atualização automática a cada cinco segundos.'),
        findsOneWidget);

    api.status = 'em_espera';
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Check-in realizado'), findsWidgets);
    expect(api.summaryCalls, 2);
    expect(api.appointmentCalls, 2,
        reason: 'O temporizador deve consultar /appointments/me uma vez.');

    api
      ..offline = true
      ..status = 'em_triagem';
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(api.summaryCalls, 3);
    expect(api.appointmentCalls, 3);
    expect(find.text('Check-in realizado'), findsWidgets,
        reason: 'Um erro temporário deve preservar o último estado válido.');

    api.offline = false;
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(api.summaryCalls, 4);
    expect(api.appointmentCalls, 4);
    expect(find.text('Em triagem'), findsWidgets,
        reason: 'A consulta periódica deve continuar após o erro.');

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 10));
    expect(api.summaryCalls, 4,
        reason: 'O temporizador deve ser cancelado ao sair da tela.');
    expect(api.appointmentCalls, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard mobile sem consulta abre agendamento', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    accessibility.fontSizeScale = 1.3;
    addTearDown(() => accessibility.fontSizeScale = 1);
    await tester.pumpWidget(MaterialApp(
        home: PatientDashboard(api: FakePatientApi(hasAppointment: false))));
    await tester.pump();
    expect(find.text('Você não possui consultas agendadas.'), findsOneWidget);
    expect(
        find.byKey(const Key('wide-navigation-menu-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('wide-navigation-menu-button')));
    await tester.pumpAndSettle();
    expect(find.text('Consultas'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Perfil'), findsOneWidget);
    await tester.tap(find.text('Início').last);
    await tester.pumpAndSettle();
    final bookingAction =
        find.widgetWithText(AppActionButton, 'Agendar consulta').first;
    await tester.ensureVisible(bookingAction);
    await tester.pumpAndSettle();
    await tester.tap(bookingAction);
    await tester.pumpAndSettle();
    expect(find.text('Especialidade'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('agendamento mobile usa tela completa e protege a seleção',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakePatientApi(hasAppointment: false);
    await tester.pumpWidget(MaterialApp(home: PatientDashboard(api: api)));
    await tester.pump();

    final action = find.text('Agendar consulta').first;
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.byType(BookingPanel), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clínica Geral').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();
    expect(find.text('Sair do agendamento?'), findsOneWidget);
    expect(find.text('Continuar agendamento'), findsOneWidget);
    expect(find.text('Descartar seleção'), findsOneWidget);

    await tester.tap(find.text('Continuar agendamento'));
    await tester.pumpAndSettle();
    expect(find.byType(BookingPanel), findsOneWidget);
    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar seleção'));
    await tester.pumpAndSettle();
    expect(find.byType(BookingPanel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('agendamento confirma após resposta e atualiza painel',
      (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakePatientApi(hasAppointment: false);
    await tester.pumpWidget(MaterialApp(home: PatientDashboard(api: api)));
    await tester.pump();
    await tester.tap(find.text('Agendar consulta').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clínica Geral').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dra. Ana Souza').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<DateTime>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(showBookingDate(api.at)).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AvailabilitySlotCard).first);
    await tester.pumpAndSettle();
    expect(api.bookings, 0);
    expect(find.text('Sua consulta'), findsOneWidget);
    expect(find.text('Revise os dados antes de confirmar.'), findsOneWidget);
    final summary = find.byKey(const Key('booking-summary'));
    expect(find.descendant(of: summary, matching: find.text('Especialidade')),
        findsOneWidget);
    expect(find.descendant(of: summary, matching: find.text('Profissional')),
        findsOneWidget);
    expect(find.byKey(const Key('booking-summary-date-time')), findsOneWidget);
    expect(
        find.text(showBookingSummaryDate(
            DateTime(api.at.year, api.at.month, api.at.day, api.at.hour))),
        findsOneWidget);
    expect(find.text('Alterar horário'), findsOneWidget);
    expect(find.text('A reserva será concluída ao confirmar.'), findsOneWidget);
    expect(find.byType(AvailabilityLegend), findsNothing,
        reason: 'Os próprios cartões já comunicam o estado do horário.');
    expect(find.text('Selecionado', skipOffstage: false), findsOneWidget);
    await tester.tap(find.text('Confirmar agendamento'));
    await tester.pumpAndSettle();
    expect(api.bookings, 1);
    expect(find.text('Dra. Ana Souza'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('agendamento permite começar por especialidade ou profissional',
      (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakePatientApi(hasAppointment: false);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BookingPanel(api: api, old: null, onChanged: () {}))));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('booking-filter-mode')), findsOneWidget);
    expect(
        find.text(
            'Escolha a área de atendimento e depois um profissional disponível.'),
        findsOneWidget);
    expect(find.byKey(const Key('booking-professional-first')), findsNothing);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

    await tester.tap(find.text('Profissional').first);
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Escolha quem fará o atendimento e depois uma especialidade disponível.'),
        findsOneWidget);
    expect(find.byKey(const Key('booking-professional-first')), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);

    await tester.tap(find.byKey(const Key('booking-professional-first')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(api.professionalName).last);
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(specialtyDisplayName(api.specialtyName)).last);
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<DateTime>), findsOneWidget);
    expect(api.professionalSpecialtyCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('booking_submits_once_while_request_is_pending', (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakePatientApi(hasAppointment: false)
      ..bookingCompleter = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BookingPanel(api: api, old: null, onChanged: () {}))));
    await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clínica Geral').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dra. Ana Souza').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<DateTime>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(showBookingDate(api.at)).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AvailabilitySlotCard).first);
    await tester.pump();
    final confirm = find.text('Confirmar agendamento');
    await tester.tap(confirm);
    await tester.tap(confirm);
    await tester.pump();
    expect(api.bookings, 1);
    expect(find.byType(AppActionButton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    api.bookingCompleter!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('erro de conexão permite tentar novamente', (tester) async {
    final api = FakePatientApi()..offline = true;
    await tester.pumpWidget(MaterialApp(home: PatientDashboard(api: api)));
    await tester.pump();
    expect(find.text('Sem conexão.'), findsOneWidget);
    api.offline = false;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    expect(find.text('Olá, Victor!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'decisão prioritária confirmada gera aviso único e orientação ao paciente',
      (tester) async {
    final api = FakePatientApi(priorityConditions: [
      {
        'condition': 'pcd',
        'status': 'pendente',
        'reported_at': '2026-11-13T10:00:00'
      }
    ]);
    await tester.pumpWidget(MaterialApp(home: PatientDashboard(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wide-navigation-menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perfil').last);
    await tester.pumpAndSettle();
    expect(find.text('Aguardando confirmação presencial'), findsOneWidget);

    api.priorityConditions = [
      {
        'condition': 'pcd',
        'status': 'confirmada',
        'reported_at': '2026-11-13T10:00:00',
        'validated_at': '2026-11-13T11:15:00'
      }
    ];
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(find.byKey(const ValueKey('priority-decision-pcd-confirmada')),
        findsOneWidget);
    expect(find.text('Resultado: confirmada'), findsOneWidget);
    expect(
        find.text(
            'A condição foi incluída no cálculo da prioridade dos próximos atendimentos.'),
        findsOneWidget);
    const transitionNotice =
        'PCD confirmada. A condição foi incluída no cálculo da prioridade dos próximos atendimentos.';
    expect(find.text(transitionNotice), findsOneWidget);

    ScaffoldMessenger.of(tester.element(find.byType(PatientDashboard)))
        .clearSnackBars();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.byKey(const ValueKey('priority-decision-pcd-confirmada')),
        findsOneWidget);
    expect(find.text(transitionNotice), findsNothing,
        reason: 'A atualização automática não deve repetir o mesmo aviso.');
  });

  testWidgets('decisão prioritária rejeitada mostra data e efeito',
      (tester) async {
    final api = FakePatientApi(priorityConditions: [
      {
        'condition': 'gestante',
        'status': 'rejeitada',
        'reported_at': '2026-11-13T10:00:00',
        'validated_at': '2026-11-13T12:30:00'
      }
    ]);
    await tester.pumpWidget(MaterialApp(home: PatientDashboard(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wide-navigation-menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perfil').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('priority-decision-gestante-rejeitada')),
        findsOneWidget);
    expect(find.text('Resultado: rejeitada'), findsOneWidget);
    expect(find.textContaining('Decisão em 13/11 às 12:30'), findsOneWidget);
    expect(
        find.text(
            'A condição não altera sua prioridade de atendimento. Procure a Recepção se precisar de orientação.'),
        findsOneWidget);
  });

  testWidgets('sessão expirada retorna ao login', (tester) async {
    final api = FakePatientApi()..expired = true;
    await tester.pumpWidget(MaterialApp(home: PatientDashboard(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Acesse sua conta'), findsOneWidget);
    expect(find.byType(PatientDashboard), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
