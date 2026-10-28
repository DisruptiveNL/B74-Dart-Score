import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/layout.dart';

/// The licenses of every package the app is built on.
///
/// Written out rather than handed to Flutter's own [LicensePage], which divides
/// itself into a list and a detail from 840 dp of width, stacks the detail over
/// the list in a way that fights the scroll, and appends to its list while the
/// registry is still being read. This one reads the registry once, then shows a
/// list that no longer moves under the finger, beside the package it opens on a
/// tablet and on top of it on a phone.
class LicensesScreen extends StatefulWidget {
  const LicensesScreen({super.key});

  @override
  State<LicensesScreen> createState() => _LicensesScreenState();
}

class _LicensesScreenState extends State<LicensesScreen> {
  /// Started once, in [initState]: a future created in `build` is created again
  /// by every rebuild, and a list that reloads while it is read is exactly the
  /// stutter this screen exists to avoid.
  late final Future<List<_PackageLicenses>> _future = _load();

  /// The package the detail pane shows. Only ever set on a tablet, where a tap
  /// opens the license beside the list instead of on top of it.
  _PackageLicenses? _selected;

  /// Reads the whole registry and groups it by package, sorted by name.
  ///
  /// An entry may belong to several packages and is then listed under each of
  /// them, the way the registry means it. Only the packages of
  /// [kDevelopmentOnlyPackages] are left out, and only as a name: an entry they
  /// share with a shipped package is still shown under that one.
  Future<List<_PackageLicenses>> _load() async {
    final byPackage = <String, List<LicenseEntry>>{};
    await for (final entry in LicenseRegistry.licenses) {
      for (final package in entry.packages) {
        if (kDevelopmentOnlyPackages.contains(package)) continue;
        byPackage.putIfAbsent(package, () => []).add(entry);
      }
    }

    return byPackage.entries
        .map((e) => _PackageLicenses(name: e.key, entries: e.value))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Opens [package]: beside the list where there is room for it, on top of it
  /// where there is not.
  void _open(BuildContext context, _PackageLicenses package) {
    if (isTabletLayout(context)) {
      setState(() => _selected = package);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PackageLicenseScreen(package: package),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final tablet = isTabletLayout(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.openSourceLicenses)),
      body: FutureBuilder<List<_PackageLicenses>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final packages = snap.data ?? const <_PackageLicenses>[];

          final list = ListView.builder(
            padding: tablet
                ? const EdgeInsets.symmetric(vertical: 8)
                : contentPadding(context, top: 8, bottom: 8),
            itemCount: packages.length,
            itemBuilder: (context, i) {
              final package = packages[i];
              return ListTile(
                title: Text(package.label(l)),
                subtitle: Text(l.licenseCount(package.entries.length)),
                selected: package == _selected,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _open(context, package),
              );
            },
          );

          if (!tablet) return list;

          final selected = _selected;
          return SidePaneLayout(
            side: InputSide.left,
            // A list of package names needs less room than the license it
            // opens, so the divider does not stand in the middle.
            fraction: 0.35,
            minPaneWidth: kMinListPaneWidth,
            primary: list,
            secondary: selected == null
                ? _EmptyLicensePane(message: l.licensesPickPackage)
                : _LicensePane(package: selected),
          );
        },
      ),
    );
  }
}

/// One package and every license entry the registry holds for it.
@immutable
class _PackageLicenses {
  final String name;
  final List<LicenseEntry> entries;

  const _PackageLicenses({required this.name, required this.entries});

  /// What the list writes on the tile.
  ///
  /// The engine registers one notice whose package name is a bare dash, which
  /// reads as an empty row rather than as a name. Such an entry keeps its
  /// license and gets a word instead of the punctuation.
  String label(AppLocalizations l) =>
      _named.hasMatch(name) ? name : l.licenseUnnamedComponent;

  static final _named = RegExp(r'[A-Za-z0-9]');
}

/// Packages that only ever run on a development machine: the linter, the icon
/// generator, the test and benchmark tooling of Flutter and of its engine.
///
/// They reach the registry because Flutter writes its `NOTICES` from the whole
/// dependency graph, not from what a build ships. Listing a package the app
/// does not carry is only noise, while dropping one it does carry would leave
/// an attribution out, so this set stays small: a name belongs here once
/// `flutter pub deps --no-dev` proves it absent from the shipped graph.
const kDevelopmentOnlyPackages = <String>{
  'benchmark',
  'checked_yaml',
  'cli_util',
  'devtools',
  'fake_async',
  'ffi_leak_tracker',
  'flutter_launcher_icons',
  'flutter_lints',
  'gtest-parallel',
  'image',
  'leak_tracker',
  'leak_tracker_flutter_testing',
  'leak_tracker_testing',
  'lints',
  'node_preamble',
  'sqflite_common_ffi',
  'test_api',
  'test_shaders',
  'web_test_fonts',
  'wycheproof_testvectors',
  'yapf',
  'yapf_diff',
};

// ── Detail ────────────────────────────────────────────────────────────────────

/// The licenses of one package, on the screen a phone opens for them.
class _PackageLicenseScreen extends StatelessWidget {
  final _PackageLicenses package;

  const _PackageLicenseScreen({required this.package});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(package.label(context.l10n))),
    body: _LicenseText(package: package),
  );
}

/// The licenses of one package inside the pane beside the list, under the name
/// of the package they belong to.
class _LicensePane extends StatelessWidget {
  final _PackageLicenses package;

  const _LicensePane({required this.package});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            package.label(context.l10n),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(child: _LicenseText(package: package)),
      ],
    );
  }
}

/// What the pane shows while no package is picked.
class _EmptyLicensePane extends StatelessWidget {
  final String message;

  const _EmptyLicensePane({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 40, color: cs.outline),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every license of a package, one paragraph at a time, with the entries parted
/// by a line where a package carries more than one.
class _LicenseText extends StatelessWidget {
  final _PackageLicenses package;

  const _LicenseText({required this.package});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final children = <Widget>[];
    for (var i = 0; i < package.entries.length; i++) {
      if (i > 0) children.add(const Divider(height: 32));
      for (final paragraph in package.entries[i].paragraphs) {
        children.add(
          Padding(
            // The registry states an indent per paragraph, and a centred one for
            // the headings a license opens with.
            padding: EdgeInsets.only(
              top: 8,
              left: paragraph.indent == LicenseParagraph.centeredIndent
                  ? 0
                  : 16.0 * paragraph.indent,
            ),
            child: Text(
              paragraph.text,
              textAlign: paragraph.indent == LicenseParagraph.centeredIndent
                  ? TextAlign.center
                  : TextAlign.start,
              style: theme.textTheme.bodySmall,
            ),
          ),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: children,
    );
  }
}
