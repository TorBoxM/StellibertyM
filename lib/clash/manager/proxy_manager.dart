import 'package:stelliberty/clash/client/clash_core_client.dart';
import 'package:stelliberty/clash/services/delay_test_service.dart';

// Clash 代理管理器
// 负责代理节点的切换、延迟测试
class ProxyManager {
  final ClashCoreClient _coreClient;
  final bool Function() _isCoreRunning;
  final String Function() _getTestUrl;

  ProxyManager({
    required ClashCoreClient coreClient,
    required bool Function() isCoreRunning,
    required String Function() getTestUrl,
  }) : _coreClient = coreClient,
       _isCoreRunning = isCoreRunning,
       _getTestUrl = getTestUrl;

  // 获取代理列表
  Future<Map<String, dynamic>> getProxies() async {
    if (!_isCoreRunning()) {
      throw Exception('Clash 未在运行');
    }

    return await _coreClient.getProxies();
  }

  // 切换代理节点
  Future<bool> changeProxy(String groupName, String proxyName) async {
    if (!_isCoreRunning()) {
      throw Exception('Clash 未在运行');
    }

    final wasSuccessful = await _coreClient.changeProxy(groupName, proxyName);

    // 切换节点后关闭所有现有连接，确保立即生效
    if (wasSuccessful) {
      await _coreClient.closeAllConnections();
    }

    return wasSuccessful;
  }

  // 测试代理延迟（使用 ClashCoreClient）
  Future<int> testProxyDelay(String proxyName, {String? testUrl}) async {
    if (!_isCoreRunning()) {
      throw Exception('Clash 未在运行');
    }

    return await _coreClient.testProxyDelay(
      proxyName,
      testUrl: testUrl ?? _getTestUrl(),
    );
  }

  // 测试单个代理节点延迟
  Future<int> testProxyDelayViaRust(String proxyName, {String? testUrl}) async {
    if (!_isCoreRunning()) {
      throw Exception('Clash 未在运行');
    }

    return await DelayTestService.testProxyDelay(
      proxyName,
      testUrl: testUrl ?? _getTestUrl(),
    );
  }

  // 批量测试代理节点延迟
  Future<Map<String, int>> testGroupDelays(
    List<String> proxyNames, {
    String? testUrl,
    Function(String nodeName)? onNodeStart,
    Function(String nodeName, int delay)? onNodeComplete,
  }) async {
    if (!_isCoreRunning()) {
      throw Exception('Clash 未在运行');
    }

    return await DelayTestService.testGroupDelays(
      proxyNames,
      testUrl: testUrl ?? _getTestUrl(),
      onNodeStart: onNodeStart,
      onNodeComplete: onNodeComplete,
    );
  }
}
