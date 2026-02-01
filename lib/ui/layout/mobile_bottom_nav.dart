import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stelliberty/providers/content_provider.dart';
import 'package:stelliberty/i18n/i18n.dart';

// 移动端底部导航栏
// 提供主要功能页面的快速切换
class MobileBottomNav extends StatelessWidget {
  const MobileBottomNav({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ContentProvider>(context);
    final currentView = provider.currentView;
    final trans = context.translate;

    // 根据当前视图确定选中的底部导航项
    final selectedIndex = _getSelectedIndex(currentView);

    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) {
        final view = _getViewFromIndex(index);
        provider.switchView(view);
      },
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home_rounded),
          label: trans.sidebar.home,
        ),
        NavigationDestination(
          icon: const Icon(Icons.link_outlined),
          selectedIcon: const Icon(Icons.link_rounded),
          label: trans.sidebar.subscriptions,
        ),
        NavigationDestination(
          icon: const Icon(Icons.lan_outlined),
          selectedIcon: const Icon(Icons.lan_rounded),
          label: trans.sidebar.proxy,
        ),
        NavigationDestination(
          icon: const Icon(Icons.settings_outlined),
          selectedIcon: const Icon(Icons.settings_rounded),
          label: trans.sidebar.settings,
        ),
      ],
    );
  }

  // 根据当前视图获取底部导航索引
  int _getSelectedIndex(ContentView view) {
    switch (view) {
      case ContentView.home:
        return 0;
      case ContentView.subscriptions:
      case ContentView.overrides:
      case ContentView.rules:
        return 1;
      case ContentView.proxy:
      case ContentView.connections:
        return 2;
      case ContentView.logs:
      case ContentView.settingsOverview:
      case ContentView.settingsAppearance:
      case ContentView.settingsBehavior:
      case ContentView.settingsLanguage:
      case ContentView.settingsClashFeatures:
      case ContentView.settingsClashNetworkSettings:
      case ContentView.settingsClashPortControl:
      case ContentView.settingsClashSystemIntegration:
      case ContentView.settingsClashDnsConfig:
      case ContentView.settingsClashPerformance:
      case ContentView.settingsClashLogsDebug:
      case ContentView.settingsBackup:
      case ContentView.settingsAppUpdate:
      case ContentView.settingsAccessControl:
        return 3;
    }
  }

  // 根据底部导航索引获取对应视图
  ContentView _getViewFromIndex(int index) {
    switch (index) {
      case 0:
        return ContentView.home;
      case 1:
        return ContentView.subscriptions;
      case 2:
        return ContentView.proxy;
      case 3:
        return ContentView.settingsOverview;
      default:
        return ContentView.home;
    }
  }
}
