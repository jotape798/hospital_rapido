part of '../main.dart';

class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.child,
    this.showDecorativeWaves = false,
    this.reserveDecorativeFooter = false,
  });
  final Widget child;
  final bool showDecorativeWaves;
  final bool reserveDecorativeFooter;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: accessibility,
      builder: (context, _) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(accessibility.fontSizeScale)),
          child: Scaffold(
              backgroundColor: accessibility.pageBackground,
              body: LayoutBuilder(builder: (context, constraints) {
                final decorativeFooterHeight =
                    showDecorativeWaves && reserveDecorativeFooter ? 48.0 : 0.0;
                return Stack(fit: StackFit.expand, children: [
                  if (showDecorativeWaves)
                    reserveDecorativeFooter
                        ? const Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: 48,
                            child: IgnorePointer(
                                child: WaveBackground(footerMode: true)))
                        : const Positioned.fill(
                            child: IgnorePointer(child: WaveBackground())),
                  Positioned.fill(
                      bottom: decorativeFooterHeight,
                      child: SafeArea(
                          key: const Key('app-page-content-safe-area'),
                          child: FocusTraversalGroup(
                              child: Stack(children: [
                            child,
                            const Positioned(
                                top: 12,
                                right: 16,
                                left: 16,
                                child: Align(
                                    alignment: Alignment.centerRight,
                                    child: AccessibilityMenu()))
                          ]))))
                ]);
              }))));
}

class AccessibilityMenu extends StatefulWidget {
  const AccessibilityMenu({super.key});
  @override
  State<AccessibilityMenu> createState() => _AccessibilityMenuState();
}

class _AccessibilityMenuState extends State<AccessibilityMenu> {
  bool open = false;

  void _setReaderSupport(BuildContext context, bool value) {
    accessibility.setReaderSupport(value);
    SemanticsService.sendAnnouncement(
        View.of(context),
        value
            ? 'Otimização para leitor de tela ativada'
            : 'Otimização para leitor de tela desativada',
        Directionality.of(context));
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final menuLabel = open
        ? 'Fechar preferências de acessibilidade'
        : 'Abrir preferências de acessibilidade';
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Semantics(
              key: const Key('accessibility-menu-semantics'),
              expanded: open,
              child: compact
                  ? IconButton.filled(
                      key: const Key('accessibility-menu-button'),
                      tooltip: menuLabel,
                      onPressed: () => setState(() => open = !open),
                      icon: const Icon(Icons.accessibility_new))
                  : FilledButton.icon(
                      key: const Key('accessibility-menu-button'),
                      onPressed: () => setState(() => open = !open),
                      icon: const Icon(Icons.accessibility_new),
                      label: Semantics(
                          label: menuLabel,
                          excludeSemantics: true,
                          child:
                              const Text('Preferências de acessibilidade')))),
          if (open)
            Card(
                child: SizedBox(
                    width: (MediaQuery.sizeOf(context).width - 32)
                        .clamp(0, 310)
                        .toDouble(),
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Opções de acessibilidade',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 12),
                              const Text('Tamanho da fonte',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              Row(children: [
                                OutlinedButton(
                                    key: const Key(
                                        'accessibility-font-decrease'),
                                    onPressed: accessibility.decreaseFont,
                                    child: Semantics(
                                        label: 'Diminuir tamanho da fonte',
                                        excludeSemantics: true,
                                        child: const Text('A-'))),
                                Expanded(
                                    child: TextButton(
                                        onPressed: () =>
                                            accessibility.setFontScale(1),
                                        child: const Text('A'))),
                                OutlinedButton(
                                    onPressed: accessibility.increaseFont,
                                    child: Semantics(
                                        label: 'Aumentar tamanho da fonte',
                                        excludeSemantics: true,
                                        child: const Text('A+')))
                              ]),
                              SwitchListTile(
                                  value: accessibility.highContrast,
                                  onChanged: accessibility.setContrast,
                                  title: const Text('Alto contraste'),
                                  subtitle: const Text(
                                      'Preto, branco e amarelo em toda a interface')),
                              Semantics(
                                  key: const Key('screen-reader-toggle'),
                                  container: true,
                                  toggled: accessibility.screenReaderSupport,
                                  label: 'Otimizar para leitor de tela',
                                  hint:
                                      'Melhora a leitura do sistema por Narrador, TalkBack e leitores de tela compatíveis',
                                  onTap: () => _setReaderSupport(context,
                                      !accessibility.screenReaderSupport),
                                  excludeSemantics: true,
                                  child: SwitchListTile(
                                      value: accessibility.screenReaderSupport,
                                      onChanged: (value) =>
                                          _setReaderSupport(context, value),
                                      title: const Text(
                                          'Otimizar para leitor de tela'),
                                      subtitle: const Text(
                                          'Melhora a leitura do sistema por Narrador, TalkBack e leitores de tela compatíveis'))),
                              Text(
                                  'Use TAB para navegar e ENTER para confirmar.',
                                  style: Theme.of(context).textTheme.bodySmall)
                            ]))))
        ]);
  }
}

class WaveBackground extends StatelessWidget {
  const WaveBackground({super.key, this.footerMode = false});
  final bool footerMode;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
      child: IgnorePointer(
          child: AnimatedBuilder(
              animation: accessibility,
              builder: (context, _) => CustomPaint(
                  painter: WavePainter(
                      highContrast: accessibility.highContrast,
                      footerMode: footerMode)))));
}

class WavePainter extends CustomPainter {
  WavePainter({this.highContrast = false, this.footerMode = false});
  final bool highContrast;
  final bool footerMode;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size,
        Paint()..color = highContrast ? Colors.black : pageBackgroundColor);
    final green = Path()
      ..moveTo(0, size.height * (footerMode ? .28 : .88))
      ..quadraticBezierTo(
          size.width * .22,
          size.height * (footerMode ? .02 : .78),
          size.width * .50,
          size.height * (footerMode ? .28 : .88))
      ..quadraticBezierTo(
          size.width * .78,
          size.height * (footerMode ? .02 : .78),
          size.width,
          size.height * (footerMode ? .18 : .84))
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(green,
        Paint()..color = highContrast ? Colors.black : const Color(0xFF19A77E));
    final blue = Path()
      ..moveTo(0, size.height * (footerMode ? .88 : .98))
      ..quadraticBezierTo(
          size.width * .24,
          size.height * (footerMode ? .60 : .91),
          size.width * .55,
          size.height * (footerMode ? .88 : .98))
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    if (highContrast) {
      canvas.drawPath(
          green,
          Paint()
            ..color = Colors.yellow
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
    canvas.drawPath(blue,
        Paint()..color = highContrast ? Colors.black : const Color(0xFF0879BE));
  }

  @override
  bool shouldRepaint(covariant WavePainter oldDelegate) =>
      oldDelegate.highContrast != highContrast ||
      oldDelegate.footerMode != footerMode;
}

class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.child,
    this.topAligned = false,
    this.cardKey,
  });
  final Widget child;
  final bool topAligned;
  final Key? cardKey;

  @override
  Widget build(BuildContext context) {
    final compact = screenClassOf(context) == ScreenClass.compact;
    final card = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
            key: cardKey,
            child: Padding(
                padding: EdgeInsets.all(compact ? 20 : (topAligned ? 24 : 30)),
                child: child)));
    if (!topAligned) {
      return Center(
          child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 82, 20, 30), child: card));
    }
    final size = MediaQuery.sizeOf(context);
    final top = compact
        ? 72.0
        : size.height >= 900
            ? 72.0
            : 40.0;
    return SingleChildScrollView(
        key: const Key('top-aligned-auth-scroll'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(20, top, 20, size.height < 700 ? 20 : 32),
        child: Align(alignment: Alignment.topCenter, child: card));
  }
}

class FormTypography extends StatelessWidget {
  const FormTypography({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final input = theme.inputDecorationTheme;
    final body = theme.textTheme.bodyLarge;
    final guidance = theme.textTheme.bodySmall;
    return Theme(
        data: theme.copyWith(
            textTheme: theme.textTheme.copyWith(
                titleMedium: theme.textTheme.bodyLarge?.copyWith(fontSize: 16)),
            inputDecorationTheme: input.copyWith(
                labelStyle: (input.labelStyle ?? body)?.copyWith(fontSize: 16),
                hintStyle: (input.hintStyle ?? body)?.copyWith(fontSize: 16),
                helperStyle: guidance?.copyWith(fontSize: 14, height: 1.35),
                errorStyle: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 14,
                    color: theme.colorScheme.error,
                    height: 1.35))),
        child: child);
  }
}

class InfoPanel extends StatelessWidget {
  const InfoPanel({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: accessibility.highContrast
              ? Colors.black
              : const Color(0xFFE8F1FF),
          border: Border.all(
              color: accessibility.highContrast ? Colors.yellow : blue,
              width: accessibility.highContrast ? 2 : 0),
          borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(icon, color: accessibility.highContrast ? Colors.yellow : blue),
        const SizedBox(width: 10),
        Expanded(child: Text(text))
      ]));
}

Widget field(TextEditingController controller, String label, IconData icon,
        {String? hint,
        String? semanticLabel,
        bool requiredField = false,
        String? errorText,
        bool number = false,
        bool secret = false,
        Widget? suffix,
        String? Function(String?)? validator,
        List<TextInputFormatter>? inputFormatters,
        Iterable<String>? autofillHints,
        TextInputType? keyboardType,
        TextInputAction textInputAction = TextInputAction.next,
        ValueChanged<String>? onFieldSubmitted}) =>
    Semantics(
        textField: true,
        label: semanticLabel ?? '$label${requiredField ? ', obrigatório' : ''}',
        hint: accessibility.screenReaderSupport ? hint : null,
        child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextFormField(
                controller: controller,
                keyboardType: keyboardType ??
                    (number ? TextInputType.number : TextInputType.text),
                inputFormatters: inputFormatters ??
                    (number ? [FilteringTextInputFormatter.digitsOnly] : null),
                validator: validator,
                forceErrorText: errorText,
                errorBuilder: (context, error) => Semantics(
                    liveRegion: true,
                    child: Text(error,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
                enableSuggestions: false,
                autocorrect: false,
                autofillHints: autofillHints,
                textInputAction: textInputAction,
                onFieldSubmitted: onFieldSubmitted,
                obscureText: secret,
                decoration: InputDecoration(
                    labelText: label,
                    errorMaxLines: 4,
                    hintText: hint,
                    prefixIcon: ExcludeSemantics(child: Icon(icon)),
                    suffixIcon: suffix))));
