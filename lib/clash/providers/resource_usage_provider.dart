import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:rinf/rinf.dart';
import 'package:stelliberty/clash/providers/clash_provider.dart';
import 'package:stelliberty/services/log_print_service.dart';
import 'package:stelliberty/src/bindings/signals/signals.dart';

class ResourceUsageProvider extends ChangeNotifier {
  ResourceUsageProvider(this._clashProvider) {
    _clashProvider.addListener(_handleCoreStateChanged);
    _startAppMemoryTimer();
    if (_clashProvider.isCoreRunning) {
      _startMemoryStream();
    } else {
      _refreshAppMemory();
    }
  }

  static const Duration _appRefreshInterval = Duration(seconds: 2);

  final ClashProvider _clashProvider;

  Timer? _appRefreshTimer;
  StreamSubscription<RustSignalPack<IpcMemoryData>>? _memorySubscription;
  bool _isMemoryStreamActive = false;

  int? _appMemoryBytes;
  int? _coreMemoryBytes;

  int? get appMemoryBytes => _appMemoryBytes;
  int? get coreMemoryBytes => _coreMemoryBytes;

  void _handleCoreStateChanged() {
    if (_clashProvider.isCoreRunning) {
      _startMemoryStream();
      return;
    }

    _stopMemoryStream();
    final shouldNotify = _coreMemoryBytes != null;
    _coreMemoryBytes = null;
    if (shouldNotify) {
      notifyListeners();
    }
    _refreshAppMemory();
  }

  void _startAppMemoryTimer() {
    _appRefreshTimer?.cancel();
    _appRefreshTimer = Timer.periodic(_appRefreshInterval, (_) {
      _refreshAppMemory();
    });
  }

  void _startMemoryStream() {
    if (_isMemoryStreamActive) {
      return;
    }

    _isMemoryStreamActive = true;
    _memorySubscription?.cancel();
    _memorySubscription = IpcMemoryData.rustSignalStream.listen(
      _handleMemoryData,
      onError: (error) {
        Logger.warning('核心内存数据流错误：$error');
      },
    );

    const StartMemoryStream().sendSignalToRust();
  }

  void _stopMemoryStream() {
    if (!_isMemoryStreamActive) {
      return;
    }

    _isMemoryStreamActive = false;
    const StopMemoryStream().sendSignalToRust();
    _memorySubscription?.cancel();
    _memorySubscription = null;
  }

  void _handleMemoryData(RustSignalPack<IpcMemoryData> signal) {
    final nextCoreMemoryBytes = signal.message.inuse.toInt();
    final nextAppMemoryBytes = _readAppMemoryBytes();
    final resolvedAppMemoryBytes = nextAppMemoryBytes ?? _appMemoryBytes;

    final shouldNotify =
        nextCoreMemoryBytes != _coreMemoryBytes ||
        resolvedAppMemoryBytes != _appMemoryBytes;

    _coreMemoryBytes = nextCoreMemoryBytes;
    if (nextAppMemoryBytes != null) {
      _appMemoryBytes = nextAppMemoryBytes;
    }

    if (shouldNotify) {
      notifyListeners();
    }
  }

  int? _readAppMemoryBytes() {
    try {
      return ProcessInfo.currentRss;
    } catch (e) {
      Logger.warning('获取应用内存失败：$e');
      return null;
    }
  }

  void _refreshAppMemory() {
    final nextAppMemoryBytes = _readAppMemoryBytes();
    if (nextAppMemoryBytes == null) {
      return;
    }

    if (nextAppMemoryBytes != _appMemoryBytes) {
      _appMemoryBytes = nextAppMemoryBytes;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _stopMemoryStream();
    _appRefreshTimer?.cancel();
    _clashProvider.removeListener(_handleCoreStateChanged);
    super.dispose();
  }
}
