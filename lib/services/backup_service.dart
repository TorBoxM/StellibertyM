import 'dart:async';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:stelliberty/services/path_service.dart';
import 'package:stelliberty/services/log_print_service.dart';
import 'package:stelliberty/src/bindings/signals/signals.dart';

// 备份相关异常类型
enum BackupErrorType {
  fileNotFound,
  invalidFormat,
  versionMismatch,
  dataIncomplete,
  operationInProgress,
  timeout,
  unknown,
}

class BackupException implements Exception {
  final BackupErrorType type;
  final String message;
  final Object? originalError;

  BackupException({
    required this.type,
    required this.message,
    this.originalError,
  });

  factory BackupException.fileNotFound(String path) {
    return BackupException(
      type: BackupErrorType.fileNotFound,
      message: '备份文件不存在：$path',
    );
  }

  factory BackupException.invalidFormat() {
    return BackupException(
      type: BackupErrorType.invalidFormat,
      message: '备份文件格式错误',
    );
  }

  factory BackupException.versionMismatch(String backupVersion, String appVersion) {
    return BackupException(
      type: BackupErrorType.versionMismatch,
      message: '备份版本不匹配：备份版本 $backupVersion，应用版本 $appVersion',
    );
  }

  factory BackupException.dataIncomplete() {
    return BackupException(
      type: BackupErrorType.dataIncomplete,
      message: '备份数据不完整',
    );
  }

  factory BackupException.operationInProgress() {
    return BackupException(
      type: BackupErrorType.operationInProgress,
      message: '正在进行备份或还原操作，请稍后再试',
    );
  }

  factory BackupException.timeout() {
    return BackupException(
      type: BackupErrorType.timeout,
      message: '备份操作超时',
    );
  }

  factory BackupException.unknown(Object error) {
    return BackupException(
      type: BackupErrorType.unknown,
      message: '未知错误：$error',
      originalError: error,
    );
  }

  @override
  String toString() => message;
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
      throw BackupException.operationInProgress();
    }

    _isOperating = true;

    try {
      // 使用 Rust 层创建备份
      final completer = Completer<BackupOperationResult>();
      StreamSubscription? subscription;

      try {
        // 订阅 Rust 响应流
        subscription = BackupOperationResult.rustSignalStream.listen((result) {
          if (!completer.isCompleted) {
            completer.complete(result.message);
          }
        });

        // 获取应用版本
        final packageInfo = await PackageInfo.fromPlatform();

        // 获取所有路径
        final pathService = PathService.instance;
        final preferencesPath =
            '${pathService.appDataPath}/shared_preferences_dev.json';

        // 发送创建备份请求到 Rust
        final request = CreateBackupRequest(
          targetPath: targetPath,
          appVersion: packageInfo.version,
          preferencesPath: preferencesPath,
          subscriptionsDir: pathService.subscriptionsDir,
          subscriptionsListPath: pathService.subscriptionListPath,
          overridesDir: pathService.overridesDir,
          overridesListPath: pathService.overrideListPath,
          dnsConfigPath: pathService.dnsConfigPath,
          pacFilePath: pathService.pacFilePath,
        );
        request.sendSignalToRust();

        // 等待备份结果
        final result = await completer.future.timeout(
          const Duration(seconds: 60),
          onTimeout: () => throw BackupException.timeout(),
        );

        if (!result.isSuccessful) {
          final errorMessage = result.errorMessage ?? '备份创建失败';
          throw _mapMessageToBackupException(errorMessage);
        }

        return result.message;
      } finally {
        await subscription?.cancel();
      }
    } catch (e) {
      Logger.error('创建备份失败：$e');
      if (e is BackupException) {
        rethrow;
      }
      throw _toBackupException(e);
    } finally {
      _isOperating = false;
    }
  }

  // 还原备份
  Future<void> restoreBackup(String backupPath) async {
    // 检查是否正在进行其他操作
    if (_isOperating) {
      throw BackupException.operationInProgress();
    }

    _isOperating = true;

    try {
      // 使用 Rust 层还原备份
      final completer = Completer<BackupOperationResult>();
      StreamSubscription? subscription;

      try {
        // 订阅 Rust 响应流
        subscription = BackupOperationResult.rustSignalStream.listen((result) {
          if (!completer.isCompleted) {
            completer.complete(result.message);
          }
        });

        // 获取所有路径
        final pathService = PathService.instance;
        final preferencesPath =
            '${pathService.appDataPath}/shared_preferences_dev.json';

        // 发送还原备份请求到 Rust
        final request = RestoreBackupRequest(
          backupPath: backupPath,
          preferencesPath: preferencesPath,
          subscriptionsDir: pathService.subscriptionsDir,
          subscriptionsListPath: pathService.subscriptionListPath,
          overridesDir: pathService.overridesDir,
          overridesListPath: pathService.overrideListPath,
          dnsConfigPath: pathService.dnsConfigPath,
          pacFilePath: pathService.pacFilePath,
        );
        request.sendSignalToRust();

        // 等待还原结果
        final result = await completer.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw BackupException.timeout(),
        );

        if (!result.isSuccessful) {
          final errorMessage = result.errorMessage ?? '备份还原失败';
          throw _mapMessageToBackupException(errorMessage);
        }
      } finally {
        await subscription?.cancel();
      }
    } catch (e) {
      Logger.error('还原备份失败：$e');
      if (e is BackupException) {
        rethrow;
      }
      throw _toBackupException(e);
    } finally {
      _isOperating = false;
    }
  }

  BackupException _toBackupException(Object error) {
    if (error is BackupException) {
      return error;
    }
    return _mapMessageToBackupException(error.toString(), originalError: error);
  }

  BackupException _mapMessageToBackupException(
    String message, {
    Object? originalError,
  }) {
    final lowerMessage = message.toLowerCase();

    if (_containsAny(message, const ['不存在', '找不到']) ||
        _containsAny(
          lowerMessage,
          const ['not found', 'no such file', 'cannot find'],
        )) {
      return BackupException(
        type: BackupErrorType.fileNotFound,
        message: message,
        originalError: originalError,
      );
    }

    if (_containsAny(message, const ['格式', '解析']) ||
        _containsAny(lowerMessage, const ['format', 'expected', 'json'])) {
      return BackupException.invalidFormat();
    }

    if (_containsAny(message, const ['版本', '不支持']) ||
        _containsAny(lowerMessage, const ['version'])) {
      return BackupException(
        type: BackupErrorType.versionMismatch,
        message: message,
        originalError: originalError,
      );
    }

    if (_containsAny(message, const ['不完整']) ||
        _containsAny(lowerMessage, const ['incomplete'])) {
      return BackupException.dataIncomplete();
    }

    return BackupException.unknown(originalError ?? message);
  }

  bool _containsAny(String source, List<String> keywords) {
    return keywords.any(source.contains);
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
