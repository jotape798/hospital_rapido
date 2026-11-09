import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubs_saude/main.dart';
import 'package:ubs_saude/models/api_models.dart';
import 'package:ubs_saude/services/api_service.dart';

AdminAppointment fakeAppointment(String status,
        {int id = 22,
        String? risk,
        String? riskLabel,
        String patient = 'Paciente Fictício',
        bool triageActionAllowed = true,
        String? triageBlockReason}) =>
    AdminAppointment.fromJson({
      'id': id,
      'scheduled_at': DateTime.now()
          .copyWith(hour: 10, minute: 0, second: 0, millisecond: 0)
          .toIso8601String(),
      'patient': patient,
      'patient_document': '***.***.***-25',
      'specialty': 'Clínica Geral',
      'professional': 'Profissional Fictício',
      'professional_id': 2,
      'status': status,
      'legal_priority': 'geral',
      'priority_reason': 'Sem prioridade legal',
      'risk_classification': risk,
      'risk_label': riskLabel,
      'triage_action_allowed': triageActionAllowed,
      'triage_block_reason': triageBlockReason,
      'arrived_at':
          status == 'agendado' ? null : DateTime.now().toIso8601String(),
    });

class FakeStaffApi extends ApiService {
  FakeStaffApi(this.professional,
      {this.patientName = 'Paciente Fictício',
      this.withPendingPcd = false,
      this.failReceptionLoad = false,
      this.failNursingLoad = false,
      this.withBlockedTriage = false,
      this.priorityValidationError});
  final bool professional;
  final String patientName;
  final bool withPendingPcd;
  bool failReceptionLoad;
  bool failNursingLoad;
  final bool withBlockedTriage;
  final String? priorityValidationError;
  int checkIns = 0;
  int classifications = 0;
  int calls = 0;
  int priorityValidationCalls = 0;
  bool initialTriageCompleted = false;
  String receptionStatus = 'agendado';
  Completer<void>? nextReceptionRequest;
  DateTime? lastDay;
  String? lastSpecialty, lastStatus, lastRisk, lastPatient;
  int? lastProfessionalId;

  @override
  Future<Map<String, dynamic>> receptionSummary([DateTime? day]) async => {
        'scheduled': 1,
        'checked_in': 2,
        'in_care': 3,
        'completed': 4,
        'absent': 5,
      };

  @override
  Future<List<AdminAppointment>> receptionAppointments(
      {DateTime? day,
      String? specialty,
      int? professionalId,
      String? status,
      String? patient}) async {
    if (failReceptionLoad) {
      throw const ApiException('Não foi possível comunicar com a UBS.');
    }
    final pending = nextReceptionRequest;
    nextReceptionRequest = null;
    lastDay = day;
    lastSpecialty = specialty;
    lastProfessionalId = professionalId;
    lastStatus = status;
    lastPatient = patient;
    if (pending != null) await pending.future;
    if (specialty != null ||
        professionalId != null ||
        status != null ||
        (patient?.isNotEmpty ?? false)) {
      return [];
    }
    return [fakeAppointment(receptionStatus, patient: patientName)];
  }

  @override
  Future<Map<String, dynamic>> nursingSummary([DateTime? day]) async => {
        'awaiting_triage': 1,
        'in_care': 2,
        'completed': 3,
        'risk_counts': {
          'muito_alto': 1,
          'alto': 2,
          'moderado': 3,
          'baixo': 4,
        }
      };

  @override
  Future<List<AdminAppointment>> nursingQueue(
      {DateTime? day, String? specialty, String? status, String? risk}) async {
    if (failNursingLoad) {
      throw const ApiException('Não foi possível comunicar com a UBS.');
    }
    lastDay = day;
    lastSpecialty = specialty;
    lastStatus = status;
    lastRisk = risk;
    if (specialty != null || status != null || risk != null) return [];
    return [
      fakeAppointment(initialTriageCompleted ? 'em_triagem' : 'em_espera',
          risk: 'baixo', riskLabel: 'Baixo', patient: patientName),
      if (withBlockedTriage)
        fakeAppointment('em_espera',
            id: 23,
            patient: 'Paciente em segundo lugar',
            triageActionAllowed: initialTriageCompleted,
            triageBlockReason: initialTriageCompleted
                ? null
                : 'Outro paciente está à frente na fila.'),
    ];
  }

  @override
  Future<List<AdminAppointment>> professionalQueue([DateTime? day]) async => [
        fakeAppointment('em_triagem',
            risk: 'baixo', riskLabel: 'Baixo', patient: patientName)
      ];

  @override
  Future<void> receptionCheckIn(int id) async {
    checkIns++;
    receptionStatus = 'em_espera';
  }

  @override
  Future<void> receptionAbsence(int id) async {}

  @override
  Future<void> receptionValidatePriorityCondition(
      int appointmentId, String condition, String status) async {
    priorityValidationCalls++;
    if (priorityValidationError != null) {
      throw ApiException(priorityValidationError!, statusCode: 409);
    }
  }

  @override
  Future<void> classifyRisk(int id, String level, String complaint,
      String vitalSigns, String? observation) async {
    classifications++;
    if (id == 22) initialTriageCompleted = true;
  }

  @override
  Future<void> startCare(int id) async {}

  @override
  Future<void> completeCare(int id) async {}

  @override
  Future<Map<String, dynamic>> receptionDetails(int id) async => _details();

  @override
  Future<Map<String, dynamic>> nursingDetails(int id) async => _details();

  @override
  Future<Map<String, dynamic>> professionalDetails(int id) async => _details();

  @override
  Future<void> callPatient(int id) async {
    calls++;
  }

  Map<String, dynamic> _details() => {
        'id': 22,
        'patient': 'Paciente Fictício',
        'patient_document': '***.***.***-25',
        'specialty': 'Clínica Geral',
        'professional': 'Profissional Fictício',
        'scheduled_at': DateTime.now().toIso8601String(),
        'status': professional ? 'em_espera' : receptionStatus,
        'arrived_at': professional || receptionStatus != 'agendado'
            ? DateTime.now().toIso8601String()
            : null,
        'priority_conditions': withPendingPcd
            ? [
                {
                  'condition': 'pcd',
                  'status': 'pendente',
                  'reported_at': DateTime.now().toIso8601String(),
                }
              ]
            : [],
      };
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    accessibility.setContrast(false);
    accessibility.setFontScale(1);
  });

  tearDown(() {
    ApiService.session = null;
    accessibility.setContrast(false);
    accessibility.setFontScale(1);
  });

  testWidgets('reception_wide_uses_filter_and_results_regions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1366, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ApiService.session =
        const Session('token', 'Recepção Fictícia', 'recepcao', []);
    await tester
        .pumpWidget(UbsApp(home: StaffDashboard(api: FakeStaffApi(false))));
    await tester.pumpAndSettle();
    expect(find.byType(ResponsiveAppShell), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byKey(const Key('staff-filter-region')), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Localizar agendamento por nome ou CPF'),
        findsOneWidget);
    expect(find.bySemanticsLabel('Registrar check-in'), findsOneWidget);
    expect(find.bySemanticsLabel('Registrar no-show ou falta'), findsOneWidget);
    expect(find.byTooltip('Buscar'), findsOneWidget);
    final filterKeys = [
      const Key('staff-filter-date'),
      const Key('staff-search'),
      const Key('staff-filter-specialty'),
      const Key('staff-filter-professional'),
      const Key('staff-filter-status'),
    ];
    final filterRects =
        filterKeys.map((key) => tester.getRect(find.byKey(key))).toList();
    expect(filterRects.map((rect) => rect.top).toSet(), hasLength(1));
    for (final rect in filterRects.skip(1)) {
      expect(rect.width, closeTo(filterRects.first.width, .01));
    }
    for (var index = 1; index < filterRects.length; index++) {
      expect(filterRects[index].left, greaterThan(filterRects[index - 1].left));
    }
    semantics.dispose();
    expect(find.byKey(const Key('staff-results-region')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reception_compact_collapses_filters_without_hiding_checkin',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ApiService.session =
        const Session('token', 'Recepção Fictícia', 'recepcao', []);
    await tester
        .pumpWidget(UbsApp(home: StaffDashboard(api: FakeStaffApi(false))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('staff-compact-filters')), findsOneWidget);
    expect(find.text('Check-in'), findsWidgets);
    expect(
        find.widgetWithText(OutlinedButton, 'Não compareceu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'detalhes fica à direita e dados essenciais são legíveis em 390 768 1280',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ApiService.session =
        const Session('token', 'Recepção Fictícia', 'recepcao', []);
    for (final width in [390.0, 768.0, 1280.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester
          .pumpWidget(UbsApp(home: StaffDashboard(api: FakeStaffApi(false))));
      await tester.pumpAndSettle();

      final card = find.byKey(const Key('staff-appointment-card-22'));
      final details = find.byKey(const Key('staff-details-button-22'));
      final cardRect = tester.getRect(card);
      final detailsRect = tester.getRect(details);
      final patient = tester.widget<Text>(find.text('Paciente Fictício'));
      final schedule = tester.widget<Text>(find.textContaining('Horário:'));

      expect(detailsRect.center.dx, greaterThan(cardRect.center.dx),
          reason: 'largura $width');
      expect(detailsRect.right, lessThanOrEqualTo(cardRect.right),
          reason: 'largura $width');
      expect(cardRect.right - detailsRect.right, lessThanOrEqualTo(20),
          reason: 'o botão deve ficar no extremo direito em $width');
      expect(detailsRect.height, greaterThanOrEqualTo(48),
          reason: 'largura $width');
      expect(patient.style?.fontSize, greaterThanOrEqualTo(20),
          reason: 'largura $width');
      expect(schedule.style?.fontSize, greaterThanOrEqualTo(18),
          reason: 'largura $width');
      expect(find.text('Especialidade: Clínica Geral'), findsOneWidget);
      expect(find.text('Profissional: Profissional Fictício'), findsOneWidget);
      expect(find.text('Prioridade: Sem prioridade legal'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'largura $width');
    }
  });

  testWidgets('empty_reception_can_clear_filters_without_changing_day',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeStaffApi(false);
    ApiService.session =
        const Session('token', 'Recepção Fictícia', 'recepcao', []);
    await tester.pumpWidget(UbsApp(home: StaffDashboard(api: api)));
    await tester.pumpAndSettle();
    final originalDay = api.lastDay;

    await tester.enterText(find.byKey(const Key('staff-search')), 'Ninguém');
    await tester.tap(find.byTooltip('Buscar'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum atendimento encontrado'), findsOneWidget);
    expect(
        find.ancestor(
            of: find.text('Nenhum atendimento encontrado'),
            matching: find.byType(Card)),
        findsWidgets);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    await tester.tap(find.text('Limpar filtros'));
    await tester.pumpAndSettle();

    expect(api.lastSpecialty, isNull);
    expect(api.lastProfessionalId, isNull);
    expect(api.lastStatus, isNull);
    expect(api.lastRisk, isNull);
    expect(api.lastPatient, isEmpty);
    expect(showOnlyDate(api.lastDay!), showOnlyDate(originalDay!));
    expect(find.text('Paciente Fictício'), findsOneWidget);
  });

  testWidgets('reception_load_failure_is_not_presented_as_empty_queue',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeStaffApi(false, failReceptionLoad: true);
    ApiService.session =
        const Session('token', 'Recepção Fictícia', 'recepcao', []);

    await tester.pumpWidget(UbsApp(home: StaffDashboard(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível carregar'), findsOneWidget);
    expect(find.textContaining('Verifique sua conexão'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(find.text('Nenhum atendimento encontrado'), findsNothing);

    api.failReceptionLoad = false;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Paciente Fictício'), findsOneWidget);
    expect(find.text('Não foi possível carregar'), findsNothing);
  });

  testWidgets('failed_refresh_preserves_previous_reception_results',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeStaffApi(false);
    ApiService.session =
        const Session('token', 'Recepção Fictícia', 'recepcao', []);

    await tester.pumpWidget(UbsApp(home: StaffDashboard(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Paciente Fictício'), findsOneWidget);

    api.failReceptionLoad = true;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Atualizar'));
    await tester.pumpAndSettle();

    expect(find.text('Paciente Fictício'), findsOneWidget);
    expect(find.textContaining('podem estar desatualizados'), findsOneWidget);
    expect(find.text('Nenhum atendimento encontrado'), findsNothing);
  });

  testWidgets('nursing_load_failure_is_not_presented_as_empty_queue',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeStaffApi(true, failNursingLoad: true);
    ApiService.session = const Session(
        'token', 'Enfermagem Fictícia', 'enfermagem', ['triage:write']);

    await tester.pumpWidget(UbsApp(home: StaffDashboard(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível carregar'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(find.text('Nenhum atendimento encontrado'), findsNothing);

    api.failNursingLoad = false;
    await tester.ensureVisible(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Paciente Fictício'), findsOneWidget);
    expect(find.text('Não foi possível carregar'), findsNothing);
  });

  testWidgets('clear_filters_is_disabled_while_request_is_pending',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeStaffApi(false);
    ApiService.session =
        const Session('token', 'Recepção Fictícia', 'recepcao', []);
    await tester.pumpWidget(UbsApp(home: StaffDashboard(api: api)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('staff-search')), 'Ninguém');
    await tester.tap(find.byTooltip('Buscar'));
    await tester.pumpAndSettle();
    expect(find.text('Limpar filtros'), findsOneWidget);

    final pending = Completer<void>();
    api.nextReceptionRequest = pending;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Atualizar'));
    await tester.pump();
    expect(find.text('Limpar filtros'), findsNothing);

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Limpar filtros'), findsOneWidget);
    expect(api.lastPatient, 'Ninguém');

    await tester.tap(find.text('Limpar filtros'));
    await tester.pumpAndSettle();
    expect(api.lastPatient, isEmpty);
    expect(find.text('Paciente Fictício'), findsOneWidget);
  });

  testWidgets('empty_nursing_can_clear_status_and_risk', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeStaffApi(true);
    ApiService.session = const Session(
        'token', 'Enfermagem Fictícia', 'enfermagem', ['triage:write']);
    await tester.pumpWidget(UbsApp(home: StaffDashboard(api: api)));
    await tester.pumpAndSettle();
    final originalDay = api.lastDay;

    await tester.tap(find.byKey(const Key('staff-filter-risk')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alto').last);
    await tester.pumpAndSettle();
    expect(find.text('Nenhum atendimento encontrado'), findsOneWidget);
    await tester.ensureVisible(find.text('Limpar filtros'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Limpar filtros'));
    await tester.pumpAndSettle();

    expect(api.lastStatus, isNull);
    expect(api.lastRisk, isNull);
    expect(showOnlyDate(api.lastDay!), showOnlyDate(originalDay!));
  });

  testWidgets('long_patient_name_does_not_hide_actions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const longName =
        'Paciente com nome muito longo da Silva Albuquerque e Nascimento';
    ApiService.session =
        const Session('token', 'Recepção Fictícia', 'recepcao', []);
    await tester.pumpWidget(UbsApp(
        home: StaffDashboard(api: FakeStaffApi(false, patientName: longName))));
    await tester.pumpAndSettle();
    expect(find.text(longName), findsOneWidget);
    expect(find.text('Check-in'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('risk_level_has_text_and_semantics_in_high_contrast',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    accessibility.setContrast(true);
    ApiService.session = const Session(
        'token', 'Enfermagem Fictícia', 'enfermagem', ['triage:write']);
    await tester
        .pumpWidget(UbsApp(home: StaffDashboard(api: FakeStaffApi(true))));
    await tester.pumpAndSettle();
    expect(find.text('Risco: Baixo'), findsWidgets);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics &&
            widget.properties.label == 'Classificação de risco: baixo'),
        findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clinical_queue_survives_max_text_scale_at_360', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    accessibility.setFontScale(1.3);
    ApiService.session = const Session(
        'token', 'Enfermagem Fictícia', 'enfermagem', ['triage:write']);
    await tester
        .pumpWidget(UbsApp(home: StaffDashboard(api: FakeStaffApi(true))));
    await tester.pumpAndSettle();
    expect(find.text('Classificar risco'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filtro de risco mantém texto e ícone visíveis com A+',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    accessibility.setFontScale(1.3);
    ApiService.session = const Session(
        'token', 'Enfermagem Fictícia', 'enfermagem', ['triage:write']);
    await tester
        .pumpWidget(UbsApp(home: StaffDashboard(api: FakeStaffApi(true))));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('staff-filter-risk')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('risk-filter-option-baixo')).last);
    await tester.pumpAndSettle();

    final field = find.byKey(const Key('staff-filter-risk'));
    final selected = find.descendant(
        of: field, matching: find.byKey(const Key('risk-filter-option-baixo')));
    expect(selected, findsOneWidget);
    final fieldRect = tester.getRect(field);
    final selectedRect = tester.getRect(selected);
    expect(selectedRect.top, greaterThanOrEqualTo(fieldRect.top));
    expect(selectedRect.bottom, lessThanOrEqualTo(fieldRect.bottom));
    expect(find.descendant(of: selected, matching: find.text('Baixo')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resumo da enfermagem separa fluxo e riscos em ordem responsiva',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ApiService.session = const Session(
        'token', 'Enfermagem Fictícia', 'enfermagem', ['triage:write']);
    final keys = [
      const Key('nursing-risk-card-baixo'),
      const Key('nursing-risk-card-moderado'),
      const Key('nursing-risk-card-alto'),
      const Key('nursing-risk-card-muito_alto'),
    ];

    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester
        .pumpWidget(UbsApp(home: StaffDashboard(api: FakeStaffApi(true))));
    await tester.pumpAndSettle();
    final workflow =
        tester.getRect(find.byKey(const Key('nursing-workflow-summary')));
    final wide = keys.map((key) => tester.getRect(find.byKey(key))).toList();
    expect(wide.every((rect) => rect.top > workflow.bottom), isTrue);
    expect(wide.map((rect) => rect.top).toSet(), hasLength(1));
    expect(wide.map((rect) => rect.width).toSet(), hasLength(1));
    expect(wide[0].left, lessThan(wide[1].left));
    expect(wide[1].left, lessThan(wide[2].left));
    expect(wide[2].left, lessThan(wide[3].left));

    accessibility.setFontScale(1.3);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester
        .pumpWidget(UbsApp(home: StaffDashboard(api: FakeStaffApi(true))));
    await tester.pumpAndSettle();
    final compact = keys.map((key) => tester.getRect(find.byKey(key))).toList();
    expect(compact[0].top, compact[1].top);
    expect(compact[2].top, compact[3].top);
    expect(compact[2].top, greaterThan(compact[0].top));
    expect(compact.map((rect) => rect.width).toSet(), hasLength(1));
    expect(find.text('Aguardando triagem'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('professional_actions_remain_in_workflow_order', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ApiService.session = const Session(
        'token', 'Profissional Fictício', 'profissional', ['care:update']);
    await tester
        .pumpWidget(UbsApp(home: StaffDashboard(api: FakeStaffApi(true))));
    await tester.pumpAndSettle();
    expect(find.text('1. Chamar  2. Iniciar  3. Concluir'), findsOneWidget);
    final callY = tester.getTopLeft(find.text('Chamar paciente')).dy;
    final startY = tester.getTopLeft(find.text('Iniciar atendimento')).dy;
    expect(callY, lessThanOrEqualTo(startY));
    expect(tester.takeException(), isNull);
  });

  testWidgets('recepção mostra resumo, filtros e ações próprias',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeStaffApi(false);
    ApiService.session =
        const Session('token', 'Recepção Fictícia', 'recepcao', []);
    await tester.pumpWidget(UbsApp(home: StaffDashboard(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Painel da Recepção'), findsOneWidget);
    expect(find.text('Agendadas'), findsOneWidget);
    expect(find.text('Não compareceu'), findsWidgets);
    expect(find.byKey(const Key('staff-search')), findsOneWidget);
    expect(find.text('Paciente Fictício'), findsOneWidget);
    expect(find.text('Check-in'), findsWidgets);

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Check-in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Check-in'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
    await tester.pumpAndSettle();
    expect(api.checkIns, 1);
    expect(find.widgetWithText(OutlinedButton, 'Não compareceu'), findsNothing);
    expect(find.text('Painel da Recepção'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recepção oculta ausência em todos os estados não permitidos',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ApiService.session =
        const Session('token', 'Recepção Fictícia', 'recepcao', []);

    for (final status in [
      'em_espera',
      'em_triagem',
      'em_atendimento',
      'concluido',
      'cancelado',
      'falta',
    ]) {
      final api = FakeStaffApi(false)..receptionStatus = status;
      await tester.pumpWidget(UbsApp(home: StaffDashboard(api: api)));
      await tester.pumpAndSettle();
      expect(
          find.widgetWithText(OutlinedButton, 'Não compareceu'), findsNothing,
          reason: 'status $status');
    }
  });

  testWidgets('recepção confirma condição pendente após confirmação explícita',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeStaffApi(false, withPendingPcd: true);
    api.receptionStatus = 'em_espera';
    ApiService.session =
        const Session('token', 'Recepção Fictícia', 'recepcao', []);
    await tester.pumpWidget(UbsApp(home: StaffDashboard(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Detalhes'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aguardando confirmação presencial'),
        findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Confirmar'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar PCD?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
    await tester.pumpAndSettle();
    expect(api.priorityValidationCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recepção explica bloqueio antes do check-in', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeStaffApi(false, withPendingPcd: true);
    ApiService.session =
        const Session('token', 'Recepção Fictícia', 'recepcao', []);
    await tester.pumpWidget(UbsApp(home: StaffDashboard(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Detalhes'));
    await tester.pumpAndSettle();
    expect(find.text('Disponível após o check-in, enquanto aguarda triagem.'),
        findsOneWidget);
    expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Confirmar'),
            )
            .onPressed,
        isNull);
    expect(api.priorityValidationCalls, 0);
  });

  testWidgets('recepção exibe bloqueio devolvido pela API', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const message =
        'Somente condição prioritária pendente pode ser confirmada ou rejeitada';
    final api = FakeStaffApi(false,
        withPendingPcd: true, priorityValidationError: message)
      ..receptionStatus = 'em_espera';
    ApiService.session =
        const Session('token', 'Recepção Fictícia', 'recepcao', []);
    await tester.pumpWidget(UbsApp(home: StaffDashboard(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Detalhes'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Confirmar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
    await tester.pumpAndSettle();

    expect(api.priorityValidationCalls, 1);
    expect(find.text(message), findsOneWidget);
  });

  testWidgets('profissional usa somente quatro níveis manuais de risco',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeStaffApi(true);
    ApiService.session = const Session(
        'token', 'Enfermagem Fictícia', 'enfermagem', ['triage:write']);
    await tester.pumpWidget(UbsApp(home: StaffDashboard(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Painel da Enfermagem'), findsOneWidget);
    expect(find.text('Simulação acadêmica'), findsOneWidget);
    expect(find.text('Aguardando triagem'), findsWidgets);
    expect(find.text('Muito alto'), findsOneWidget);
    expect(find.byKey(const Key('staff-search')), findsNothing);

    await tester.ensureVisible(find.text('Classificar risco'));
    await tester.tap(find.text('Classificar risco'));
    await tester.pumpAndSettle();
    expect(find.text('Classificação de risco manual'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics &&
            widget.properties.label == 'Classificação de risco, obrigatória'),
        findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics &&
            widget.properties.label == 'Queixa principal, obrigatória'),
        findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics &&
            widget.properties.label == 'Sinais vitais, obrigatórios'),
        findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics &&
            widget.properties.label == 'Concluir triagem'),
        findsWidgets);
    expect(find.text('Muito alto'), findsWidgets);
    expect(find.text('Alto'), findsWidgets);
    expect(find.text('Moderado'), findsWidgets);
    expect(find.text('Baixo'), findsWidgets);
    expect(find.text('Queixa principal'), findsOneWidget);
    expect(find.text('Sinais vitais aferidos'), findsOneWidget);
    expect(find.textContaining('Diagnóstico'), findsNothing);
    await tester.tap(find.byKey(const Key('risk-option-baixo')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('triage-complaint')), 'Queixa fictícia.');
    await tester.enterText(
        find.byKey(const Key('triage-vital-signs')), 'PA fictícia 120/80.');
    await tester.tap(find.text('Salvar classificação'));
    await tester.pumpAndSettle();
    expect(api.classifications, 1);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('enfermagem habilita somente o primeiro paciente da fila',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ApiService.session = const Session(
        'token', 'Enfermagem Fictícia', 'enfermagem', ['triage:write']);
    final api = FakeStaffApi(true, withBlockedTriage: true);
    await tester.pumpWidget(UbsApp(home: StaffDashboard(api: api)));
    await tester.pumpAndSettle();

    final firstAction = find.byKey(const Key('triage-action-22'));
    final secondAction = find.byKey(const Key('triage-action-23'));
    expect(firstAction, findsOneWidget);
    expect(secondAction, findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.descendant(
                of: firstAction, matching: find.byType(FilledButton)))
            .onPressed,
        isNotNull);
    expect(
        tester
            .widget<FilledButton>(find.descendant(
                of: secondAction, matching: find.byType(FilledButton)))
            .onPressed,
        isNull);
    expect(find.text('Outro paciente está à frente na fila.'), findsOneWidget);

    await tester.ensureVisible(firstAction);
    await tester.tap(firstAction);
    await tester.pumpAndSettle();
    expect(find.text('Classificação de risco manual'), findsOneWidget);
    await tester.tap(find.byKey(const Key('risk-option-baixo')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('triage-complaint')), 'Queixa fictícia.');
    await tester.enterText(
        find.byKey(const Key('triage-vital-signs')), 'PA fictícia 120/80.');
    await tester.tap(find.text('Salvar classificação'));
    await tester.pumpAndSettle();

    expect(api.classifications, 1);
    expect(
        tester
            .widget<FilledButton>(find.descendant(
                of: find.byKey(const Key('triage-action-23')),
                matching: find.byType(FilledButton)))
            .onPressed,
        isNotNull);
    expect(find.byKey(const Key('triage-order-message-23')), findsNothing);
    expect(find.text('Reclassificar risco'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bloqueio da ordem da triagem permanece responsivo',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ApiService.session = const Session(
        'token', 'Enfermagem Fictícia', 'enfermagem', ['triage:write']);

    for (final size in const [
      Size(390, 900),
      Size(768, 900),
      Size(1366, 900),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(UbsApp(
          key: ValueKey(size),
          home:
              StaffDashboard(api: FakeStaffApi(true, withBlockedTriage: true))));
      await tester.pumpAndSettle();

      final message = find.byKey(const Key('triage-order-message-23'));
      await tester.ensureVisible(message);
      await tester.pumpAndSettle();
      final rect = tester.getRect(message);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(size.width));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('profissional chama e atende sem classificar risco',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeStaffApi(true);
    ApiService.session = const Session(
        'token', 'Profissional Fictício', 'profissional', ['care:update']);
    await tester.pumpWidget(UbsApp(home: StaffDashboard(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Painel do Profissional de Saúde'), findsOneWidget);
    expect(find.text('Classificar risco'), findsNothing);
    expect(find.text('Chamar paciente'), findsOneWidget);
    await tester.tap(find.text('Chamar paciente'));
    await tester.pumpAndSettle();
    expect(api.calls, 1);
    expect(tester.takeException(), isNull);
  });
}
