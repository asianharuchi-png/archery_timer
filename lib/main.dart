import 'dart:async';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ArcheryTimerApp());
}

enum TimerMode {
  threeMinutes,
  threeMinutesTwoRoundsAbCd,
  threeMinutesTwoRoundsCdAb,
  ninetySeconds,
  fifteenSecondShot,
  custom,
}

extension TimerModeExtension on TimerMode {
  String get label {
    switch (this) {
      case TimerMode.threeMinutes:
        return '2分モード';
      case TimerMode.threeMinutesTwoRoundsAbCd:
        return '3分2立ち・AB→CD';
      case TimerMode.threeMinutesTwoRoundsCdAb:
        return '3分2立ち・CD→AB';
      case TimerMode.ninetySeconds:
        return '1分30秒モード';
      case TimerMode.fifteenSecondShot:
        return '15秒射モード';
      case TimerMode.custom:
        return 'カスタムモード';
    }
  }
}

class ArcheryTimerApp extends StatelessWidget {
  const ArcheryTimerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'アーチェリータイマー',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const TimerScreen(),
    );
  }
}

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  TimerMode selectedMode = TimerMode.threeMinutes;

  final TextEditingController customMinutesController =
      TextEditingController(text: '3');
  final TextEditingController customSecondsController =
      TextEditingController(text: '0');

  final Map<String, AudioPlayer> soundPlayers = <String, AudioPlayer>{};
  final List<AudioPlayer> beepPlayers =
      List<AudioPlayer>.generate(3, (_) => AudioPlayer());
  int nextBeepPlayerIndex = 0;

  bool isRunning = false;
  bool audioReady = false;

  int remainingSeconds = 190;
  int currentShotRound = 1;
  int currentThreeMinuteRound = 1;
  int runId = 0;

  static const int preparationSeconds = 10;
  static const int shotSeconds = 15;
  static const int totalShotRounds = 10;
  static const int totalThreeMinuteRounds = 2;

  bool get isThreeMinuteTwoRoundsMode {
    return selectedMode == TimerMode.threeMinutesTwoRoundsAbCd ||
        selectedMode == TimerMode.threeMinutesTwoRoundsCdAb;
  }

  String get currentStandingGroup {
    if (selectedMode == TimerMode.threeMinutesTwoRoundsAbCd) {
      return currentThreeMinuteRound == 1 ? 'AB' : 'CD';
    }
    if (selectedMode == TimerMode.threeMinutesTwoRoundsCdAb) {
      return currentThreeMinuteRound == 1 ? 'CD' : 'AB';
    }
    return '';
  }

  int get competitionSeconds {
    switch (selectedMode) {
      case TimerMode.threeMinutes:
        return 120;
      case TimerMode.threeMinutesTwoRoundsAbCd:
      case TimerMode.threeMinutesTwoRoundsCdAb:
        return 180;
      case TimerMode.ninetySeconds:
        return 90;
      case TimerMode.fifteenSecondShot:
        return shotSeconds;
      case TimerMode.custom:
        final minutes =
            int.tryParse(customMinutesController.text.trim()) ?? 0;
        final seconds =
            int.tryParse(customSecondsController.text.trim()) ?? 0;
        final safeMinutes = minutes < 0 ? 0 : minutes;
        final safeSeconds = seconds.clamp(0, 59).toInt();
        return (safeMinutes * 60) + safeSeconds;
    }
  }

  int get initialSeconds {
    if (selectedMode == TimerMode.fifteenSecondShot) {
      return shotSeconds;
    }
    return competitionSeconds + preparationSeconds;
  }

  @override
  void initState() {
    super.initState();
    unawaited(initializeAudio());
  }

  static const List<String> soundFiles = <String>[
    '1min.wav',
    '1min30.wav',
    '2min.wav',
    '1min_left.wav',
    '30sec.wav',
    '15sec.wav',
    '10.wav',
    '9.wav',
    '8.wav',
    '7.wav',
    '6.wav',
    '5.wav',
    '4.wav',
    '3.wav',
    '2.wav',
    '1.wav',
    'shot1.wav',
    'shot2.wav',
    'shot3.wav',
    'shot4.wav',
    'shot5.wav',
    'shot6.wav',
    'shot7.wav',
    'shot8.wav',
    'shot9.wav',
    'shot10.wav',
  ];

  Future<void> initializeAudio() async {
    try {
      // スマホでは1つのAudioPlayerで音源を切り替え続けると、
      // 2回目以降の音声が再生されないことがあるため、音源ごとに分ける。
      for (final fileName in soundFiles) {
        final player = AudioPlayer();
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource('sounds/$fileName'));
        soundPlayers[fileName] = player;
      }

      // ピー・ピピ・ピピピは重ねて鳴らせるよう3台を用意する。
      for (final player in beepPlayers) {
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource('sounds/start.wav'));
      }

      if (!mounted) return;
      setState(() {
        audioReady = true;
      });
    } catch (error) {
      debugPrint('音声初期化エラー: $error');
      if (!mounted) return;
      setState(() {
        audioReady = true;
      });
    }
  }

  Future<void> playSound(
    String fileName, {
    Duration? waitAfterStart,
  }) async {
    try {
      final player = soundPlayers[fileName] ?? AudioPlayer();

      if (!soundPlayers.containsKey(fileName)) {
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource('sounds/$fileName'));
        soundPlayers[fileName] = player;
      }

      await player.stop();
      await player.seek(Duration.zero);
      await player.resume();

      if (waitAfterStart != null) {
        await Future.delayed(waitAfterStart);
      }
    } catch (error) {
      debugPrint('音声再生エラー ($fileName): $error');

      // resumeが失敗した端末向けの予備処理
      try {
        final player = soundPlayers[fileName] ?? AudioPlayer();
        soundPlayers[fileName] = player;
        await player.play(AssetSource('sounds/$fileName'));
        if (waitAfterStart != null) {
          await Future.delayed(waitAfterStart);
        }
      } catch (fallbackError) {
        debugPrint('音声再試行エラー ($fileName): $fallbackError');
      }
    }
  }

  Future<void> playOneBeep() async {
    try {
      final player = beepPlayers[nextBeepPlayerIndex];
      nextBeepPlayerIndex =
          (nextBeepPlayerIndex + 1) % beepPlayers.length;

      await player.stop();
      await player.seek(Duration.zero);
      await player.resume();

      // start.wavを最後まで鳴らすため、次の処理まで少し待つ。
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (error) {
      debugPrint('ビープ音エラー: $error');
    }
  }

  Future<void> playBeeps(int count) async {
    for (int i = 0; i < count; i++) {
      await playOneBeep();

      if (i < count - 1) {
        // ビープの開始間隔を一定にする。
        // playOneBeep内の180ms＋ここ420ms＝約600ms間隔。
        await Future.delayed(const Duration(milliseconds: 420));
      }
    }
  }

  Future<bool> runSynchronizedCountdown(
    int thisRunId, {
    int from = 10,
  }) async {
    for (int number = from; number >= 1; number--) {
      if (!isCurrentRunActive(thisRunId)) return false;

      if (mounted && remainingSeconds != number) {
        setState(() {
          remainingSeconds = number;
        });
      }

      final stopwatch = Stopwatch()..start();

      await playSound('$number.wav');

      final waitTime = const Duration(seconds: 1) - stopwatch.elapsed;
      if (waitTime > Duration.zero) {
        await Future.delayed(waitTime);
      }

      if (!isCurrentRunActive(thisRunId)) return false;
    }

    if (mounted) {
      setState(() {
        remainingSeconds = 0;
      });
    }

    return true;
  }

  bool isCurrentRunActive(int thisRunId) {
    return mounted && isRunning && thisRunId == runId;
  }

  Future<bool> waitOneSecond(int thisRunId) async {
    await Future.delayed(const Duration(seconds: 1));
    return isCurrentRunActive(thisRunId);
  }

  Future<bool> announceOneThenZero(int thisRunId) async {
    return runSynchronizedCountdown(thisRunId, from: 1);
  }

  void startTimer() {
    if (isRunning) return;

    if (selectedMode == TimerMode.custom && competitionSeconds <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('カスタム時間を1秒以上に設定してください')),
      );
      return;
    }

    runId++;
    final thisRunId = runId;

    setState(() {
      isRunning = true;
      currentShotRound = 1;
      currentThreeMinuteRound = 1;
      remainingSeconds = initialSeconds;
    });

    switch (selectedMode) {
      case TimerMode.threeMinutes:
      case TimerMode.ninetySeconds:
      case TimerMode.custom:
        unawaited(startNormalMode(thisRunId));
        break;
      case TimerMode.threeMinutesTwoRoundsAbCd:
      case TimerMode.threeMinutesTwoRoundsCdAb:
        unawaited(startThreeMinuteTwoRoundsMode(thisRunId));
        break;
      case TimerMode.fifteenSecondShot:
        unawaited(startFifteenSecondShotMode(thisRunId));
        break;
    }
  }

  Future<void> startNormalMode(int thisRunId) async {
    await playBeeps(2);
    if (!isCurrentRunActive(thisRunId)) return;

    while (remainingSeconds > 10) {
      if (!await waitOneSecond(thisRunId)) return;

      setState(() {
        remainingSeconds--;
      });

      handleNormalModeAnnouncements();
    }

    if (!isCurrentRunActive(thisRunId)) return;

    final completed = await runSynchronizedCountdown(
      thisRunId,
      from: remainingSeconds.clamp(1, 10),
    );
    if (!completed) return;

    await Future.delayed(const Duration(seconds: 1));
    if (!isCurrentRunActive(thisRunId)) return;

    await playBeeps(3);

    if (!mounted || thisRunId != runId) return;

    setState(() {
      isRunning = false;
    });
  }

  void handleNormalModeAnnouncements() {
    if (remainingSeconds == competitionSeconds) {
      unawaited(playOneBeep());
      return;
    }

    switch (selectedMode) {
      case TimerMode.threeMinutes:
        handleThreeMinuteAnnouncements();
        break;
      case TimerMode.ninetySeconds:
        handleNinetySecondAnnouncements();
        break;
      case TimerMode.custom:
        handleCustomAnnouncements();
        break;
      case TimerMode.threeMinutesTwoRoundsAbCd:
      case TimerMode.threeMinutesTwoRoundsCdAb:
      case TimerMode.fifteenSecondShot:
        break;
    }
  }

  void handleThreeMinuteAnnouncements() {
    if (remainingSeconds == 60) {
      unawaited(playSound('1min.wav'));
    } else if (remainingSeconds == 30) {
      unawaited(playSound('30sec.wav'));
    } else if (remainingSeconds == 15) {
      unawaited(playSound('15sec.wav'));
    }
  }

  void handleNinetySecondAnnouncements() {
    if (remainingSeconds == 60) {
      unawaited(playSound('1min_left.wav'));
    } else if (remainingSeconds == 30) {
      unawaited(playSound('30sec.wav'));
    } else if (remainingSeconds == 15) {
      unawaited(playSound('15sec.wav'));
    }
  }

  void handleCustomAnnouncements() {
    if (remainingSeconds == 30) {
      unawaited(playSound('30sec.wav'));
      return;
    }

    if (remainingSeconds == 15) {
      unawaited(playSound('15sec.wav'));
      return;
    }

    if (remainingSeconds <= 10 && remainingSeconds >= 2) {
      
      return;
    }

    // カスタムモードの任意の「○分経過」は、対応音声ファイルがないため
    // 画面表示のみで進行します。
  }

  Future<void> startThreeMinuteTwoRoundsMode(int thisRunId) async {
    setState(() {
      currentThreeMinuteRound = 1;
      remainingSeconds = 190;
    });

    await playBeeps(2);
    if (!isCurrentRunActive(thisRunId)) return;

    while (currentThreeMinuteRound <= totalThreeMinuteRounds) {
      if (!isCurrentRunActive(thisRunId)) return;

      scheduleStandingAnnouncement(thisRunId, currentStandingGroup);

      while (remainingSeconds > 1) {
        if (!await waitOneSecond(thisRunId)) return;

        setState(() {
          remainingSeconds--;
        });

        handleTwoRoundsThreeMinuteAnnouncements();
      }

      if (!isCurrentRunActive(thisRunId)) return;

      final completed = await announceOneThenZero(thisRunId);
      if (!completed) return;

      await Future.delayed(const Duration(seconds: 1));
      if (!isCurrentRunActive(thisRunId)) return;

      if (currentThreeMinuteRound == 1) {
        await playBeeps(2);
        if (!isCurrentRunActive(thisRunId)) return;

        setState(() {
          currentThreeMinuteRound = 2;
          remainingSeconds = 190;
        });
        continue;
      }

      await playBeeps(3);

      if (!mounted || thisRunId != runId) return;

      setState(() {
        isRunning = false;
      });
      return;
    }
  }

  void scheduleStandingAnnouncement(int thisRunId, String standingGroup) {
    // AB立ち・CD立ちの音声ファイルは未使用です。画面表示のみ行います。
  }

  void handleTwoRoundsThreeMinuteAnnouncements() {
    if (remainingSeconds == 180) {
      unawaited(playOneBeep());
    } else if (remainingSeconds == 120) {
      unawaited(playSound('1min.wav'));
    } else if (remainingSeconds == 90) {
      unawaited(playSound('1min30.wav'));
    } else if (remainingSeconds == 60) {
      unawaited(playSound('2min.wav'));
    } else if (remainingSeconds == 30) {
      unawaited(playSound('30sec.wav'));
    } else if (remainingSeconds == 15) {
      unawaited(playSound('15sec.wav'));
    }
  }

  Future<void> startFifteenSecondShotMode(int thisRunId) async {
    setState(() {
      currentShotRound = 1;
      remainingSeconds = shotSeconds;
    });

    // 1回目の準備開始合図
    await playBeeps(2);
    if (!isCurrentRunActive(thisRunId)) return;

    // ピピの1秒後に回数を読み上げる
    await Future.delayed(const Duration(seconds: 1));
    if (!isCurrentRunActive(thisRunId)) return;

    await playSound('shot$currentShotRound.wav');
    if (!isCurrentRunActive(thisRunId)) return;

    while (currentShotRound <= totalShotRounds) {
      if (!isCurrentRunActive(thisRunId)) return;

      // 回数アナウンス後、約4秒待ってピーで射撃開始
      await Future.delayed(const Duration(seconds: 4));
      if (!isCurrentRunActive(thisRunId)) return;

      setState(() {
        remainingSeconds = shotSeconds;
      });

      await playOneBeep();
      if (!isCurrentRunActive(thisRunId)) return;

      // 15秒から11秒までは通常の秒送り
      while (remainingSeconds > 10) {
        if (!await waitOneSecond(thisRunId)) return;
        setState(() {
          remainingSeconds--;
        });
      }

      // 10、9、8……1を表示と音声で同期
      final completed = await runSynchronizedCountdown(
        thisRunId,
        from: remainingSeconds.clamp(1, 10),
      );
      if (!completed) return;

      if (currentShotRound == totalShotRounds) {
        // 10回目だけ競技終了のピーピーピー
        await Future.delayed(const Duration(seconds: 1));
        if (!isCurrentRunActive(thisRunId)) return;

        await playBeeps(3);

        if (!mounted || thisRunId != runId) return;
        setState(() {
          isRunning = false;
        });
        return;
      }

      // 次の回数へ進める
      setState(() {
        currentShotRound++;
        remainingSeconds = shotSeconds;
      });

      // 各回終了直後のピピが、そのまま次の回の準備開始合図
      await playBeeps(2);
      if (!isCurrentRunActive(thisRunId)) return;

      // ピピの1秒後に「15秒しゃ2回目」などと読み上げる
      await Future.delayed(const Duration(seconds: 1));
      if (!isCurrentRunActive(thisRunId)) return;

      await playSound('shot$currentShotRound.wav');
      if (!isCurrentRunActive(thisRunId)) return;
    }
  }

  void stopTimer() {
    runId++;

    setState(() {
      isRunning = false;
    });
  }

  void resetTimer() {
    runId++;

    setState(() {
      isRunning = false;
      currentShotRound = 1;
      currentThreeMinuteRound = 1;
      remainingSeconds = initialSeconds;
    });
  }

  void changeMode(TimerMode? newMode) {
    if (newMode == null || isRunning) return;

    runId++;

    setState(() {
      selectedMode = newMode;
      currentShotRound = 1;
      currentThreeMinuteRound = 1;
      remainingSeconds = initialSeconds;
    });
  }

  void updateCustomTime() {
    if (selectedMode != TimerMode.custom || isRunning) return;

    setState(() {
      remainingSeconds = initialSeconds;
    });
  }

  String formatTime(int totalSeconds) {
    final safeSeconds = totalSeconds < 0 ? 0 : totalSeconds;
    final minutes = safeSeconds ~/ 60;
    final seconds = safeSeconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Color get backgroundColor {
    if (selectedMode == TimerMode.fifteenSecondShot) {
      if (remainingSeconds <= 5) return Colors.red;
      if (remainingSeconds <= 10) return Colors.orange;
      return Colors.green;
    }

    if (remainingSeconds > competitionSeconds) {
      return Colors.yellow.shade700;
    }
    if (remainingSeconds <= 30) return Colors.red;
    if (remainingSeconds <= 60) return Colors.orange;
    return Colors.green;
  }

  String get statusText {
    if (!isRunning) return '待機中';

    if (selectedMode == TimerMode.fifteenSecondShot) {
      return '15秒射 $currentShotRound回目';
    }

    if (isThreeMinuteTwoRoundsMode) {
      if (remainingSeconds > 180) {
        return '$currentThreeMinuteRound立ち目 '
            '$currentStandingGroup・準備時間';
      }
      return '$currentThreeMinuteRound立ち目 '
          '$currentStandingGroup・競技中';
    }

    if (remainingSeconds > competitionSeconds) {
      return '準備時間';
    }
    return '競技中';
  }

  @override
  void dispose() {
    runId++;
    for (final player in soundPlayers.values) {
      unawaited(player.dispose());
    }
    for (final player in beepPlayers) {
      unawaited(player.dispose());
    }
    customMinutesController.dispose();
    customSecondsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final timerFontSize = screenWidth < 500 ? 70.0 : 110.0;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('アーチェリータイマー'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                children: [
                  if (!audioReady)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(),
                    ),
                  SizedBox(
                    width: 370,
                    child: DropdownButtonFormField<TimerMode>(
                      initialValue: selectedMode,
                      decoration: const InputDecoration(
                        labelText: 'タイマーモード',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: TimerMode.values.where((mode) => mode == TimerMode.threeMinutes).map((mode) {
                        return DropdownMenuItem<TimerMode>(
                          value: mode,
                          child: Text(mode.label),
                        );
                      }).toList(),
                      onChanged: isRunning ? null : changeMode,
                    ),
                  ),
                  if (selectedMode == TimerMode.custom) ...[
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: customMinutesController,
                            enabled: !isRunning,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '分',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            onChanged: (_) => updateCustomTime(),
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: customSecondsController,
                            enabled: !isRunning,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '秒',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            onChanged: (_) => updateCustomTime(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '設定した競技時間に準備時間10秒が追加されます',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Text(
                    statusText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (selectedMode == TimerMode.fifteenSecondShot) ...[
                    const SizedBox(height: 10),
                    Text(
                      '$currentShotRound回目／$totalShotRounds回',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  if (isThreeMinuteTwoRoundsMode) ...[
                    const SizedBox(height: 10),
                    Text(
                      '$currentThreeMinuteRound立ち目 '
                      '$currentStandingGroup／$totalThreeMinuteRounds立ち',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    formatTime(remainingSeconds),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: timerFontSize,
                      fontWeight: FontWeight.bold,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 35),
                  Wrap(
                    spacing: 15,
                    runSpacing: 15,
                    alignment: WrapAlignment.center,
                    children: [
                      SizedBox(
                        width: 130,
                        height: 55,
                        child: ElevatedButton(
                          onPressed:
                              isRunning || !audioReady ? null : startTimer,
                          child: const Text(
                            'スタート',
                            style: TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 130,
                        height: 55,
                        child: ElevatedButton(
                          onPressed: isRunning ? stopTimer : null,
                          child: const Text(
                            'ストップ',
                            style: TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 130,
                        height: 55,
                        child: ElevatedButton(
                          onPressed: resetTimer,
                          child: const Text(
                            'リセット',
                            style: TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                        ),
                        onPressed: () => unawaited(playOneBeep()),
                        child: const Text('ビープ音テスト'),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                        ),
                        onPressed: () => unawaited(playSound('1min.wav')),
                        child: const Text('音声テスト'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'ブラウザの音量を上げ、最初に画面上のボタンを押して使用してください。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
