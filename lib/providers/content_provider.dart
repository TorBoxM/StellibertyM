import 'package:flutter/material.dart';

// 定义右侧内容区域可显示的视图类型
enum ContentView {
  // 主页相关视图
  home,
  proxy,
  subscriptions,
  overrides,
  connections,
  logs,

  // 设置相关视图
  settingsOverview,
  settingsAppearance,
  settingsLanguage,
  settingsClashFeatures,
  settingsBehavior,
  settingsAppUpdate,

  // Clash 特性子页面（命名以 settings 开头保持侧边栏选中状态）
  settingsClashNetworkSettings,
  settingsClashPortControl,
  settingsClashSystemIntegration,
  settingsClashDnsConfig,
  settingsClashPerformance,
  settingsClashLogsDebug,
}

// 管理右侧内容区域的视图切换
class ContentProvider extends ChangeNotifier {
  ContentView _currentView = ContentView.home;

  // 防抖相关
  DateTime? _lastSwitchTime;
  static const _switchDebounceMs = 200; // 切换防抖时间（毫秒）

  // 获取当前视图类型
  ContentView get currentView => _currentView;

  // 检查是否可以切换（防止快速连续切换）
  bool get _canSwitch {
    if (_lastSwitchTime == null) return true;
    final elapsed = DateTime.now().difference(_lastSwitchTime!).inMilliseconds;
    return elapsed >= _switchDebounceMs;
  }

  // 切换到指定视图，变化时通知监听器
  // 添加防抖机制，防止快速连续切换导致页面重复初始化
  void switchView(ContentView newView) {
    if (_currentView == newView) return;

    // 防抖检查
    if (!_canSwitch) {
      return;
    }

    _currentView = newView;
    _lastSwitchTime = DateTime.now();
    notifyListeners();
  }
}
