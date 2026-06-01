// ignore_for_file: avoid_print

import 'package:logging/logging.dart' as logging;

export 'package:logging/logging.dart' show Level;

class LogNames {
  static const editor = 'editor';
  static const editorEdits = 'editor.edits';
  static const editorPolicies = 'editor.policies';
  static const editorScrolling = 'editor.scrolling';
  static const editorGestures = 'editor.gestures';
  static const editorKeys = 'editor.keys';
  static const editorIme = 'editor.ime';
  static const editorImeConnection = 'editor.ime.connection';
  static const editorImeDeltas = 'editor.ime.deltas';
  static const editorIosFloatingCursor = 'editor.ios.floatingCursor';
  static const editorLayout = 'editor.layout';
  static const editorStyle = 'editor.style';
  static const editorDocument = 'editor.document';
  static const editorCommonOps = 'editor.ops';
  static const editorTokens = 'editor.tokens';
  static const editorTags = 'editor.tokens.tags';
  static const editorUserTags = 'editor.tokens.tags.users';
  static const editorHashTags = 'editor.tokens.tags.hash';
  static const editorActionTags = 'editor.tokens.tags.action';
  static const editorSpellingAndGrammar = 'editor.spellingAndGrammar';

  static const reader = 'reader';
  static const readerScrolling = 'reader.scrolling';
  static const readerGestures = 'reader.gestures';
  static const readerKeys = 'reader.keys';
  static const readerIme = 'reader.ime';
  static const readerLayout = 'reader.layout';
  static const readerStyle = 'reader.style';
  static const readerDocument = 'reader.document';
  static const readerCommonOps = 'reader.ops';

  static const documentGestures = 'document.gestures';

  static const textField = 'textfield';
  static const scrollingTextField = 'textfield.scrolling';
  static const imeTextField = 'textfield.ime';
  static const androidTextField = 'textfield.android';
  static const iosTextField = 'textfield.ios';

  static const superIme = 'superime';
  static const infrastructure = 'infrastructure';
  static const keyboardPanel = 'infrastructure.keyboardPanel';
  static const longPressSelection = 'infrastructure.gestures.longPress';
  static const scheduler = 'infrastructure.scheduler';
  static const contentLayers = 'infrastructure.content_layers';
  static const attributions = 'infrastructure.attributions';
}

// Chat
final messagePageElementLog = logging.Logger('chat.messagePage.element');
final messagePageLayoutLog = logging.Logger('chat.messagePage.layout');
final messagePagePaintLog = logging.Logger('chat.messagePage.paint');
final messageEditorHeightLog = logging.Logger('chat.messagePage.editorHeight');

// Super Editor
final editorLog = logging.Logger(LogNames.editor);
final editorEditsLog = logging.Logger(LogNames.editorEdits);
final editorPoliciesLog = logging.Logger(LogNames.editorPolicies);
final editorScrollingLog = logging.Logger(LogNames.editorScrolling);
final editorGesturesLog = logging.Logger(LogNames.editorGestures);
final editorKeyLog = logging.Logger(LogNames.editorKeys);
final editorImeLog = logging.Logger(LogNames.editorIme);
final editorImeConnectionLog = logging.Logger(LogNames.editorImeConnection);
final editorImeDeltasLog = logging.Logger(LogNames.editorImeDeltas);
final editorIosFloatingCursorLog = logging.Logger(LogNames.editorIosFloatingCursor);
final editorLayoutLog = logging.Logger(LogNames.editorLayout);
final editorStyleLog = logging.Logger(LogNames.editorStyle);
final editorDocLog = logging.Logger(LogNames.editorDocument);
final editorOpsLog = logging.Logger(LogNames.editorCommonOps);
final editorTokensLog = logging.Logger(LogNames.editorTokens);
final editorTagsLog = logging.Logger(LogNames.editorTags);
final editorStableTagsLog = logging.Logger(LogNames.editorUserTags);
final editorPatternTagsLog = logging.Logger(LogNames.editorHashTags);
final editorActionTagsLog = logging.Logger(LogNames.editorActionTags);
final editorSpellingAndGrammarLog = logging.Logger(LogNames.editorSpellingAndGrammar);

// Super Reader
final readerLog = logging.Logger(LogNames.reader);
final readerScrollingLog = logging.Logger(LogNames.readerScrolling);
final readerGesturesLog = logging.Logger(LogNames.readerGestures);
final readerKeyLog = logging.Logger(LogNames.readerKeys);
final readerImeLog = logging.Logger(LogNames.readerIme);
final readerLayoutLog = logging.Logger(LogNames.readerLayout);
final readerStyleLog = logging.Logger(LogNames.readerStyle);
final readerDocLog = logging.Logger(LogNames.readerDocument);
final readerOpsLog = logging.Logger(LogNames.readerCommonOps);

// Text Fields.
final textFieldLog = logging.Logger(LogNames.textField);
final scrollingTextFieldLog = logging.Logger(LogNames.scrollingTextField);
final imeTextFieldLog = logging.Logger(LogNames.imeTextField);
final androidTextFieldLog = logging.Logger(LogNames.androidTextField);
final iosTextFieldLog = logging.Logger(LogNames.iosTextField);

// Infrastructure.
final docGesturesLog = logging.Logger(LogNames.documentGestures);
final superImeLog = logging.Logger(LogNames.superIme);
final infrastructureLog = logging.Logger(LogNames.infrastructure);
final keyboardPanelLog = logging.Logger(LogNames.keyboardPanel);
final longPressSelectionLog = logging.Logger(LogNames.longPressSelection);
final schedulerLog = logging.Logger(LogNames.scheduler);
final contentLayersLog = logging.Logger(LogNames.contentLayers);
final attributionsLog = logging.Logger(LogNames.attributions);

final _activeLoggers = <logging.Logger>{};

void initAllLogs(logging.Level level) {
  initLoggers(level, {logging.Logger.root});
}

void initLoggers(logging.Level level, Set<logging.Logger> loggers) {
  logging.hierarchicalLoggingEnabled = true;

  for (final logger in loggers) {
    if (!_activeLoggers.contains(logger)) {
      print('Initializing logger: ${logger.name}');
      logger
        ..level = level
        ..onRecord.listen(printLog);

      _activeLoggers.add(logger);
    }
  }
}

/// Returns `true` if the given [logger] is currently logging, or
/// `false` otherwise.
///
/// Generally, developers should call loggers, regardless of whether
/// a given logger is active. However, sometimes you may want to log
/// information that's costly to compute. In such a case, you can
/// choose to compute the expensive information only if the given
/// logger will actually log the information.
bool isLogActive(logging.Logger logger) {
  return _activeLoggers.contains(logger);
}

void deactivateLoggers(Set<logging.Logger> loggers) {
  for (final logger in loggers) {
    if (_activeLoggers.contains(logger)) {
      print('Deactivating logger: ${logger.name}');
      logger.clearListeners();

      _activeLoggers.remove(logger);
    }
  }
}

void printLog(logging.LogRecord record) {
  print(
      '(${record.time.second}.${record.time.millisecond.toString().padLeft(3, '0')}) ${record.loggerName} > ${record.level.name}: ${record.message}');
}

/// Extension on [Logger] that adds lazy evaluation methods.
///
/// These methods only evaluate the message closure when the log level
/// is enabled, avoiding expensive string interpolation in hot paths
/// like layout, selection, and content layers.
extension LazyLogger on logging.Logger {
  /// Logs a message only if the [Level.FINE] level is enabled.
  ///
  /// Use this for expensive log messages in hot paths:
  /// ```dart
  /// logger.fineLazy(() => "Expensive: $computeExpensiveValue()");
  /// ```
  void fineLazy(String Function() message) {
    if (isLoggable(logging.Level.FINE)) {
      fine(message());
    }
  }

  /// Logs a message only if the [Level.FINER] level is enabled.
  void finerLazy(String Function() message) {
    if (isLoggable(logging.Level.FINER)) {
      finer(message());
    }
  }

  /// Logs a message only if the [Level.FINEST] level is enabled.
  void finestLazy(String Function() message) {
    if (isLoggable(logging.Level.FINEST)) {
      finest(message());
    }
  }

  /// Logs a message only if the [Level.INFO] level is enabled.
  void infoLazy(String Function() message) {
    if (isLoggable(logging.Level.INFO)) {
      info(message());
    }
  }

  /// Logs a message only if the [Level.WARNING] level is enabled.
  void warningLazy(String Function() message) {
    if (isLoggable(logging.Level.WARNING)) {
      warning(message());
    }
  }

  /// Logs a message only if the [Level.SEVERE] level is enabled.
  void severeLazy(String Function() message) {
    if (isLoggable(logging.Level.SEVERE)) {
      severe(message());
    }
  }
}

// TODO: get rid of this custom Logger when all references are replaced with logging package
class Logger {
  static bool _printLogs = false;
  static void setLoggingMode(bool enabled) {
    _printLogs = enabled;
  }

  Logger({
    required scope,
  }) : _scope = scope;

  final String _scope;

  void log(String tag, String message, [Exception? exception]) {
    if (!Logger._printLogs) {
      return;
    }

    print('[$_scope] - $tag: $message');
    if (exception != null) {
      print(' - ${exception.toString()}');
    }
  }
}
