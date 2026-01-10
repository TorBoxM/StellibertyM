import 'dart:async';
import 'package:flutter/material.dart';
import 'package:stelliberty/clash/model/connection_model.dart';
import 'package:stelliberty/clash/state/connection_states.dart' as state;
import 'package:stelliberty/clash/providers/clash_provider.dart';
import 'package:stelliberty/clash/manager/clash_manager.dart';
import 'package:stelliberty/services/log_print_service.dart';

// 连接管理 Provider
// 负责定时获取和管理 Clash 连接信息
class ConnectionProvider extends ChangeNotifier {
  final ClashProvider _clashProvider;

  // 直连标识（常量）
  static const String _directProxy = 'DIRECT';

  // 状态
  state.ConnectionState _state = state.ConnectionState.initial();

  // 过滤后的连接列表缓存
  List<ConnectionInfo>? _cachedFilteredConnections;

  // 过滤后的连接列表
  List<ConnectionInfo> get connections {
    _cachedFilteredConnections ??= _getFilteredConnections();
    return _cachedFilteredConnections!;
  }

  // Getters
  bool get isLoading => _state.isLoading;
  String? get errorMessage => _state.errorMessage;
  bool get isMonitoringPaused => _state.isMonitoringPaused;
  state.ConnectionFilterLevel get filterLevel => _state.filterLevel;
  String get searchKeyword => _state.searchKeyword;

  // 定时器（用于自动刷新）
  Timer? _refreshTimer;

  // 刷新间隔（秒）
  static const int _refreshIntervalSeconds = 1;

  ConnectionProvider(this._clashProvider) {
    // 监听 Clash 运行状态
    // 先移除可能存在的旧监听器，防止重复添加
    _clashProvider.removeListener(_onClashStateChanged);
    _clashProvider.addListener(_onClashStateChanged);

    // 如果 Clash 已经在运行，立即开始刷新
    if (_clashProvider.isCoreRunning) {
      startAutoRefresh();
    }
  }

  // 当 Clash 状态改变时
  void _onClashStateChanged() {
    if (_clashProvider.isCoreRunning) {
      // Clash 启动，开始自动刷新
      startAutoRefresh();
    } else {
      // Clash 停止，重置状态
      stopAutoRefresh();
      _state = state.ConnectionState.initial();
      _cachedFilteredConnections = null;
      notifyListeners();
    }
  }

  // 开始自动刷新
  void startAutoRefresh() {
    // 如果已经在运行，不重复启动
    if (_refreshTimer != null && _refreshTimer!.isActive) {
      return;
    }

    // 停止定时器
    stopAutoRefresh(silent: true);

    // 立即刷新一次
    refreshConnections();

    // 启动定时器
    _refreshTimer = Timer.periodic(
      const Duration(seconds: _refreshIntervalSeconds),
      (_) {
        // 只有在未暂停时才刷新
        if (!_state.isMonitoringPaused) {
          refreshConnections();
        }
      },
    );

    Logger.info('连接列表自动刷新已启动（间隔：$_refreshIntervalSeconds 秒）');
  }

  // 停止自动刷新
  void stopAutoRefresh({bool silent = false}) {
    if (_refreshTimer != null) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      if (!silent) {
        Logger.info('连接列表自动刷新已停止');
      }
    }
  }

  // 暂停/恢复自动刷新（监控）
  void togglePause() {
    _state = _state.copyWith(isMonitoringPaused: !_state.isMonitoringPaused);
    Logger.info('连接列表自动刷新已${_state.isMonitoringPaused ? "暂停" : "恢复"}');
    notifyListeners();
  }

  // 设置过滤级别
  void setFilterLevel(state.ConnectionFilterLevel level) {
    _state = _state.copyWith(filterLevel: level);
    _cachedFilteredConnections = null;
    Logger.info('连接过滤级别已设置为：${level.name}');
    notifyListeners();
  }

  // 设置搜索关键字
  void setSearchKeyword(String keyword) {
    _state = _state.copyWith(searchKeyword: keyword);
    _cachedFilteredConnections = null;
    Logger.debug('连接搜索关键字已设置为: $keyword');
    notifyListeners();
  }

  // 获取过滤后的连接列表
  List<ConnectionInfo> _getFilteredConnections() {
    List<ConnectionInfo> filtered = _state.connections;

    // 1. 按过滤级别筛选
    switch (_state.filterLevel) {
      case state.ConnectionFilterLevel.direct:
        filtered = filtered
            .where((conn) => conn.proxyNode == _directProxy)
            .toList();
        break;
      case state.ConnectionFilterLevel.proxy:
        filtered = filtered
            .where((conn) => conn.proxyNode != _directProxy)
            .toList();
        break;
      case state.ConnectionFilterLevel.all:
        // 不过滤
        break;
    }

    // 2. 按关键字筛选（优化：避免每个连接都重复调用 toLowerCase）
    if (_state.searchKeyword.isNotEmpty) {
      final keyword = _state.searchKeyword.toLowerCase();
      filtered = filtered.where((conn) {
        // 缓存 toLowerCase 结果，避免重复计算
        final descLower = conn.metadata.description.toLowerCase();
        final proxyLower = conn.proxyNode.toLowerCase();
        final ruleLower = conn.rule.toLowerCase();
        final processLower = conn.metadata.process.toLowerCase();

        return descLower.contains(keyword) ||
            proxyLower.contains(keyword) ||
            ruleLower.contains(keyword) ||
            processLower.contains(keyword);
      }).toList();
    }

    return filtered;
  }

  // 刷新连接列表
  Future<void> refreshConnections() async {
    if (!_clashProvider.isCoreRunning) {
      return;
    }

    try {
      final connections = await ClashManager.instance.getConnections();

      // 检查数据是否真正发生了变化
      final hasChanged = _hasConnectionsChanged(
        _state.connections,
        connections,
      );

      _state = _state.copyWith(
        connections: connections,
        isLoading: false,
        errorMessage: null,
      );

      // 只在数据真正变化时才通知
      if (hasChanged) {
        _cachedFilteredConnections = null;
        notifyListeners();
        final filteredCount = _getFilteredConnections().length;
        Logger.debug(
          '连接列表已更新：原始 ${connections.length} 个，过滤后 $filteredCount 个（过滤级别：${_state.filterLevel.name}，搜索关键字：${_state.searchKeyword.isEmpty ? "无" : _state.searchKeyword}）',
        );
      }
    } catch (e) {
      _state = _state.copyWith(isLoading: false, errorMessage: '刷新连接列表失败: $e');
      Logger.error(_state.errorMessage!);
      notifyListeners();
    }
  }

  // 检查连接列表是否发生变化
  bool _hasConnectionsChanged(
    List<ConnectionInfo> oldList,
    List<ConnectionInfo> newList,
  ) {
    // 数量不同，肯定有变化
    if (oldList.length != newList.length) {
      return true;
    }

    // 数量相同但为空，认为没变化
    if (oldList.isEmpty) {
      return false;
    }

    // 创建 ID 集合进行快速比较
    final oldIds = oldList.map((c) => c.id).toSet();
    final newIds = newList.map((c) => c.id).toSet();

    // 比较 ID 集合是否相同
    return !oldIds.containsAll(newIds) || !newIds.containsAll(oldIds);
  }

  // 关闭指定连接
  Future<bool> closeConnection(String connectionId) async {
    return _executeConnectionOperation(
      () => ClashManager.instance.closeConnection(connectionId),
      '关闭连接',
      '连接已关闭: $connectionId',
    );
  }

  // 关闭所有连接
  Future<bool> closeAllConnections() async {
    return _executeConnectionOperation(
      ClashManager.instance.closeAllConnections,
      '关闭所有连接',
      '所有连接已关闭',
    );
  }

  // 执行连接操作的公共逻辑
  Future<bool> _executeConnectionOperation(
    Future<bool> Function() operation,
    String operationName,
    String successMessage,
  ) async {
    if (!_clashProvider.isCoreRunning) {
      Logger.warning('Clash 未运行，无法$operationName');
      return false;
    }

    try {
      final success = await operation();

      if (success) {
        Logger.info(successMessage);
        // 立即刷新连接列表
        await refreshConnections();
      }

      return success;
    } catch (e) {
      Logger.error('$operationName失败：$e');
      return false;
    }
  }

  @override
  void dispose() {
    stopAutoRefresh();
    _clashProvider.removeListener(_onClashStateChanged);
    super.dispose();
  }
}
