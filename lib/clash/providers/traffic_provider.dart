import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:stelliberty/clash/model/traffic_data_model.dart';
import 'package:stelliberty/clash/manager/clash_manager.dart';
import 'package:stelliberty/clash/state/traffic_states.dart';
import 'package:stelliberty/services/log_print_service.dart';

// 流量统计状态管理
// 订阅流量数据流，管理累计流量和波形图历史
class TrafficProvider extends ChangeNotifier {
  final ClashManager _clashManager = ClashManager.instance;
  StreamSubscription<TrafficData>? _trafficSubscription;
  Timer? _retryTimer;

  TrafficState _state = TrafficState.initial();
  DateTime? _lastTimestamp;

  // Getters
  int get totalUpload => _state.totalUpload;
  int get totalDownload => _state.totalDownload;
  TrafficData? get lastTrafficData => _state.lastTrafficData;
  List<double> get uploadHistory => UnmodifiableListView(_state.uploadHistory);
  List<double> get downloadHistory =>
      UnmodifiableListView(_state.downloadHistory);

  TrafficProvider() {
    _subscribeToTrafficStream();
  }

  // 订阅流量数据流
  void _subscribeToTrafficStream() {
    final stream = _clashManager.trafficStream;

    if (stream != null) {
      _trafficSubscription = stream.listen(
        (trafficData) {
          _handleTrafficData(trafficData);
        },
        onError: (error) {
          Logger.error('流量数据流错误：$error');
        },
      );
      _retryTimer?.cancel();
      _retryTimer = null;
    } else {
      _retryTimer?.cancel();
      _retryTimer = Timer(
        const Duration(seconds: 1),
        _subscribeToTrafficStream,
      );
    }
  }

  // 处理流量数据
  void _handleTrafficData(TrafficData data) {
    final now = data.timestamp;
    int nextTotalUpload = _state.totalUpload;
    int nextTotalDownload = _state.totalDownload;

    if (_lastTimestamp != null) {
      final interval = now.difference(_lastTimestamp!).inMilliseconds / 1000.0;
      if (interval > 0 && interval < 10) {
        nextTotalUpload += (data.upload * interval).round();
        nextTotalDownload += (data.download * interval).round();
      }
    }
    _lastTimestamp = now;

    final nextUploadHistory = List<double>.from(_state.uploadHistory);
    nextUploadHistory.removeAt(0);
    nextUploadHistory.add(data.upload / 1024.0);

    final nextDownloadHistory = List<double>.from(_state.downloadHistory);
    nextDownloadHistory.removeAt(0);
    nextDownloadHistory.add(data.download / 1024.0);

    final nextTrafficData = data.copyWithTotal(
      totalUpload: nextTotalUpload,
      totalDownload: nextTotalDownload,
    );

    _state = _state.copyWith(
      totalUpload: nextTotalUpload,
      totalDownload: nextTotalDownload,
      lastTimestamp: now,
      lastTrafficData: nextTrafficData,
      uploadHistory: nextUploadHistory,
      downloadHistory: nextDownloadHistory,
    );

    notifyListeners();
  }

  // 重置累计流量
  void resetTotalTraffic() {
    _state = TrafficState.initial();
    _lastTimestamp = null;
    Logger.info('累计流量已重置');
    notifyListeners();
  }

  @override
  void dispose() {
    _trafficSubscription?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }
}
