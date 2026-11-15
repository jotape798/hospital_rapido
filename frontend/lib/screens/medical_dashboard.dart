part of '../main.dart';

class MedicalDashboard extends StatefulWidget {
  const MedicalDashboard({super.key, this.api});
  final ApiService? api;

  @override
  State<MedicalDashboard> createState() => _MedicalDashboardState();
}

class _MedicalDashboardState extends State<MedicalDashboard> {
  late final ApiService api = widget.api ?? ApiService();
  final scrollController = ScrollController();
  Timer? refreshTimer;
  List<MedicalAppointment> queue = [];
  bool loading = true, working = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
    refreshTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => load(silent: true));
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> load({bool silent = false}) async {
    if (!mounted || working) return;
    working = true;
    try {
      final result = await api.medicalQueue();
      if (!mounted) return;
      setState(() {
        queue = result;
        error = null;
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) {
        refreshTimer?.cancel();
        await ApiService.logout();
        if (mounted) {
          Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
              (_) => false);
        }
        return;
      }
      if (silent && queue.isNotEmpty) return;
      setState(() {
        error = e.message;
        loading = false;
      });
      if (!silent) notice(context, e.message);
    } finally {
      working = false;
    }
  }

  Future<void> _logout() async {
    refreshTimer?.cancel();
    await ApiService.logout();
    if (mounted) {
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
    }
  }

  Future<void> _openCare(MedicalAppointment item) async {
    MedicalAppointment details;
    try {
      details = await api.medicalDetails(item.id);
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
      return;
    }
    if (!mounted) return;
    final completed = await showDialog<bool>(
        context: context,
        builder: (_) => _MedicalCareDialog(api: api, appointment: details));
    if (completed == true) {
      await load();
      if (mounted) {
        notice(context,
            'Atendimento concluído com sucesso. Status da consulta: Concluída.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => ResponsiveAppShell(
        wideNavigationMode: WideNavigationMode.contentOnly,
        title: 'Painel de Atendimento',
        subtitle: ApiService.session?.name,
        primaryAction: Wrap(spacing: 8, runSpacing: 8, children: [
          IconButton.filledTonal(
              tooltip: 'Atualizar fila',
              onPressed: working ? null : load,
              icon: const Icon(Icons.refresh)),
          OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text('Sair')),
        ]),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null && queue.isEmpty
                ? AppErrorState(
                    message: error!,
                    actionLabel: 'Tentar novamente',
                    onAction: load)
                : RefreshIndicator(
                    onRefresh: load,
                    child: ListView(
                        controller: scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          AppSurfaceCard(
                              child: Row(children: [
                            const Icon(Icons.groups_2_outlined, size: 32),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text('${queue.length}',
                                      key: const Key('medical-waiting-count'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w800)),
                                  const Text(
                                      'pacientes na fila de atendimento'),
                                ]))
                          ])),
                          const SizedBox(height: AppSpacing.md),
                          if (queue.isEmpty)
                            const AppEmptyState(
                                icon: Icons.event_available_outlined,
                                title: 'Nenhum paciente aguardando',
                                message:
                                    'A fila será atualizada quando a triagem encaminhar um paciente.')
                          else
                            for (final item in queue) ...[
                              _MedicalQueueCard(
                                  item: item, onOpen: () => _openCare(item)),
                              const SizedBox(height: AppSpacing.md),
                            ],
                        ])),
      );
}

class _MedicalQueueCard extends StatelessWidget {
  const _MedicalQueueCard({required this.item, required this.onOpen});
  final MedicalAppointment item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final time =
        '${item.scheduledAt.hour.toString().padLeft(2, '0')}:${item.scheduledAt.minute.toString().padLeft(2, '0')}';
    final inCare = item.status == 'em_atendimento';
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label:
          'Paciente ${item.patient}. Horário $time. Especialidade ${specialtyDisplayName(item.specialty)}. ${RiskClassification.resolve(item.risk).semanticLabel}. Prioridade ${item.priorityReason}. Status ${inCare ? 'Em atendimento' : 'Aguardando profissional'}',
      child: AppSurfaceCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(inCare ? Icons.medical_services_outlined : Icons.schedule,
              color: inCare ? green : blue),
          const SizedBox(width: AppSpacing.md),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(item.patient,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                Text('$time • ${specialtyDisplayName(item.specialty)}'),
              ])),
        ]),
        const SizedBox(height: AppSpacing.md),
        Wrap(spacing: 8, runSpacing: 8, children: [
          AppRiskIndicator(risk: item.risk),
          Chip(
              avatar: const Icon(Icons.priority_high, size: 18),
              label: Text('Prioridade: ${item.priorityReason}')),
          Chip(
              avatar: Icon(inCare ? Icons.play_circle : Icons.hourglass_top,
                  size: 18),
              label:
                  Text(inCare ? 'Em atendimento' : 'Aguardando profissional')),
        ]),
        const SizedBox(height: AppSpacing.md),
        Align(
            alignment: Alignment.centerRight,
            child: Semantics(
                button: true,
                label: inCare ? 'Continuar atendimento' : 'Iniciar atendimento',
                excludeSemantics: true,
                child: FilledButton.icon(
                    onPressed: onOpen,
                    icon: Icon(
                        inCare ? Icons.description_outlined : Icons.play_arrow),
                    label: Text(inCare
                        ? 'Continuar atendimento'
                        : 'Iniciar atendimento'))))
      ])),
    );
  }
}

class _MedicalCareDialog extends StatefulWidget {
  const _MedicalCareDialog({required this.api, required this.appointment});
  final ApiService api;
  final MedicalAppointment appointment;

  @override
  State<_MedicalCareDialog> createState() => _MedicalCareDialogState();
}

class _MedicalCareDialogState extends State<_MedicalCareDialog> {
  final formKey = GlobalKey<FormState>();
  final summary = TextEditingController();
  late MedicalAppointment appointment = widget.appointment;
  bool working = false;

  @override
  void dispose() {
    summary.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (working) return;
    setState(() => working = true);
    try {
      appointment = await widget.api.startMedicalCare(appointment.id);
      if (mounted) {
        setState(() {});
        notice(context,
            'Atendimento iniciado com sucesso. Status da consulta: Em atendimento.');
      }
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _complete() async {
    if (working) return;
    if (!formKey.currentState!.validate()) {
      announceImportant(context, 'Informe o resumo do atendimento.');
      return;
    }
    setState(() => working = true);
    try {
      await widget.api.completeMedicalCare(appointment.id, summary.text);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final started = appointment.status == 'em_atendimento';
    return AlertDialog(
      title: Text(appointment.patient),
      content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
              child: Form(
                  key: formKey,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Idade: ${appointment.age ?? 'não informada'}'),
                        Text(
                            'Especialidade: ${specialtyDisplayName(appointment.specialty)}'),
                        Text('Prioridade: ${appointment.priorityReason}'),
                        Align(
                            alignment: Alignment.centerLeft,
                            child: AppRiskIndicator(risk: appointment.risk)),
                        const Divider(height: 32),
                        Text('Queixa principal',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(appointment.complaint),
                        const SizedBox(height: AppSpacing.md),
                        Text('Sinais vitais',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(appointment.vitalSigns),
                        if (appointment.triageObservation != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text('Observação da triagem',
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(appointment.triageObservation!),
                        ],
                        if (started) ...[
                          const SizedBox(height: AppSpacing.lg),
                          Semantics(
                              textField: true,
                              label: 'Resumo do atendimento, obrigatório',
                              child: TextFormField(
                                  key: const Key('medical-care-summary'),
                                  controller: summary,
                                  autovalidateMode:
                                      AutovalidateMode.onUserInteraction,
                                  minLines: 3,
                                  maxLines: 6,
                                  maxLength: 2000,
                                  decoration: const InputDecoration(
                                      labelText: 'Resumo do atendimento'),
                                  validator: (value) =>
                                      (value ?? '').trim().length < 3
                                          ? 'Informe o resumo do atendimento.'
                                          : null)),
                        ]
                      ])))),
      actions: [
        TextButton(
            onPressed: working ? null : () => Navigator.pop(context),
            child: const Text('Fechar')),
        if (!started)
          Semantics(
              button: true,
              label: 'Iniciar atendimento',
              child: FilledButton.icon(
                  onPressed: working ? null : _start,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Iniciar atendimento')))
        else
          Semantics(
              button: true,
              label: 'Concluir atendimento',
              child: FilledButton.icon(
                  onPressed: working ? null : _complete,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Concluir atendimento'))),
      ],
    );
  }
}
