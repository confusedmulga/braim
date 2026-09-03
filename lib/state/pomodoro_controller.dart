import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../services/dnd_service.dart';
import '../services/focus_media_service.dart';

enum PomoKind { focus, rest }

class PomoPhase {
  const PomoPhase(this.kind, this.seconds);
  final PomoKind kind;
  final int seconds;
}

/// Localized labels the controller stamps onto the ongoing notification and the
/// phase alerts (supplied by the screen, which has a BuildContext).
class FocusStrings {
  const FocusStrings({
    required this.focus,
    required this.rest,
    required this.done,
    required this.round,
    required this.paused,
    required this.breakSoon,
    required this.backToFocus,
    required this.sessionDone,
  });

  const FocusStrings.fallback()
      : focus = 'Focus',
        rest = 'Break',
        done = 'All done',
        round = 'Round',
        paused = 'Paused',
        breakSoon = 'Break time',
        backToFocus = 'Back to focus',
        sessionDone = 'Focus session complete';

  final String focus;
  final String rest;
  final String done;
  final String round;
  final String paused;
  final String breakSoon;
  final String backToFocus;
  final String sessionDone;
}

/// Owns the Pomodoro session so it survives leaving the screen: a singleton
/// [ChangeNotifier] with its own ticker. Time is tracked against the wall clock
/// (absolute phase-end instants), so backgrounding never drifts it — on resume
/// it reconciles however many phases elapsed while away.
class PomodoroController extends ChangeNotifier with WidgetsBindingObserver {
  PomodoroController._() {
    WidgetsBinding.instance.addObserver(this);
    // The media notification's play/pause button routes back here.
    FocusMediaService.instance.onAction = (action) {
      if (action == 'play') {
        resume();
      } else if (action == 'pause') {
        pause();
      }
    };
  }
  static final PomodoroController instance = PomodoroController._();

  // Config (adjustable while idle).
  int focusMin = 20;
  int breakMin = 5;
  int rounds = 3;
  DndMode dnd = DndMode.off;

  // Runtime.
  bool running = false;
  bool completed = false;
  bool _started = false;
  int _index = 0;
  DateTime? _phaseEnd; // when the current phase ends (while running)
  int _pausedRemaining = 0; // seconds left when paused / before first start
  Timer? _ticker;
  FocusStrings _s = const FocusStrings.fallback();

  // ---- Derived state ------------------------------------------------------

  List<PomoPhase> get phases => [
        for (var r = 0; r < rounds; r++) ...[
          PomoPhase(PomoKind.focus, focusMin * 60),
          PomoPhase(PomoKind.rest, breakMin * 60),
        ],
      ];

  PomoPhase get current => phases[_index.clamp(0, phases.length - 1)];
  bool get isFocus => current.kind == PomoKind.focus;
  int get round => (_index ~/ 2) + 1;

  bool get idle => !_started;
  bool get paused => _started && !running && !completed;

  int get remaining {
    if (completed) return 0;
    if (running && _phaseEnd != null) {
      final r = _phaseEnd!.difference(DateTime.now()).inSeconds;
      return r < 0 ? 0 : r;
    }
    return _started ? _pausedRemaining : phases.first.seconds;
  }

  double get fraction {
    final total = current.seconds;
    if (total == 0) return 0;
    return (1 - remaining / total).clamp(0.0, 1.0);
  }

  String get clock {
    final r = remaining;
    final m = (r ~/ 60).toString().padLeft(2, '0');
    final s = (r % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  int get phaseTotal => current.seconds;
  int get elapsedInPhase =>
      (current.seconds - remaining).clamp(0, current.seconds);
  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  String get elapsedClock => _fmt(elapsedInPhase);
  String get totalClock => _fmt(phaseTotal);

  // ---- Config -------------------------------------------------------------

  void setFocusMin(int v) => _configure(() => focusMin = v.clamp(5, 90));
  void setBreakMin(int v) => _configure(() => breakMin = v.clamp(1, 30));
  void setRounds(int v) => _configure(() => rounds = v.clamp(1, 8));

  void _configure(void Function() change) {
    if (_started) return; // config is locked once a session is under way
    change();
    _pausedRemaining = phases.first.seconds;
    notifyListeners();
  }

  Future<void> setDnd(DndMode mode) async {
    dnd = mode;
    notifyListeners();
    if (running) await DndService.instance.apply(mode);
  }

  // ---- Control ------------------------------------------------------------

  Future<void> resume() => start();

  /// Play/pause from the media notification's button.
  void toggleFromNotification() {
    if (running) {
      pause();
    } else if (paused) {
      resume();
    }
  }

  Future<void> start([FocusStrings? strings]) async {
    if (strings != null) _s = strings;
    if (completed) _resetState();
    if (!_started) {
      _index = 0;
      _pausedRemaining = phases.first.seconds;
    }
    _started = true;
    running = true;
    _phaseEnd = DateTime.now().add(Duration(seconds: _pausedRemaining));
    _startTicker();
    notifyListeners();
    await DndService.instance.apply(dnd);
    _syncMedia();
  }

  Future<void> pause() async {
    if (!running) return;
    _pausedRemaining = remaining;
    running = false;
    _phaseEnd = null;
    _ticker?.cancel();
    notifyListeners();
    // Paused = not focusing: drop the phone's DND; the media entry stays but
    // shows a paused (straight, non-wiggly) bar.
    await DndService.instance.restore();
    _syncMedia();
  }

  Future<void> reset() async {
    _ticker?.cancel();
    _resetState();
    notifyListeners();
    await FocusMediaService.instance.hide();
    await DndService.instance.restore();
  }

  void _resetState() {
    _started = false;
    running = false;
    completed = false;
    _index = 0;
    _phaseEnd = null;
    _pausedRemaining = phases.first.seconds;
  }

  /// Restarts the current phase from the top.
  void restartPhase() {
    if (!_started || completed) return;
    if (running) {
      _phaseEnd = DateTime.now().add(Duration(seconds: current.seconds));
      _syncMedia();
    } else {
      _pausedRemaining = current.seconds;
    }
    notifyListeners();
  }

  /// Jumps to the next phase (or finishes the session if on the last one).
  void skipPhase() {
    if (!_started || completed) return;
    final ph = phases;
    if (_index >= ph.length - 1) {
      running = false;
      completed = true;
      _phaseEnd = null;
      _pausedRemaining = 0;
      _ticker?.cancel();
      FocusMediaService.instance.hide();
      DndService.instance.restore();
      notifyListeners();
      return;
    }
    _index++;
    if (running) {
      _phaseEnd = DateTime.now().add(Duration(seconds: ph[_index].seconds));
      _syncMedia();
    } else {
      _pausedRemaining = ph[_index].seconds;
    }
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final changed = _reconcile();
    notifyListeners();
    if (!running) return; // completion is handled inside _reconcile
    if (changed) {
      // The seek-bar advances itself; only re-push on a phase change.
      HapticFeedback.selectionClick();
      _syncMedia();
    }
  }

  /// Advances through any phases whose end has passed (walking several if the
  /// app was away a while). Returns true when the phase changed.
  bool _reconcile() {
    if (!running || _phaseEnd == null) return false;
    final ph = phases;
    final startIndex = _index;
    while (running) {
      final rem = _phaseEnd!.difference(DateTime.now()).inSeconds;
      if (rem > 0) break;
      if (_index >= ph.length - 1) {
        running = false;
        completed = true;
        _phaseEnd = null;
        _pausedRemaining = 0;
        _ticker?.cancel();
        HapticFeedback.mediumImpact();
        FocusMediaService.instance.hide();
        DndService.instance.restore();
        break;
      }
      _index++;
      _phaseEnd = _phaseEnd!.add(Duration(seconds: ph[_index].seconds));
    }
    return _index != startIndex || completed;
  }

  // ---- Media notification -------------------------------------------------

  // Phase colours for the media notification: green study, light blue break.
  static const int _focusNotif = 0xFF2FA36B;
  static const int _breakNotif = 0xFF3E9BD8;

  String _label() => '${_s.round} $round/$rounds';

  /// Pushes the current phase to the native MediaSession notification. The
  /// system extrapolates the seek-bar from position + play speed, so it keeps
  /// advancing (and wiggling) on its own — we only re-push on phase/state change.
  void _syncMedia() {
    final total = current.seconds;
    final elapsed = (total - remaining).clamp(0, total);
    FocusMediaService.instance.show(
      title: isFocus ? _s.focus : _s.rest,
      text: _label(),
      elapsedMs: elapsed * 1000,
      durationMs: total * 1000,
      playing: running,
      color: isFocus ? _focusNotif : _breakNotif,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && running) {
      _reconcile();
      if (running) _syncMedia();
      notifyListeners();
    }
  }
}
