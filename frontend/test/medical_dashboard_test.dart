import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubs_saude/main.dart';
import 'package:ubs_saude/models/api_models.dart';
import 'package:ubs_saude/services/api_service.dart';

MedicalAppointment medicalAppointment(String status) =>
    MedicalAppointment.fromJson({
      'id': 7,
      'scheduled_at': DateTime.now()
          .copyWith(hour: 10, minute: 0, second: 0, millisecond: 0)
          .toIso8601String(),
      'patient': 'Paciente Triado',
      'age': 36,
      'specialty': 'Clínica Geral',
      'professional': 'Dr. Victor Almeida',
      'professional_id': 2,
      'status': status,
      'legal_priority': 'geral',
      'priority_reason': 'Sem prioridade legal',
      'risk_classification': 'alto',
      'risk_label': 'Alto',
      'triage_complaint': 'Dor fictícia.',
      'vital_signs': 'PA fictícia 120/80.',
      'triage_observation': 'Observação fictícia.',
      'care_summary': null,
    });

class FakeMedicalApi extends ApiService {
  MedicalAppointment item = medicalAppointment('em_triagem');
  int starts = 0, completions = 0, loads = 0;
  bool failQueue = false;
  String? submittedSummary;

  @override
  Future<List<MedicalAppointment>> medicalQueue() async {
    loads++;
    if (failQueue) {
      throw const ApiException('Falha temporária simulada.');
    }
    return [item];
  }

  @override
  Future<MedicalAppointment> medicalDetails(int id) async => item;

  @override
  Future<MedicalAppointment> startMedicalCare(int id) async {
    starts++;
    item = medicalAppointment('em_atendimento');
    return item;
  }

  @override
  Future<MedicalAppointment> completeMedicalCare(int id, String summary) async {
    completions++;
    submittedSummary = summary;
    item = medicalAppointment('concluido');
    return item;
  }
}

class PendingMedicalApi extends FakeMedicalApi {
  PendingMedicalApi() {
    item = medicalAppointment('em_atendimento');
  }

  final completion = Completer<MedicalAppointment>();

  @override
  Future<MedicalAppointment> completeMedicalCare(int id, String summary) {
    completions++;
    submittedSummary = summary;
    return completion.future;
  }
}

void main() {
  setUp(() {
    ApiService.session =
        const Session('token', 'Dr. Victor Almeida', 'medico', ['care:update']);
  });

  tearDown(() => ApiService.session = null);

  testWidgets('medical_role_opens_dedicated_dashboard', (tester) async {
    expect(homeForRole(), isA<MedicalDashboard>());
  });

  testWidgets('medical_dashboard_shows_ordered_care_information',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(768, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeMedicalApi();
    await tester.pumpWidget(UbsApp(home: MedicalDashboard(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Painel de Atendimento'), findsOneWidget);
    expect(find.text('Dr. Victor Almeida'), findsOneWidget);
    expect(find.byKey(const Key('medical-waiting-count')), findsOneWidget);
    expect(find.text('Paciente Triado'), findsOneWidget);
    expect(find.text('Risco: Alto'), findsOneWidget);
    expect(find.text('Prioridade: Sem prioridade legal'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(
        find.bySemanticsLabel(
            RegExp('Paciente Paciente Triado.*Classificação de risco: alto')),
        findsOneWidget);
    expect(
        find.bySemanticsLabel('Classificação de risco: alto'), findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics &&
            widget.properties.label == 'Iniciar atendimento'),
        findsWidgets);
    semantics.dispose();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'fila médica atualiza a cada cinco segundos e preserva dados em falha',
      (tester) async {
    final api = FakeMedicalApi();
    await tester.pumpWidget(UbsApp(home: MedicalDashboard(api: api)));
    await tester.pump();
    expect(api.loads, 1);
    expect(find.text('Paciente Triado'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(api.loads, 2);

    api.failQueue = true;
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(api.loads, 3);
    expect(find.text('Paciente Triado'), findsOneWidget);
    expect(find.text('Falha temporária simulada.'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    final loadsAfterDispose = api.loads;
    await tester.pump(const Duration(seconds: 5));
    expect(api.loads, loadsAfterDispose);
  });

  testWidgets('care_requires_summary_before_completion', (tester) async {
    await tester.binding.setSurfaceSize(const Size(768, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeMedicalApi();
    await tester.pumpWidget(UbsApp(home: MedicalDashboard(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Iniciar atendimento').first);
    await tester.pumpAndSettle();
    expect(find.text('Queixa principal'), findsOneWidget);

    await tester.tap(find.text('Iniciar atendimento').last);
    await tester.pumpAndSettle();
    expect(api.starts, 1);
    expect(find.byKey(const Key('medical-care-summary')), findsOneWidget);

    await tester.tap(find.text('Concluir atendimento'));
    await tester.pump();
    expect(find.text('Informe o resumo do atendimento.'), findsOneWidget);
    expect(api.completions, 0);

    await tester.enterText(
        find.byKey(const Key('medical-care-summary')), '   ');
    await tester.pump();
    expect(find.text('Informe o resumo do atendimento.'), findsOneWidget);
    expect(api.completions, 0);

    await tester.enterText(find.byKey(const Key('medical-care-summary')),
        'Resumo fictício do atendimento.');
    await tester.pump();
    expect(find.text('Informe o resumo do atendimento.'), findsNothing);
    await tester.tap(find.text('Concluir atendimento'));
    await tester.pumpAndSettle();
    expect(api.completions, 1);
    expect(api.submittedSummary, 'Resumo fictício do atendimento.');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('care_blocks_duplicate_completion_and_preserves_rejected_text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(768, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = PendingMedicalApi();
    await tester.pumpWidget(UbsApp(home: MedicalDashboard(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continuar atendimento'));
    await tester.pumpAndSettle();
    final summary = find.byKey(const Key('medical-care-summary'));
    await tester.enterText(summary, 'Conteúdo que deve permanecer.');

    final complete = find.text('Concluir atendimento');
    await tester.tap(complete);
    await tester.tap(complete, warnIfMissed: false);
    expect(api.completions, 1);

    api.completion.completeError(const ApiException('Recusa simulada.'));
    await tester.pumpAndSettle();
    expect(find.text('Recusa simulada.'), findsOneWidget);
    expect(tester.widget<TextFormField>(summary).controller?.text,
        'Conteúdo que deve permanecer.');
  });
}
