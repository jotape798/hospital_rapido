part of '../main.dart';

class AppDestination {
  const AppDestination({
    required this.icon,
    required this.label,
    this.description,
    this.groupLabel,
    this.groupDescription,
    this.groupIcon,
    this.color,
  });

  final IconData icon;
  final String label;
  final String? description;
  final String? groupLabel;
  final String? groupDescription;
  final IconData? groupIcon;
  final Color? color;
}

enum WideNavigationMode { persistentRail, overlayDrawer, contentOnly }

class ResponsiveAppShell extends StatelessWidget {
  const ResponsiveAppShell({
    super.key,
    required this.body,
    required this.title,
    this.subtitle,
    this.destinations = const [],
    this.selectedIndex = 0,
    this.onDestinationSelected,
    this.primaryAction,
    this.wideNavigationMode = WideNavigationMode.persistentRail,
  });

  final Widget body;
  final String title;
  final String? subtitle;
  final List<AppDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int>? onDestinationSelected;
  final Widget? primaryAction;
  final WideNavigationMode wideNavigationMode;

  bool get _hasGroupedDestinations =>
      destinations.any((destination) => destination.groupLabel != null);

  @override
  Widget build(BuildContext context) => AppPage(
        showDecorativeWaves: false,
        reserveDecorativeFooter: false,
        child: LayoutBuilder(builder: (context, constraints) {
          final screenClass = screenClassForWidth(constraints.maxWidth);
          return AnimatedBuilder(
            animation: accessibility,
            builder: (context, child) => ColoredBox(
              color: accessibility.pageBackground,
              child: child!,
            ),
            child: screenClass == ScreenClass.wide
                ? _wide(context)
                : _compact(context),
          );
        }),
      );

  Widget _wide(BuildContext context) {
    final mode = destinations.isEmpty
        ? WideNavigationMode.contentOnly
        : wideNavigationMode;
    if (mode == WideNavigationMode.overlayDrawer) {
      return Stack(
        children: [
          _content(context, showBrand: true),
          Positioned(
            top: AppSpacing.sm,
            left: AppSpacing.md,
            child: IconButton.filledTonal(
              key: const Key('wide-navigation-menu-button'),
              tooltip: 'Abrir menu de navegação',
              constraints: const BoxConstraints.tightFor(
                width: AppSizes.minTouchTarget,
                height: AppSizes.minTouchTarget,
              ),
              onPressed: () => _showWideNavigation(context),
              icon: const Icon(Icons.menu),
            ),
          ),
        ],
      );
    }
    if (mode == WideNavigationMode.contentOnly) {
      return _content(context, showBrand: true);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        width: accessibility.fontSizeScale > 1.15 ? 300 : 280,
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.md),
        color: accessibility.highContrast
            ? Colors.black
            : Theme.of(context).colorScheme.surface,
        child: Column(
          children: [
            const BrandMark(compact: true),
            const SizedBox(height: AppSpacing.lg),
            if (destinations.isNotEmpty && _hasGroupedDestinations)
              Expanded(child: _groupedWideNavigation(context))
            else if (destinations.isNotEmpty)
              Expanded(
                child: NavigationRailTheme(
                    data: NavigationRailTheme.of(context).copyWith(
                      selectedLabelTextStyle: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                      unselectedLabelTextStyle:
                          Theme.of(context).textTheme.titleMedium,
                    ),
                    child: NavigationRail(
                      extended: true,
                      scrollable: true,
                      backgroundColor: Colors.transparent,
                      selectedIndex: selectedIndex,
                      onDestinationSelected: onDestinationSelected,
                      destinations: [
                        for (final destination in destinations)
                          NavigationRailDestination(
                            icon: Icon(destination.icon,
                                color: accessibility.highContrast
                                    ? null
                                    : destination.color),
                            label: Tooltip(
                              message: destination.label,
                              child: Text(destination.label,
                                  maxLines: 2, softWrap: true),
                            ),
                          ),
                      ],
                    )),
              ),
          ],
        ),
      ),
      Expanded(child: _content(context, showBrand: false)),
    ]);
  }

  Future<void> _showWideNavigation(BuildContext context) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fechar menu de navegação',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 180),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      ),
      pageBuilder: (dialogContext, animation, secondaryAnimation) => Align(
        alignment: Alignment.centerLeft,
        child: Material(
          key: const Key('wide-navigation-panel'),
          elevation: 12,
          color: accessibility.highContrast
              ? Colors.black
              : Theme.of(context).colorScheme.surface,
          child: SafeArea(
            child: SizedBox(
              width: 320,
              height: double.infinity,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(child: BrandMark(compact: true)),
                        IconButton(
                          tooltip: 'Fechar menu',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Expanded(
                      child: _hasGroupedDestinations
                          ? _groupedDrawerNavigation(dialogContext)
                          : ListView.builder(
                              itemCount: destinations.length,
                              itemBuilder: (context, index) =>
                                  _drawerDestination(dialogContext, index),
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

  Map<String, List<int>> _destinationGroups() {
    final groups = <String, List<int>>{};
    for (var index = 0; index < destinations.length; index++) {
      final label = destinations[index].groupLabel ?? 'Navegação';
      groups.putIfAbsent(label, () => <int>[]).add(index);
    }
    return groups;
  }

  Widget _groupedWideNavigation(BuildContext context) {
    final groups = _destinationGroups();
    return ListView(
      key: const Key('grouped-wide-navigation'),
      children: [
        for (final entry in groups.entries) ...[
          _navigationGroupHeader(context, entry.value.first),
          for (final index in entry.value)
            _wideGroupedDestination(context, index),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }

  Widget _navigationGroupHeader(BuildContext context, int firstIndex) {
    final destination = destinations[firstIndex];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.xs),
      child: Semantics(
        header: true,
        label:
            '${destination.groupLabel}. ${destination.groupDescription ?? ''}',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(destination.groupIcon ?? Icons.folder_outlined,
                size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(destination.groupLabel!,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  if (destination.groupDescription != null)
                    Text(destination.groupDescription!,
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wideGroupedDestination(BuildContext context, int index) {
    final destination = destinations[index];
    return Tooltip(
      message: _destinationTooltip(destination),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          key: Key('grouped-destination-$index'),
          minTileHeight: AppSizes.minTouchTarget,
          dense: true,
          selected: index == selectedIndex,
          selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: Icon(destination.icon,
              color: accessibility.highContrast ? null : destination.color),
          title: Semantics(
            label: _destinationSemanticLabel(destination),
            excludeSemantics: true,
            child: Text(destination.label, maxLines: 2, softWrap: true),
          ),
          subtitle: destination.description == null
              ? null
              : Text(destination.description!,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: onDestinationSelected == null
              ? null
              : () => onDestinationSelected!(index),
        ),
      ),
    );
  }

  Widget _groupedDrawerNavigation(BuildContext dialogContext) {
    final groups = _destinationGroups();
    return ListView(
      key: const Key('grouped-compact-navigation'),
      children: [
        for (final entry in groups.entries)
          _drawerGroup(dialogContext, entry.value),
      ],
    );
  }

  Widget _drawerGroup(BuildContext dialogContext, List<int> indices) {
    final first = destinations[indices.first];
    return ExpansionTile(
      key: Key('navigation-group-${first.groupLabel}'),
      initiallyExpanded: indices.contains(selectedIndex),
      leading: Icon(first.groupIcon ?? Icons.folder_outlined),
      title: Text(first.groupLabel!,
          style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: first.groupDescription == null
          ? null
          : Text(first.groupDescription!, maxLines: 2, softWrap: true),
      children: [
        for (final index in indices)
          _drawerDestination(dialogContext, index, grouped: true),
      ],
    );
  }

  Widget _drawerDestination(BuildContext dialogContext, int index,
      {bool grouped = false}) {
    final destination = destinations[index];
    return Tooltip(
      message: _destinationTooltip(destination),
      child: ListTile(
        contentPadding: grouped
            ? const EdgeInsetsDirectional.only(start: 36, end: 12)
            : null,
        minTileHeight: AppSizes.minTouchTarget * accessibility.fontSizeScale,
        selected: index == selectedIndex,
        leading: Icon(destination.icon,
            color: accessibility.highContrast ? null : destination.color),
        title: Semantics(
          label: _destinationSemanticLabel(destination),
          excludeSemantics: true,
          child: Text(destination.label, maxLines: 2, softWrap: true),
        ),
        subtitle: destination.description == null
            ? null
            : Text(destination.description!, maxLines: 3, softWrap: true),
        onTap: onDestinationSelected == null
            ? null
            : () {
                Navigator.pop(dialogContext);
                onDestinationSelected!(index);
              },
      ),
    );
  }

  String _destinationTooltip(AppDestination destination) =>
      destination.description == null
          ? destination.label
          : '${destination.label}: ${destination.description}';

  String _destinationSemanticLabel(AppDestination destination) =>
      'Seção ${destination.label}${destination.description == null ? '' : '. ${destination.description}'}';

  Widget _compact(BuildContext context) {
    if (wideNavigationMode == WideNavigationMode.overlayDrawer &&
        destinations.isNotEmpty) {
      return Stack(children: [
        _content(context, showBrand: true),
        Positioned(
          top: AppSpacing.sm,
          left: AppSpacing.md,
          child: IconButton.filledTonal(
            key: const Key('wide-navigation-menu-button'),
            tooltip: 'Abrir menu de navegação',
            constraints: const BoxConstraints.tightFor(
              width: AppSizes.minTouchTarget,
              height: AppSizes.minTouchTarget,
            ),
            onPressed: () => _showWideNavigation(context),
            icon: const Icon(Icons.menu),
          ),
        ),
      ]);
    }
    return Column(
      children: [
        Expanded(child: _content(context, showBrand: true)),
        if (destinations.length > 5)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
            child: Tooltip(
              message: destinations[selectedIndex].label,
              child: OutlinedButton.icon(
                key: const Key('responsive-compact-destination-picker'),
                onPressed: () => _showWideNavigation(context),
                icon: const Icon(Icons.menu),
                label: Semantics(
                  label:
                      'Abrir menu de seções. Seção atual: ${destinations[selectedIndex].label}',
                  excludeSemantics: true,
                  child: Text(destinations[selectedIndex].label,
                      maxLines: 2, softWrap: true),
                ),
              ),
            ),
          )
        else if (destinations.isNotEmpty)
          NavigationBar(
            height: 72,
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            destinations: [
              for (final destination in destinations)
                NavigationDestination(
                  icon: Icon(destination.icon,
                      color: accessibility.highContrast
                          ? null
                          : destination.color),
                  label: destination.label,
                ),
            ],
          ),
      ],
    );
  }

  Widget _content(BuildContext context, {required bool showBrand}) =>
      LayoutBuilder(builder: (context, constraints) {
        final reducedHeight = constraints.maxHeight < 700;
        return Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  reducedHeight ? 64 : 72,
                  AppSpacing.lg,
                  reducedHeight ? AppSpacing.sm : AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showBrand) ...[
                    const BrandMark(compact: true),
                    SizedBox(
                        height: reducedHeight ? AppSpacing.sm : AppSpacing.lg),
                  ],
                  ResponsivePageHeader(
                    title: title,
                    subtitle: subtitle,
                    primaryAction: primaryAction,
                  ),
                  SizedBox(
                      height: reducedHeight ? AppSpacing.sm : AppSpacing.lg),
                  Expanded(child: body),
                ],
              ),
            ),
          ),
        );
      });
}

class ResponsivePageHeader extends StatelessWidget {
  const ResponsivePageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.primaryAction,
  });

  final String title;
  final String? subtitle;
  final Widget? primaryAction;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(subtitle!, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ],
        );
        if (constraints.maxWidth < AppBreakpoints.compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              text,
              if (primaryAction != null) ...[
                const SizedBox(height: AppSpacing.md),
                primaryAction!,
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: text),
            if (primaryAction != null) ...[
              const SizedBox(width: AppSpacing.lg),
              primaryAction!,
            ],
          ],
        );
      });
}
