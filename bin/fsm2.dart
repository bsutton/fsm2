#! /usr/bin/env dcli

import 'dart:async';
import 'dart:io';
import 'package:dcli/dcli.dart';
import 'package:synchronized/synchronized.dart';

/// dcli script generated by:
/// dcli create show.dart
///
/// See
/// https://pub.dev/packages/dcli#-installing-tab-
///
/// For details on installing dcli.
///

void main(List<String> args) async {
  var parser = ArgParser();
  parser.addFlag(
    'verbose',
    abbr: 'v',
    negatable: false,
    defaultsTo: false,
    help: 'Logs additional details to the cli',
  );

  parser.addFlag(
    'help',
    abbr: 'h',
    negatable: false,
    defaultsTo: false,
    help: 'Shows the help message',
  );

  parser.addFlag(
    'show',
    abbr: 's',
    negatable: false,
    defaultsTo: false,
    help: 'After generating the image file it will be displayed using firefox.',
  );

  parser.addFlag(
    'watch',
    abbr: 'w',
    negatable: false,
    defaultsTo: false,
    help: 'Monitors the smcat files and regenerates the svg if they change.',
  );

  parser.addFlag(
    'install',
    abbr: 'i',
    negatable: false,
    defaultsTo: false,
    help: 'Install the smcat dependencies',
  );

  var parsed = parser.parse(args);

  if (parsed.wasParsed('help')) {
    showUsage(parser);
  }

  if (parsed.wasParsed('verbose')) {
    Settings().setVerbose(enabled: true);
  }

  if (parsed.wasParsed('install')) {
    install();
    exit(0);
  }

  if (parsed.rest.isEmpty) {
    print(red('You must pass a to path the basename of the smcat file'));
    showUsage(parser);
  }

  await generateAll(parsed.rest, parsed.wasParsed('show'), parsed.wasParsed('watch'));
}

Future<void> generateAll(List<String> rest, bool show, bool watch) async {
  var watchList = <String>[];

  for (var file in rest) {
    if (exists(file)) {
      watchList.add(file);
      generate(file, show);
    } else {
      if (extension(file).isNotEmpty) {
        printerr(red('File $file not found'));
        exit(1);
      }
      var count = 0;
      var pattern = '$file.*.smcat';
      for (file in find(pattern, recursive: false).toList()) {
        generate(file, show);
        watchList.add(file);
      }
      if (count == 0) {
        var one = '$file.smcat';
        if (exists(one)) {
          generate(one, show);
          watchList.add(file);
        } else {
          printerr(orange('No files found that match the pattern: $pattern or $one'));
        }
      }
    }
  }
  if (watch && watchList.isNotEmpty) {
    await watchFiles(watchList);
  }
}

void install() {
  if (which('npm').notfound) {
    print(red('Please install npm and then try again'));
    exit(1);
  }
  'npm install --global state-machine-cat'.start(privileged: true);
}

final lock = Lock();
void generate(String path, bool show) {
  var outputFile = '${basenameWithoutExtension(path)}.svg';
  print('Generating: $outputFile ');

  /// 'smcat -T dot $path | dot -T svg > your-machine.svg'.run;
  'smcat $path'.start(
      progress: Progress((stdout) => print(stdout), stderr: (stderr) {
    /// suppress the viz warning:
    /// https://github.com/sverweij/state-machine-cat/issues/127
    if (!stderr.contains('viz.js:33')) print(stderr);
  }));

  if (show) {
    'firefox $outputFile'.start(detached: true);
  }
}

void showUsage(ArgParser parser) {
  print('Usage: ${Script.current.exeName} <base name of myfsm2>\n');
  print('Converts a set of smcat files into svg files.');
  print('If your smcat file has multiple parts due to page breaks then each page will be processed.');
  print(parser.usage);
  exit(1);
}

var controller = StreamController<FileSystemEvent>();
Future<void> watchFiles(List<String> files) async {
  StreamSubscription<FileSystemEvent> subscriber;
  subscriber = controller.stream.listen((event) async {
    // serialise the events
    // otherwise we end up trying to move multiple files
    // at once and that doesn't work.
    subscriber.pause();
    onFileSystemEvent(event);
    subscriber.resume();
  });

  /// start a watch on every subdirectory of _projectRoot
  for (var file in files) {
    watchFile(file);
  }

  var forever = Completer<void>();

  // wait until someone does ctrl-c.
  await forever.future;
}

void watchFile(String file) {
  File(file).watch(events: FileSystemEvent.all).listen((event) => controller.add(event));
}

void watchDirectory(String projectRoot) {
  print('watching ${projectRoot}');
  Directory(projectRoot).watch(events: FileSystemEvent.all).listen((event) => controller.add(event));
}

void onFileSystemEvent(FileSystemEvent event) async {
  if (event is FileSystemCreateEvent) {
    onCreateEvent(event);
  } else if (event is FileSystemModifyEvent) {
    onModifyEvent(event);
  } else if (event is FileSystemMoveEvent) {
    onMoveEvent(event);
  } else if (event is FileSystemDeleteEvent) {
    onDeleteEvent(event);
  }
}

/// when we see a mod we want to delay the generation as we often
/// see multiple modifications when a file is being updated.
var toGenerate = <String>[];

void onModifyEvent(FileSystemModifyEvent event) async {
  toGenerate.add(event.path);

  Future.delayed(Duration(microseconds: 1500), () => delayedGeneration());
}

void delayedGeneration() {
  lock.synchronized(() {
    for (var file in toGenerate.toSet()) {
      generate(file, true);
    }
    toGenerate.clear();
  });
}

void onCreateEvent(FileSystemCreateEvent event) async {
  if (event.isDirectory) {
    Directory(event.path).watch(events: FileSystemEvent.all).listen((event) => controller.add(event));
  } else {
    if (lastDeleted != null) {
      if (basename(event.path) == basename(lastDeleted)) {
        print(red('Move from: $lastDeleted to: ${event.path}'));
        generate(event.path, true);
        lastDeleted = null;
      }
    }
  }
}

String lastDeleted;

void onDeleteEvent(FileSystemDeleteEvent event) async {
  print('Delete:  ${event.path}');
  if (!event.isDirectory) {
    lastDeleted = event.path;
  }
}

void onMoveEvent(FileSystemMoveEvent event) async {
  // var actioned = false;

  // var from = event.path;
  // var to = event.destination;

  // if (event.isDirectory) {
  //   actioned = true;
  //   await MoveCommand().importMoveDirectory(from: libRelative(from), to: libRelative(to), alreadyMoved: true);
  // } else {
  //   if (extension(from) == '.dart') {
  //     /// we don't process the move if the 'to' isn't a dart file.
  //     /// e.g. ignore a target of <lib>.dart.bak
  //     if (isDirectory(to) || isFile(to) && extension(to) == '.dart') {
  //       actioned = true;
  //       await MoveCommand()
  //           .moveFile(from: libRelative(from), to: libRelative(to), fromDirectory: false, alreadyMoved: true);
  //     }
  //   }
  // }
  // if (actioned) {
  //   print('Move: directory: ${event.isDirectory} ${event.path} destination: ${event.destination}');
  // }
}