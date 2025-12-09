import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:stelliberty/storage/preferences.dart';
import 'package:stelliberty/clash/storage/preferences.dart';
import 'package:stelliberty/services/path_service.dart';
import 'package:stelliberty/utils/logger.dart';

// 备份数据模型
class BackupData {
  final String version;
  final DateTime timestamp;
  final String appVersion;
  final String platform;
  final Map<String, dynamic> data;

  BackupData({
    required this.version,
    required this.timestamp,
    required this.appVersion,
    required this.platform,
    required this.data,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'timestamp': timestamp.toIso8601String(),
    'app_version': appVersion,
    'platform': platform,
    'data': data,
  };

  factory BackupData.fromJson(Map<String, dynamic> json) => BackupData(
    version: json['version'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    appVersion: json['app_version'] as String,
    platform: json['platform'] as String,
    data: json['data'] as Map<String, dynamic>,
  );
}

// 备份服务
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const String backupVersion = '1.0.0';
  static const String backupExtension = '.stelliberty';

  // 并发控制标志
  bool _isOperating = false;

  // 创建备份
  Future<String> createBackup(String targetPath) async {
    // 检查是否正在进行其他操作
    if (_isOperating) {
      throw Exception('正在进行备份或还原操作，请稍后再试');
    }

    _isOperating = true;
    Logger.info('开始创建备份到：$targetPath');

    try {
      // 1. 收集应用配置
      final appPrefs = AppPreferences.instance.getAllSettings();

      // 2. 收集 Clash 配置
      final clashPrefs = ClashPreferences.instance.getAllSettings();

      // 3. 收集订阅数据
      final subscriptions = await _collectSubscriptions();

      // 4. 收集覆写数据
      final overrides = await _collectOverrides();

      // 5. 收集 DNS 配置
      final dnsConfig = await _collectDnsConfig();

      // 6. 收集 PAC 文件
      final pacFile = await _collectPacFile();

      // 7. 构建备份数据
      final packageInfo = await PackageInfo.fromPlatform();
      final backupData = BackupData(
        version: backupVersion,
        timestamp: DateTime.now(),
        appVersion: packageInfo.version,
        platform: Platform.operatingSystem,
        data: {
          'app_preferences': appPrefs,
          'clash_preferences': clashPrefs,
          'subscriptions': subscriptions,
          'overrides': overrides,
          'dns_config': dnsConfig,
          'pac_file': pacFile,
        },
      );

      // 8. 写入文件
      final outputFile = File(targetPath);
      await outputFile.parent.create(recursive: true);
      final jsonStr = const JsonEncoder.withIndent(
        '  ',
      ).convert(backupData.toJson());
      await outputFile.writeAsString(jsonStr);

      Logger.info('备份创建成功：$targetPath');
      return targetPath;
    } catch (e) {
      Logger.error('创建备份失败：$e');
      rethrow;
    } finally {
      _isOperating = false;
    }
  }

  // 还原备份
  Future<void> restoreBackup(String backupPath) async {
    // 检查是否正在进行其他操作
    if (_isOperating) {
      throw Exception('正在进行备份或还原操作，请稍后再试');
    }

    _isOperating = true;

    Logger.info('开始还原备份：$backupPath');

    final backupFile = File(backupPath);
    if (!await backupFile.exists()) {
      throw Exception('备份文件不存在');
    }

    try {
      // 1. 读取并验证备份文件
      final jsonStr = await backupFile.readAsString();
      final jsonData = json.decode(jsonStr);

      // 验证 JSON 结构
      if (jsonData is! Map<String, dynamic>) {
        throw Exception('备份文件格式错误');
      }

      final backupData = BackupData.fromJson(jsonData);

      // 2. 验证版本兼容性
      if (backupData.version != backupVersion) {
        Logger.warning('备份版本不匹配：${backupData.version} != $backupVersion');
        // 当前只支持 1.0.0 版本
        if (backupData.version != '1.0.0') {
          throw Exception('不支持的备份版本：${backupData.version}');
        }
      }

      Logger.info('备份版本：${backupData.version}，时间：${backupData.timestamp}');

      // 3. 验证必要的数据字段
      if (!backupData.data.containsKey('app_preferences') ||
          !backupData.data.containsKey('clash_preferences')) {
        throw Exception('备份文件数据不完整');
      }

      // 4. 还原应用配置
      await _restorePreferences(
        backupData.data['app_preferences'] as Map<String, dynamic>,
        true,
      );

      // 5. 还原 Clash 配置
      await _restorePreferences(
        backupData.data['clash_preferences'] as Map<String, dynamic>,
        false,
      );

      // 6. 还原订阅数据
      await _restoreSubscriptions(
        backupData.data['subscriptions'] as Map<String, dynamic>,
      );

      // 7. 还原覆写数据
      await _restoreOverrides(
        backupData.data['overrides'] as Map<String, dynamic>,
      );

      // 8. 还原 DNS 配置
      await _restoreDnsConfig(backupData.data['dns_config'] as String?);

      // 9. 还原 PAC 文件
      await _restorePacFile(backupData.data['pac_file'] as String?);

      Logger.info('备份还原成功');
    } catch (e) {
      Logger.error('还原备份失败：$e');
      rethrow;
    } finally {
      _isOperating = false;
    }
  }

  // 收集订阅数据
  Future<Map<String, dynamic>> _collectSubscriptions() async {
    final subscriptionsDir = PathService.instance.subscriptionsDir;
    final listPath = PathService.instance.subscriptionListPath;

    final result = <String, dynamic>{
      'list': null,
      'configs': <String, String>{},
    };

    // 读取订阅列表
    final listFile = File(listPath);
    if (await listFile.exists()) {
      result['list'] = await listFile.readAsString();
    }

    // 读取所有订阅配置文件
    final dir = Directory(subscriptionsDir);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.yaml')) {
          final fileName = path.basenameWithoutExtension(entity.path);
          final content = await entity.readAsBytes();
          result['configs'][fileName] = base64Encode(content);
        }
      }
    }

    return result;
  }

  // 收集覆写数据
  Future<Map<String, dynamic>> _collectOverrides() async {
    final overridesDir = PathService.instance.overridesDir;
    final listPath = PathService.instance.overrideListPath;

    final result = <String, dynamic>{'list': null, 'files': <String, String>{}};

    // 读取覆写列表
    final listFile = File(listPath);
    if (await listFile.exists()) {
      result['list'] = await listFile.readAsString();
    }

    // 读取所有覆写文件
    final dir = Directory(overridesDir);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File) {
          final fileName = path.basename(entity.path);
          final content = await entity.readAsBytes();
          result['files'][fileName] = base64Encode(content);
        }
      }
    }

    return result;
  }

  // 收集 DNS 配置
  Future<String?> _collectDnsConfig() async {
    final dnsConfigPath = PathService.instance.dnsConfigPath;
    final file = File(dnsConfigPath);
    if (await file.exists()) {
      final content = await file.readAsBytes();
      return base64Encode(content);
    }
    return null;
  }

  // 收集 PAC 文件
  Future<String?> _collectPacFile() async {
    final pacPath = PathService.instance.pacFilePath;
    final file = File(pacPath);
    if (await file.exists()) {
      final content = await file.readAsBytes();
      return base64Encode(content);
    }
    return null;
  }

  // 还原配置
  Future<void> _restorePreferences(
    Map<String, dynamic> settings,
    bool isAppPrefs,
  ) async {
    if (isAppPrefs) {
      final prefs = AppPreferences.instance;
      for (final entry in settings.entries) {
        final key = entry.key;
        final value = entry.value;

        if (value is String) {
          await prefs.setString(key, value);
        } else if (value is int) {
          await prefs.setInt(key, value);
        } else if (value is double) {
          await prefs.setDouble(key, value);
        } else if (value is bool) {
          await prefs.setBool(key, value);
        }
      }
    } else {
      final prefs = ClashPreferences.instance;
      for (final entry in settings.entries) {
        final key = entry.key;
        final value = entry.value;

        if (value is String) {
          await prefs.setString(key, value);
        } else if (value is int) {
          await prefs.setInt(key, value);
        } else if (value is double) {
          await prefs.setDouble(key, value);
        } else if (value is bool) {
          await prefs.setBool(key, value);
        }
      }
    }

    Logger.info('配置已还原');
  }

  // 还原订阅数据
  Future<void> _restoreSubscriptions(Map<String, dynamic> data) async {
    final subscriptionsDir = PathService.instance.subscriptionsDir;
    final listPath = PathService.instance.subscriptionListPath;

    // 清空现有订阅配置文件
    final dir = Directory(subscriptionsDir);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.yaml')) {
          await entity.delete();
        }
      }
    }

    // 还原订阅列表
    if (data['list'] != null) {
      final listFile = File(listPath);
      await listFile.parent.create(recursive: true);
      await listFile.writeAsString(data['list'] as String);
    }

    // 还原订阅配置文件
    final configs = data['configs'] as Map<String, dynamic>;
    for (final entry in configs.entries) {
      final fileName = entry.key;
      final base64Content = entry.value as String;
      final content = base64Decode(base64Content);

      final filePath = path.join(subscriptionsDir, '$fileName.yaml');
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(content);
    }

    Logger.info('订阅数据已还原');
  }

  // 还原覆写数据
  Future<void> _restoreOverrides(Map<String, dynamic> data) async {
    final overridesDir = PathService.instance.overridesDir;
    final listPath = PathService.instance.overrideListPath;

    // 清空现有覆写文件
    final dir = Directory(overridesDir);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File) {
          await entity.delete();
        }
      }
    }

    // 还原覆写列表
    if (data['list'] != null) {
      final listFile = File(listPath);
      await listFile.parent.create(recursive: true);
      await listFile.writeAsString(data['list'] as String);
    }

    // 还原覆写文件
    final files = data['files'] as Map<String, dynamic>;
    for (final entry in files.entries) {
      final fileName = entry.key;
      final base64Content = entry.value as String;
      final content = base64Decode(base64Content);

      final filePath = path.join(overridesDir, fileName);
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(content);
    }

    Logger.info('覆写数据已还原');
  }

  // 还原 DNS 配置
  Future<void> _restoreDnsConfig(String? base64Content) async {
    if (base64Content == null) return;

    final dnsConfigPath = PathService.instance.dnsConfigPath;
    final content = base64Decode(base64Content);
    final file = File(dnsConfigPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(content);

    Logger.info('DNS 配置已还原');
  }

  // 还原 PAC 文件
  Future<void> _restorePacFile(String? base64Content) async {
    if (base64Content == null) return;

    final pacPath = PathService.instance.pacFilePath;
    final content = base64Decode(base64Content);
    final file = File(pacPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(content);

    Logger.info('PAC 文件已还原');
  }

  // 生成备份文件名
  String generateBackupFileName() {
    final now = DateTime.now();
    final timestamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    return 'backup_$timestamp$backupExtension';
  }
}
