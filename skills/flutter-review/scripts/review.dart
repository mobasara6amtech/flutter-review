// flutter-review: snapshot-based, layer-by-layer review of a feature's changes.
// Pure Dart (dart:io only). Run from anywhere inside a git repo:
//   dart run review.dart <command> ...
//
// Commands:
//   start <name>                         save baseline snapshot
//   prepare review [name] [--since <rev>] snapshot now, diff baseline -> now, write report
//   prepare recheck [name]               snapshot now, diff last review -> now, write report
//   list                                 all baselines with date and changed-file count
//   done <name>                          delete the feature's refs
//   summary <ref-a> <ref-b>              layer table + file list
//   layer <n> <ref-a> <ref-b> [--full]   full diff of one layer
//
// Exit code 3 = no baseline found (caller must ask the user what to diff against).

import 'dart:convert';
import 'dart:io';

// ============================================================================
// LAYER RULES — edit freely.
// Matching is done on '/' + lowercase repo-relative path, so '/models/' also
// matches a top-level 'models/' folder. Rules are checked in `checkOrder`;
// the first layer with a matching rule wins. A file that matches nothing goes
// to Config & Assets if it is not a .dart file, otherwise to Unclassified.
// ============================================================================
const layerNames = <int, String>{
  1: 'Models',
  2: 'Repository',
  3: 'Service',
  4: 'Controller',
  5: 'UI',
  6: 'Helper & Util',
  7: 'Config & Assets',
  8: 'Tests',
  9: 'Generated',
  10: 'Unclassified',
};

// contains: path substrings; suffixes: path endings.
const layerRules = <int, Map<String, List<String>>>{
  9: {
    'suffixes': ['.g.dart', '.freezed.dart', '.gr.dart', '.mocks.dart', '/pubspec.lock'],
  },
  8: {
    'contains': ['/test/', '/integration_test/'],
  },
  1: {
    'contains': ['/models/', '/model/'],
  },
  2: {
    'contains': ['/repositories/', '/repository/', '/repo/'],
  },
  3: {
    'contains': ['/services/', '/service/'],
  },
  4: {
    'contains': ['/controllers/', '/controller/', '/bloc/', '/cubit/', '/provider/'],
  },
  5: {
    'contains': ['/screens/', '/screen/', '/view/', '/views/', '/widgets/', '/widget/', '/pages/'],
  },
  6: {
    'contains': ['/helper/', '/helpers/', '/util/', '/utils/', '/common/'],
  },
  7: {
    'suffixes': ['/pubspec.yaml'],
    'contains': ['/assets/', '/android/', '/ios/'],
  },
};

// Generated and Tests first, then layers in display order.
const checkOrder = [9, 8, 1, 2, 3, 4, 5, 6, 7];

// Layers where `*interface*` files are listed before their implementation.
const interfaceFirstLayers = {2, 3};

const contextLines = 3;
const refRoot = 'refs/flutter-review';
const reportDir = '.code-review';
// ============================================================================

int classify(String path) {
  final p = '/${path.toLowerCase()}';
  for (final layer in checkOrder) {
    final rule = layerRules[layer]!;
    if ((rule['suffixes'] ?? const []).any(p.endsWith)) return layer;
    if ((rule['contains'] ?? const []).any(p.contains)) return layer;
  }
  return p.endsWith('.dart') ? 10 : 7;
}

class ChangedFile {
  final String status;
  final String path;
  final String? oldPath;
  int added = 0;
  int deleted = 0;
  bool binary = false;

  ChangedFile(this.status, this.path, [this.oldPath]);

  int get layer => classify(path);

  String get featureFolder {
    final parts = path.split('/');
    final i = parts.indexOf('features');
    if (i >= 0 && i + 1 < parts.length - 1) return parts[i + 1];
    return parts.length > 1 ? parts.sublist(0, parts.length - 1).join('/') : '';
  }

  String get fileName => path.split('/').last;

  String get label => oldPath == null ? path : '$oldPath -> $path';
}

const utf8Lenient = Utf8Codec(allowMalformed: true);

String git(List<String> args, {Map<String, String>? env, bool allowFail = false}) {
  final r = Process.runSync('git', args,
      environment: env, stdoutEncoding: utf8Lenient, stderrEncoding: utf8Lenient);
  if (r.exitCode != 0 && !allowFail) {
    stderr.writeln('git ${args.join(' ')} failed:\n${r.stderr}');
    exit(1);
  }
  return r.exitCode == 0 ? (r.stdout as String) : '';
}

String? headCommit() {
  final out = git(['rev-parse', '--verify', '-q', 'HEAD'], allowFail: true).trim();
  return out.isEmpty ? null : out;
}

String slugOf(String name) {
  final s = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return s.isEmpty ? 'unnamed' : s;
}

String? refSha(String ref) {
  final out = git(['rev-parse', '--verify', '-q', ref], allowFail: true).trim();
  return out.isEmpty ? null : out;
}

// Full working tree (incl. untracked, minus ignored) as a commit, via a throwaway index.
String snapshot(String name) {
  final realIndex = File(git(['rev-parse', '--git-path', 'index']).trim()).absolute;
  final tmpIndex = File('${Directory.systemTemp.path}${Platform.pathSeparator}'
      'flutter-review-$pid-${DateTime.now().microsecondsSinceEpoch}.index');
  try {
    if (realIndex.existsSync()) realIndex.copySync(tmpIndex.path);
    final env = {
      'GIT_INDEX_FILE': tmpIndex.path,
      'GIT_AUTHOR_NAME': 'flutter-review',
      'GIT_AUTHOR_EMAIL': 'flutter-review@localhost',
      'GIT_COMMITTER_NAME': 'flutter-review',
      'GIT_COMMITTER_EMAIL': 'flutter-review@localhost',
    };
    git(['add', '-A'], env: env);
    final tree = git(['write-tree'], env: env).trim();
    final head = headCommit();
    return git([
      'commit-tree',
      tree,
      if (head != null) ...['-p', head],
      '-m',
      'flutter-review snapshot: $name',
    ], env: env)
        .trim();
  } finally {
    if (tmpIndex.existsSync()) tmpIndex.deleteSync();
    final lock = File('${tmpIndex.path}.lock');
    if (lock.existsSync()) lock.deleteSync();
  }
}

void saveRef(String slug, String kind, String sha) => git(['update-ref', '$refRoot/$slug/$kind', sha]);

void ensureExcluded() {
  final exclude = File(git(['rev-parse', '--git-path', 'info/exclude']).trim());
  final line = '/$reportDir/';
  final existing = exclude.existsSync() ? exclude.readAsStringSync() : '';
  if (existing.split(RegExp(r'\r?\n')).contains(line)) return;
  exclude.parent.createSync(recursive: true);
  final sep = existing.isEmpty || existing.endsWith('\n') ? '' : '\n';
  exclude.writeAsStringSync('$existing$sep$line\n');
}

List<ChangedFile> changedFiles(String a, String b) {
  final files = <String, ChangedFile>{};
  final ns = git(['diff', '-M', '--name-status', '-z', a, b]).split('\x00');
  for (var i = 0; i + 1 < ns.length;) {
    final code = ns[i];
    if (code.isEmpty) break;
    if (code.startsWith('R') || code.startsWith('C')) {
      files[ns[i + 2]] = ChangedFile('renamed', ns[i + 2], ns[i + 1]);
      i += 3;
      continue;
    }
    final status = switch (code[0]) { 'A' => 'added', 'D' => 'deleted', _ => 'modified' };
    files[ns[i + 1]] = ChangedFile(status, ns[i + 1]);
    i += 2;
  }
  final num = git(['diff', '-M', '--numstat', '-z', a, b]).split('\x00');
  for (var i = 0; i < num.length; i++) {
    final cols = num[i].split('\t');
    if (cols.length < 3) continue;
    var path = cols[2];
    if (path.isEmpty) {
      path = num[i + 2];
      i += 2;
    }
    final f = files[path];
    if (f == null) continue;
    if (cols[0] == '-') {
      f.binary = true;
    } else {
      f.added = int.parse(cols[0]);
      f.deleted = int.parse(cols[1]);
    }
  }
  return files.values.toList();
}

Map<int, List<ChangedFile>> byLayer(List<ChangedFile> files) {
  final layers = {for (final n in layerNames.keys) n: <ChangedFile>[]};
  for (final f in files) {
    layers[f.layer]!.add(f);
  }
  layers.forEach((layer, list) {
    final interfaceFirst = interfaceFirstLayers.contains(layer);
    list.sort((x, y) {
      final c = x.featureFolder.compareTo(y.featureFolder);
      if (c != 0) return c;
      if (interfaceFirst) {
        final xi = x.fileName.contains('interface') ? 0 : 1;
        final yi = y.fileName.contains('interface') ? 0 : 1;
        if (xi != yi) return xi - yi;
      }
      final n = x.fileName.compareTo(y.fileName);
      return n != 0 ? n : x.path.compareTo(y.path);
    });
  });
  return layers;
}

String summaryText(String a, String b) {
  final layers = byLayer(changedFiles(a, b));
  final out = StringBuffer();
  final total = layers.values.fold<int>(0, (s, l) => s + l.length);
  out.writeln('Changed files: $total   ($a..$b)');
  out.writeln();
  out.writeln('  #  Layer             Files      +lines   -lines');
  out.writeln('  -- ----------------  -----  ---------  -------');
  layers.forEach((n, list) {
    final add = list.fold<int>(0, (s, f) => s + f.added);
    final del = list.fold<int>(0, (s, f) => s + f.deleted);
    out.writeln('  ${'$n'.padLeft(2)} ${layerNames[n]!.padRight(16)}  ${'${list.length}'.padLeft(5)}  '
        '${'+$add'.padLeft(9)}  ${'-$del'.padLeft(7)}');
  });
  layers.forEach((n, list) {
    if (list.isEmpty) return;
    out.writeln();
    out.writeln('[$n] ${layerNames[n]}');
    for (final f in list) {
      final stat = f.binary ? 'binary' : '+${f.added} -${f.deleted}';
      out.writeln('  ${f.status.padRight(8)}  ${f.label}  ($stat)');
    }
  });
  return out.toString();
}

String numbered(String content) {
  final lines = const LineSplitter().convert(content);
  final width = '${lines.length}'.length;
  final out = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    out.writeln('${'${i + 1}'.padLeft(width)} | ${lines[i]}');
  }
  return out.toString();
}

String fileText(ChangedFile f, String a, String b, bool full) {
  final out = StringBuffer();
  out.writeln('=== [${f.status}] ${f.label}  '
      '(${f.binary ? 'binary' : '+${f.added} -${f.deleted}'}) ===');
  if (f.binary) {
    final side = f.status == 'deleted' ? '$a:${f.path}' : '$b:${f.path}';
    out.writeln('Binary file, ${git(['cat-file', '-s', side]).trim()} bytes. Content not shown.');
    return out.toString();
  }
  if (full) {
    final side = f.status == 'deleted' ? '$a:${f.path}' : '$b:${f.path}';
    out.writeln(f.status == 'deleted' ? '--- removed content ---' : '--- full new content ---');
    out.write(numbered(git(['show', side])));
    return out.toString();
  }
  out.write(git([
    'diff', '-M', '-U$contextLines', a, b, '--',
    if (f.oldPath != null) f.oldPath!,
    f.path,
  ]));
  return out.toString();
}

String layerText(int n, String a, String b, bool full) {
  final list = byLayer(changedFiles(a, b))[n]!;
  final out = StringBuffer('##### Layer $n — ${layerNames[n]} (${list.length} files)\n\n');
  for (final f in list) {
    out.writeln(fileText(f, a, b, full));
  }
  return out.toString();
}

String fence(String body) {
  final runs = RegExp(r'`+').allMatches(body).map((m) => m.group(0)!.length);
  final longest = runs.isEmpty ? 0 : runs.reduce((x, y) => x > y ? x : y);
  return '`' * (longest < 3 ? 3 : longest + 1);
}

// Drops the `diff --git` / `index` / `---` / `+++` boilerplate (the path is
// already in the numbered heading) and keeps only the `@@` hunks onward.
String stripDiffHeader(String diff) {
  final lines = const LineSplitter().convert(diff);
  final i = lines.indexWhere((l) => l.startsWith('@@'));
  return i < 0 ? diff : '${lines.sublist(i).join('\n')}\n';
}

// One numbered heading + one fenced diff per file, so a Markdown preview
// renders each file on its own line with just its changed lines below it —
// not a wall of repeated file-path boilerplate.
String fileSection(ChangedFile fl, String a, String b, int index) {
  final stat = fl.binary ? 'binary' : '+${fl.added} -${fl.deleted}';
  final out = StringBuffer('$index. `${fl.label}` — ${fl.status} ($stat)\n\n');
  if (fl.binary) {
    final side = fl.status == 'deleted' ? '$a:${fl.path}' : '$b:${fl.path}';
    out.writeln('   Binary file, ${git(['cat-file', '-s', side]).trim()} bytes. Content not shown.\n');
    return out.toString();
  }
  if (fl.status == 'deleted') {
    out.writeln('   File deleted (${fl.deleted} lines removed).\n');
    return out.toString();
  }
  final body = stripDiffHeader(git([
    'diff', '-M', '-U$contextLines', a, b, '--',
    if (fl.oldPath != null) fl.oldPath!,
    fl.path,
  ]));
  final f = fence(body);
  out.writeln('${f}diff\n$body$f\n');
  return out.toString();
}

String writeReport(String name, String slug, String a, String b, String summary) {
  final now = DateTime.now();
  String two(int v) => '$v'.padLeft(2, '0');
  final stamp = '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}';
  var file = File('$reportDir/$slug-$stamp.md');
  // A recheck within the same minute must not overwrite the earlier review.
  for (var i = 2; file.existsSync(); i++) {
    file = File('$reportDir/$slug-$stamp-$i.md');
  }
  file.parent.createSync(recursive: true);
  final md = StringBuffer('# Review: $name\n\nFrom `$a` to `$b`, written $now\n\n');
  final f = fence(summary);
  md.writeln('## Summary\n\n$f\n$summary$f\n');
  final layers = byLayer(changedFiles(a, b));
  for (final n in layerNames.keys) {
    final list = layers[n]!;
    if (list.isEmpty) continue;
    md.writeln('## Layer $n — ${layerNames[n]} (${list.length} files)\n');
    for (var i = 0; i < list.length; i++) {
      md.write(fileSection(list[i], a, b, i + 1));
    }
  }
  file.writeAsStringSync(md.toString());
  return file.absolute.path;
}

// Each line: slug, date, name. Newest first.
List<List<String>> baselines() {
  final out = git([
    'for-each-ref',
    '--sort=-committerdate',
    '--format=%(refname)%09%(committerdate:format:%Y-%m-%d %H:%M)%09%(contents:subject)',
    refRoot,
  ]);
  final rows = <List<String>>[];
  for (final line in const LineSplitter().convert(out)) {
    final cols = line.split('\t');
    final parts = cols[0].split('/');
    if (parts.last != 'baseline') continue;
    final name = cols[2].replaceFirst('flutter-review snapshot: ', '');
    rows.add([parts[parts.length - 2], cols[1], name]);
  }
  return rows;
}

Never fail(String msg, [int code = 2]) {
  stderr.writeln(msg);
  exit(code);
}

String? optValue(List<String> args, String flag) {
  final i = args.indexOf(flag);
  if (i < 0) return null;
  if (i + 1 >= args.length) fail('$flag needs a value');
  final v = args[i + 1];
  args.removeRange(i, i + 2);
  return v;
}

void cmdPrepare(List<String> args) {
  final mode = args.isEmpty ? 'review' : args.removeAt(0);
  final since = optValue(args, '--since');
  final givenName = args.isEmpty ? null : args.join(' ');
  String name;
  String slug;
  String from;

  if (since != null) {
    name = givenName ?? 'unnamed';
    slug = slugOf(name);
    from = git(['rev-parse', '--verify', '$since^{commit}'], allowFail: true).trim();
    if (from.isEmpty) fail('Not a commit or branch: $since');
    if (refSha('$refRoot/$slug/baseline') == null) saveRef(slug, 'baseline', from);
  } else {
    if (givenName != null) {
      name = givenName;
      slug = slugOf(givenName);
    } else {
      final all = baselines();
      if (all.isEmpty) fail('NO_BASELINE: no flutter-review baseline exists in this repo.', 3);
      slug = all.first[0];
      name = all.first[2];
    }
    final baseline = refSha('$refRoot/$slug/baseline');
    if (baseline == null) fail('NO_BASELINE: no baseline for "$name" ($slug).', 3);
    if (mode == 'recheck') {
      final reviewed = refSha('$refRoot/$slug/reviewed');
      if (reviewed == null) fail('No previous review for "$name". Run a full review first.');
      from = reviewed;
    } else {
      from = baseline;
    }
  }

  final to = snapshot(name);
  saveRef(slug, 'reviewed', to);
  final summary = summaryText(from, to);
  final report = writeReport(name, slug, from, to, summary);
  stdout.writeln('FEATURE=$name\nSLUG=$slug\nMODE=$mode\nFROM=$from\nTO=$to\nREPORT=$report\n');
  stdout.write(summary);
}

const helpText = '''
flutter-review commands

  /flutter-review-start <name>      Save a baseline of the working tree before you build a feature.
                                    e.g. /flutter-review-start pharmacy checkout
  /flutter-review [name]            Diff baseline -> now, then walk it layer by layer (latest baseline if no name).
                                    e.g. /flutter-review pharmacy checkout
  /flutter-review-recheck [name]    Diff the last review -> now, to review only the fixes made since.
                                    e.g. /flutter-review-recheck
  /flutter-review-list              List baselines with their date and changed-file count.
  /flutter-review-done <name>       Delete a feature's baseline and review refs.
                                    e.g. /flutter-review-done pharmacy checkout
  /flutter-review-help              Show this list.

The review (all layers, full diffs, notes) is written to .code-review/<feature>-<date>.md, not the terminal.
''';

void main(List<String> argv) {
  final args = [...argv];
  if (args.isEmpty || const ['help', '-h', '--help'].contains(args.first)) {
    stdout.write(helpText);
    return;
  }
  final top = git(['rev-parse', '--show-toplevel'], allowFail: true).trim();
  if (top.isEmpty) fail('Not inside a git repository.');
  Directory.current = top;
  ensureExcluded();

  final cmd = args.removeAt(0);
  switch (cmd) {
    case 'start':
      if (args.isEmpty) fail('usage: start <feature-name>');
      final name = args.join(' ');
      final slug = slugOf(name);
      if (refSha('$refRoot/$slug/baseline') != null) {
        fail('Baseline for "$name" already exists. Run `done $name` first to replace it.');
      }
      final sha = snapshot(name);
      saveRef(slug, 'baseline', sha);
      stdout.writeln('Baseline saved: $refRoot/$slug/baseline -> $sha');
    case 'prepare':
      cmdPrepare(args);
    case 'list':
      final all = baselines();
      if (all.isEmpty) {
        stdout.writeln('No baselines.');
        return;
      }
      final now = snapshot('list');
      stdout.writeln('Name                          Slug                          Created           Changed');
      for (final row in all) {
        final count = const LineSplitter()
            .convert(git(['diff', '-M', '--name-only', '$refRoot/${row[0]}/baseline', now]))
            .length;
        stdout.writeln('${row[2].padRight(30)}${row[0].padRight(30)}${row[1].padRight(18)}$count');
      }
    case 'done':
      if (args.isEmpty) fail('usage: done <feature-name>');
      final slug = slugOf(args.join(' '));
      var removed = 0;
      for (final kind in ['baseline', 'reviewed']) {
        if (refSha('$refRoot/$slug/$kind') == null) continue;
        git(['update-ref', '-d', '$refRoot/$slug/$kind']);
        removed++;
      }
      stdout.writeln(removed == 0 ? 'No refs for "$slug".' : 'Deleted $removed ref(s) for "$slug".');
    case 'summary':
      if (args.length != 2) fail('usage: summary <ref-a> <ref-b>');
      stdout.write(summaryText(args[0], args[1]));
    case 'layer':
      final full = args.remove('--full');
      if (args.length != 3) fail('usage: layer <n> <ref-a> <ref-b> [--full]');
      final n = int.tryParse(args[0]);
      if (n == null || !layerNames.containsKey(n)) fail('Layer must be 1-10.');
      stdout.write(layerText(n, args[1], args[2], full));
    default:
      stdout.write('Unknown command: $cmd\n\n$helpText');
      exit(2);
  }
}
