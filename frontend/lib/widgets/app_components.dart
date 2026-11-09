part of '../main.dart';

class AppActionButton extends StatelessWidget {
  const AppActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.destructive = false,
    this.expand = false,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool destructive;
  final bool expand;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = destructive
        ? FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          )
        : null;
    final accessibleLabel =
        busy ? '${semanticLabel ?? label}, carregando' : semanticLabel ?? label;
    final button = FilledButton(
      style: style,
      onPressed: busy ? null : onPressed,
      child: Semantics(
        label: accessibleLabel,
        liveRegion: busy,
        excludeSemantics: true,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (busy)
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon ?? Icons.arrow_forward),
          const SizedBox(width: AppSpacing.sm),
          Flexible(child: Text(busy ? 'Aguarde…' : label)),
        ]),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle!),
                ],
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: AppSpacing.md),
            action!,
          ],
        ],
      );
}

class AppSurfaceCard extends StatelessWidget {
  const AppSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Card(
        shape: Theme.of(context).cardTheme.shape,
        child: Padding(padding: padding, child: child),
      );
}

class AvailabilitySlotCard extends StatelessWidget {
  const AvailabilitySlotCard({
    super.key,
    required this.slot,
    required this.selected,
    required this.onPressed,
  });

  final Slot slot;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = slot.selectable && onPressed != null;
    final label = selected
        ? 'Selecionado'
        : slot.selectable
            ? 'Disponível'
            : 'Indisponível';
    final apiLabel = slot.label.trim();
    final detail = !selected &&
            apiLabel.isNotEmpty &&
            apiLabel.toLowerCase() != label.toLowerCase()
        ? apiLabel
        : null;
    final icon = selected
        ? Icons.check_circle_outline
        : slot.selectable
            ? Icons.event_available_outlined
            : Icons.event_busy_outlined;
    final state = selected
        ? _AvailabilityVisualState.selected
        : slot.selectable
            ? _AvailabilityVisualState.available
            : _AvailabilityVisualState.unavailable;
    final palette = _availabilityPalette(context, state);
    final borderWidth = accessibility.highContrast || selected ? 2.0 : 1.0;
    final time =
        '${slot.scheduledAt.hour.toString().padLeft(2, '0')}:${slot.scheduledAt.minute.toString().padLeft(2, '0')}';

    return Semantics(
      container: true,
      button: slot.selectable,
      enabled: enabled,
      selected: selected,
      label:
          '$time, $label, ${slot.selectable ? '1 vaga disponível' : '0 vagas disponíveis'}${detail == null ? '' : ', $detail'}',
      onTap: enabled ? onPressed : null,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.border, width: borderWidth),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: enabled ? onPressed : null,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(icon, color: palette.foreground),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(time,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                      color: palette.foreground,
                                      fontWeight: FontWeight.w800)),
                          Text(label,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: palette.foreground,
                                      fontWeight:
                                          selected ? FontWeight.w700 : null)),
                          if (detail != null)
                            Text(detail,
                                maxLines: 2,
                                softWrap: true,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: palette.foreground)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AvailabilityLegend extends StatelessWidget {
  const AvailabilityLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: [
        _AvailabilityLegendItem(
            icon: Icons.event_available_outlined,
            label: 'Disponível',
            state: _AvailabilityVisualState.available),
        _AvailabilityLegendItem(
            icon: Icons.event_busy_outlined,
            label: 'Indisponível',
            state: _AvailabilityVisualState.unavailable),
        _AvailabilityLegendItem(
            icon: Icons.check_circle_outline,
            label: 'Selecionado',
            state: _AvailabilityVisualState.selected),
      ],
    );
  }
}

class _AvailabilityLegendItem extends StatelessWidget {
  const _AvailabilityLegendItem(
      {required this.icon, required this.label, required this.state});

  final IconData icon;
  final String label;
  final _AvailabilityVisualState state;

  @override
  Widget build(BuildContext context) {
    final palette = _availabilityPalette(context, state);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.border),
          ),
          child: Icon(icon, size: 18, color: palette.foreground),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: palette.foreground)),
      ],
    );
  }
}

enum _AvailabilityVisualState { available, unavailable, selected }

({Color foreground, Color background, Color border}) _availabilityPalette(
    BuildContext context, _AvailabilityVisualState state) {
  final colors = Theme.of(context).colorScheme;
  if (accessibility.highContrast) {
    final accent = state == _AvailabilityVisualState.unavailable
        ? Colors.white
        : colors.primary;
    return (foreground: accent, background: colors.surface, border: accent);
  }

  final foreground = switch (state) {
    _AvailabilityVisualState.available => green,
    _AvailabilityVisualState.unavailable => colors.error,
    _AvailabilityVisualState.selected => colors.primary,
  };
  final background = Color.alphaBlend(
      foreground.withValues(
          alpha: state == _AvailabilityVisualState.selected ? .14 : .08),
      colors.surface);
  return (foreground: foreground, background: background, border: foreground);
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.event_available_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => _AppFeedbackState(
        icon: icon,
        title: title,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
      );
}

enum StatusTone { neutral, info, success, warning, danger }

StatusTone statusToneFor(String status) => switch (status) {
      'concluido' => StatusTone.success,
      'cancelado' || 'falta' => StatusTone.danger,
      'em_atendimento' || 'em_triagem' => StatusTone.info,
      'em_espera' => StatusTone.warning,
      _ => StatusTone.neutral,
    };

class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge({
    super.key,
    required this.label,
    required this.tone,
    this.semanticLabel,
  });

  final String label;
  final StatusTone tone;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground, icon) = switch (tone) {
      StatusTone.info => (
          colors.primaryContainer,
          colors.onPrimaryContainer,
          Icons.info_outline
        ),
      StatusTone.success => (
          const Color(0xFFDFF4E8),
          const Color(0xFF155D36),
          Icons.check_circle_outline
        ),
      StatusTone.warning => (
          const Color(0xFFFFF0C7),
          const Color(0xFF6D4C00),
          Icons.schedule_outlined
        ),
      StatusTone.danger => (
          colors.errorContainer,
          colors.onErrorContainer,
          Icons.error_outline
        ),
      StatusTone.neutral => (
          colors.surfaceContainerHighest,
          colors.onSurface,
          Icons.event_outlined
        ),
    };
    final effectiveBackground =
        accessibility.highContrast ? Colors.black : background;
    final effectiveForeground =
        accessibility.highContrast ? Colors.yellow : foreground;

    return Semantics(
      container: true,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: effectiveBackground,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(
              color: effectiveForeground,
              width: accessibility.highContrast ? 2 : 1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: effectiveForeground),
              const SizedBox(width: 5),
              Flexible(
                child: Text(label,
                    style: TextStyle(
                        color: effectiveForeground,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppRiskIndicator extends StatelessWidget {
  const AppRiskIndicator({
    super.key,
    required this.risk,
    this.prefix = true,
  });

  final String? risk;
  final bool prefix;

  @override
  Widget build(BuildContext context) {
    final presentation = RiskClassification.resolve(risk);
    final highContrast = accessibility.highContrast;
    return Semantics(
      container: true,
      label: presentation.semanticLabel,
      excludeSemantics: true,
      child: DecoratedBox(
        key: Key('risk-indicator-${presentation.code ?? 'unknown'}'),
        decoration: BoxDecoration(
          color: presentation.background,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(
            color: highContrast
                ? presentation.foreground
                : presentation.background,
            width: highContrast ? 3 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(presentation.icon,
                  key: Key('risk-icon-${presentation.code ?? 'unknown'}'),
                  size: 18,
                  color: presentation.foreground),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  prefix && presentation.code != null
                      ? 'Risco: ${presentation.label}'
                      : presentation.label,
                  softWrap: true,
                  style: TextStyle(
                    color: presentation.foreground,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppRiskSelector extends StatelessWidget {
  const AppRiskSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: value,
      validator: (selected) => selected == null
          ? 'Selecione conscientemente a classificação de risco.'
          : null,
      builder: (field) => Semantics(
        container: true,
        label: 'Classificação de risco, obrigatória',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nível de risco',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            LayoutBuilder(builder: (context, constraints) {
              final choices = [
                for (final code in RiskClassification.values)
                  _RiskChoice(
                    presentation: RiskClassification.resolve(code),
                    selected: field.value == code,
                    onSelected: () {
                      field.didChange(code);
                      onChanged(code);
                    },
                  ),
              ];
              final wide = constraints.maxWidth >= 720;
              if (wide) return _riskChoiceRow(choices);
              return Column(children: [
                _riskChoiceRow(choices.take(2).toList()),
                const SizedBox(height: AppSpacing.sm),
                _riskChoiceRow(choices.skip(2).toList()),
              ]);
            }),
            if (field.hasError) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(field.errorText!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _riskChoiceRow(List<Widget> choices) => Row(children: [
        for (var index = 0; index < choices.length; index++) ...[
          if (index > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(child: choices[index]),
        ],
      ]);
}

class _RiskChoice extends StatelessWidget {
  const _RiskChoice({
    required this.presentation,
    required this.selected,
    required this.onSelected,
  });

  final RiskPresentation presentation;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final highContrast = accessibility.highContrast;
    final accent = highContrast
        ? Colors.yellow
        : switch (presentation.code) {
            'baixo' => const Color(0xFF1B5E20),
            'moderado' => const Color(0xFF6D4C00),
            'alto' => const Color(0xFF8A3D00),
            _ => const Color(0xFFB71C1C),
          };
    final background = highContrast
        ? Colors.black
        : selected
            ? Color.alphaBlend(
                presentation.background.withValues(alpha: .14), Colors.white)
            : Colors.white;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${presentation.semanticLabel}. ${selected ? 'Selecionado' : 'Não selecionado'}',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: FilterChip(
          key: Key('risk-option-${presentation.code}'),
          selected: selected,
          showCheckmark: true,
          checkmarkColor: accent,
          avatar: Icon(presentation.icon, size: 18, color: accent),
          label: Text(presentation.label),
          labelStyle: TextStyle(color: accent, fontWeight: FontWeight.w800),
          backgroundColor: background,
          selectedColor: background,
          side: BorderSide(
            color: accent,
            width: selected || highContrast ? 3 : 1.5,
          ),
          elevation: selected ? 2 : 0,
          onSelected: (_) => onSelected(),
        ),
      ),
    );
  }
}

class AppRiskFilterItem extends StatelessWidget {
  const AppRiskFilterItem({super.key, required this.risk});

  final String risk;

  @override
  Widget build(BuildContext context) {
    final presentation = RiskClassification.resolve(risk);
    final foreground = accessibility.highContrast
        ? Colors.yellow
        : switch (presentation.code) {
            'baixo' => const Color(0xFF1B5E20),
            'moderado' => const Color(0xFF6D4C00),
            'alto' => const Color(0xFF8A3D00),
            _ => const Color(0xFFB71C1C),
          };
    return Semantics(
      label: presentation.semanticLabel,
      excludeSemantics: true,
      child: Row(
        key: Key('risk-filter-option-${presentation.code}'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(presentation.icon, size: 20, color: foreground),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              presentation.label,
              maxLines: 2,
              softWrap: true,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.message,
    this.actionLabel = 'Tentar novamente',
    this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => _AppFeedbackState(
        icon: Icons.error_outline,
        title: 'Não foi possível carregar',
        message: message,
        actionLabel: onAction == null ? null : actionLabel,
        onAction: onAction,
      );
}

class _AppFeedbackState extends StatelessWidget {
  const _AppFeedbackState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 40),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(message, textAlign: TextAlign.center),
                    if (actionLabel != null && onAction != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      AppActionButton(
                        label: actionLabel!,
                        onPressed: onAction,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
