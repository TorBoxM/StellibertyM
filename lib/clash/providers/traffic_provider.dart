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
    _trafficSubscription = _clashManager.trafficStream?.listen(
      (trafficData) {
        _handleTrafficData(trafficData);
      },
      onError: (error) {
        Logger.error('流量数据流错误：$error');
      },
    );
  }

  // 处理流量数据
  void _handleTrafficData(TrafficData data) {
    final now = data.timestamp;
    int newTotalUpload = _state.totalUpload;
    int newTotalDownload = _state.totalDownload;

    if (_lastTimestamp != null) {
      final interval = now.difference(_lastTimestamp!).inMilliseconds / 1000.0;
      if (interval > 0 && interval < 10) {
        newTotalUpload += (data.upload * interval).round();
        newTotalDownload += (data.download * interval).round();
      }
    }
    _lastTimestamp = now;

    final newUploadHistory = List<double>.from(_state.uploadHistory);
    newUploadHistory.removeAt(0);
    newUploadHistory.add(data.upload / 1024.0);

    final newDownloadHistory = List<double>.from(_state.downloadHistory);
    newDownloadHistory.removeAt(0);
    newDownloadHistory.add(data.download / 1024.0);

    final newTrafficData = data.copyWithTotal(
      totalUpload: newTotalUpload,
      totalDownload: newTotalDownload,
    );

    _state = _state.copyWith(
      totalUpload: newTotalUpload,
      totalDownload: newTotalDownload,
      lastTimestamp: now,
      lastTrafficData: newTrafficData,
      uploadHistory: newUploadHistory,
      downloadHistory: newDownloadHistory,
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
    super.dispose();
  }
}
