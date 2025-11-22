import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:archive/archive_io.dart';

// --- 日志函数 ---
void log(Object? message, {bool withTime = false}) {
  if (withTime) {
    final now = DateTime.now();
    final year = now.year;
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final timestamp = "$year-$month-$day $hour:$minute";
    stdout.writeln("[$timestamp] $message");
  } else {
    stdout.writeln("$message");
  }
}

// 自动解析 flutter 命令路径
Future<String> resolveFlutterCmd() async {
  if (Platform.isWindows) {
    return 'flutter.bat';
  } else {
    final result = await Process.run('which', ['flutter']);
    if (result.exitCode == 0) {
      final path = (result.stdout as String).trim();
      if (path.isNotEmpty) {
        return path;
      }
    }
    throw Exception('未能找到 flutter 命令，请确认 Flutter SDK 已安装并加入 PATH');
  }
}

// 读取版本号
Future<Map<String, String>> readVersionInfo(String projectRoot) async {
  final pubspecFile = File(p.join(projectRoot, 'pubspec.yaml'));
  if (!await pubspecFile.exists()) {
    throw Exception('未找到 pubspec.yaml 文件');
  }

  final content = await pubspecFile.readAsString();
  final yaml = loadYaml(content);

  final name = yaml['name'] as String? ?? 'app';
  final version = yaml['version'] as String? ?? '0.0.0';

  // 解析版本号（格式：1.0.0+1 或 1.0.0-beta+1）
  final versionParts = version.split('+');
  final versionNumber = versionParts[0]; // 例如 1.0.0 或 1.0.0-beta

  return {'name': name, 'version': versionNumber};
}

// 运行 flutter clean
Future<void> runFlutterClean(
  String projectRoot, {
  bool skipClean = false,
}) async {
  if (skipClean) {
    log('⏭️  跳过构建缓存清理（--dirty 模式）');
    return;
  }

  final flutterCmd = await resolveFlutterCmd();

  log('🧹 正在清理构建缓存...');

  final result = await Process.run(flutterCmd, [
    'clean',
  ], workingDirectory: projectRoot);

  if (result.exitCode != 0) {
    log('❌ 清理失败');
    log(result.stdout);
    log(result.stderr);
    throw Exception('Flutter clean 失败');
  }

  log('✅ 清理完成');
}

// 获取当前平台名称
String getCurrentPlatform() {
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  throw Exception('不支持的平台');
}

// 获取当前架构
String getCurrentArchitecture() {
  // Dart 的 Platform.version 包含架构信息
  // 例如: "2.19.0 (stable) (Thu Feb 9 00:00:00 2023 +0000) on 'windows_x64'"
  final version = Platform.version;

  // 解析架构信息
  if (version.contains('arm64') || version.contains('aarch64')) {
    return 'arm64';
  } else if (version.contains('x64') || version.contains('x86_64')) {
    return 'x64';
  } else if (version.contains('ia32') || version.contains('x86')) {
    return 'x86';
  }

  // 默认返回 x64（大多数桌面平台）
  return 'x64';
}

// 获取构建输出目录
String getBuildOutputDir(String projectRoot, String platform, bool isRelease) {
  final mode = isRelease ? 'Release' : 'Debug';
  final arch = getCurrentArchitecture();

  switch (platform) {
    case 'windows':
      // Windows 支持 x64 和 arm64
      return p.join(projectRoot, 'build', 'windows', arch, 'runner', mode);
    case 'macos':
      return p.join(projectRoot, 'build', 'macos', 'Build', 'Products', mode);
    case 'linux':
      // Linux 支持 x64 和 arm64
      return p.join(
        projectRoot,
        'build',
        'linux',
        arch,
        isRelease ? 'release' : 'debug',
        'bundle',
      );
    case 'apk':
      return p.join(projectRoot, 'build', 'app', 'outputs', 'flutter-apk');
    case 'appbundle':
      return p.join(
        projectRoot,
        'build',
        'app',
        'outputs',
        'bundle',
        isRelease ? 'release' : 'debug',
      );
    default:
      throw Exception('不支持的平台: $platform');
  }
}

// 获取 Android 输出文件名
String getAndroidOutputFile(
  String sourceDir,
  bool isRelease,
  bool isAppBundle,
) {
  final dir = Directory(sourceDir);
  if (!dir.existsSync()) {
    throw Exception('构建目录不存在: $sourceDir');
  }

  if (isAppBundle) {
    // AAB 文件
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.aab'))
        .toList();
    if (files.isEmpty) throw Exception('未找到 .aab 文件');
    return files.first.path;
  } else {
    // APK 文件
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.apk'))
        .toList();
    if (files.isEmpty) throw Exception('未找到 .apk 文件');
    return files.first.path;
  }
}

// 运行 flutter build
Future<void> runFlutterBuild({
  required String projectRoot,
  required String platform,
  required bool isRelease,
  bool isAppBundle = false,
}) async {
  final flutterCmd = await resolveFlutterCmd();
  final mode = isRelease ? 'release' : 'debug';

  final buildTypeLabel = isRelease ? 'Release' : 'Debug';
  log('▶️  正在构建 $platform $buildTypeLabel 版本...');

  // Android 构建命令
  final buildCommand = (platform == 'apk' || platform == 'appbundle')
      ? ['build', isAppBundle ? 'appbundle' : 'apk', '--$mode']
      : ['build', platform, '--$mode'];

  final result = await Process.run(
    flutterCmd,
    buildCommand,
    workingDirectory: projectRoot,
  );

  if (result.exitCode != 0) {
    log('❌ 构建失败');
    log(result.stdout);
    log(result.stderr);
    throw Exception('Flutter 构建失败');
  }

  log('✅ 构建完成');
}

// 生成 Inno Setup 配置（内嵌模板，移除简体中文支持）
String _generateInnoSetupConfig({
  required String appName,
  required String version,
  required String appExeName,
  required String outputDir,
  required String outputFileName,
  required String sourceDir,
  required String archMode,
}) {
  // 生成标准 GUID 格式（使用固定的应用专属 GUID）
  // 注意：每个应用应该有唯一的 GUID，这里使用应用名生成
  final appNameHash = appName.hashCode
      .abs()
      .toRadixString(16)
      .padLeft(8, '0')
      .toUpperCase();
  final guid = 'A1B2C3D4-E5F6-7890-$appNameHash-123456789ABC';

  // Publisher 名称使用应用名称（首字母大写）
  final publisher = appName;

  return '''
; Inno Setup 配置文件 - 由 build.dart 自动生成

#define MyAppName "$appName"
#define MyAppVersion "$version"
#define MyAppPublisher "$publisher"
#define MyAppExeName "$appExeName"

[Setup]
; 应用程序基本信息
AppId={{$guid}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppCopyright=Copyright (C) 2025 {#MyAppPublisher}

; 安装目录
DefaultDirName={autopf}\\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
DisableProgramGroupPage=yes

; 输出配置
OutputDir=$outputDir
OutputBaseFilename=$outputFileName

; 压缩配置
Compression=lzma2/max
SolidCompression=yes

; 安装界面配置
WizardStyle=modern

; 架构配置
$archMode

; 权限配置
; admin: 总是需要管理员权限（安装和卸载都需要）
; lowest: 不需要管理员权限（如果需要会提示）
; 使用 admin 确保卸载时有足够权限清理所有文件
PrivilegesRequired=admin

; 卸载配置
UninstallDisplayIcon={app}\\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
UninstallFilesDir={app}\\uninstall

; 其他配置
DisableWelcomePage=no
DisableDirPage=no
DisableReadyPage=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "$sourceDir\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\\{#MyAppName}"; Filename: "{app}\\{#MyAppExeName}"
Name: "{group}\\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\\{#MyAppName}"; Filename: "{app}\\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; 卸载时删除运行时生成的数据文件夹
Type: filesandordirs; Name: "{app}\\data"

[Code]
function IsProcessRunning(ProcessName: String): Boolean;
var
  ResultCode: Integer;
  Output: AnsiString;
begin
  Result := False;
  if Exec('cmd.exe', '/c tasklist /FI "IMAGENAME eq ' + ProcessName + '" | findstr /i "' + ProcessName + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    // 如果 findstr 返回 0，说明找到了进程
    if ResultCode = 0 then
      Result := True;
  end;
end;

procedure KillProcess(ProcessName: String);
var
  ResultCode: Integer;
  Retries: Integer;
begin
  // taskkill /F /IM 会终止所有匹配的进程实例
  Exec('cmd.exe', '/c taskkill /F /IM ' + ProcessName, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  
  // 等待进程完全停止
  Sleep(500);
  
  // 重试最多 3 次，确保所有实例都被终止
  Retries := 0;
  while IsProcessRunning(ProcessName) and (Retries < 3) do
  begin
    Sleep(500);
    Exec('cmd.exe', '/c taskkill /F /IM ' + ProcessName, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Retries := Retries + 1;
  end;
end;

function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
  MsgText: String;
begin
  // 检查是否已有实例在运行
  if CheckForMutexes('Global\\StelliibertyMutex') then
  begin
    if MsgBox('{#MyAppName} is currently running.' #13#10#13#10 'Please close the application before continuing.', mbError, MB_OK) = IDOK then
    begin
      Result := False;
      Exit;
    end;
  end;
  
  // 检查 clash-core.exe 是否在运行
  if IsProcessRunning('clash-core.exe') then
  begin
    MsgText := 'Clash process is currently running.' #13#10#13#10 +
               'The installer will automatically stop all instances before continuing.' #13#10#13#10 +
               'Continue with installation?';
    
    if MsgBox(MsgText, mbConfirmation, MB_YESNO) = IDYES then
    begin
      // 强制停止所有 clash-core.exe 实例
      KillProcess('clash-core.exe');
      
      // 最终验证是否成功停止
      if IsProcessRunning('clash-core.exe') then
      begin
        MsgBox('Failed to stop all Clash processes.' #13#10#13#10 'Please stop them manually and try again.', mbError, MB_OK);
        Result := False;
        Exit;
      end;
    end
    else
    begin
      Result := False;
      Exit;
    end;
  end;
  
  Result := True;
end;

function GetServicePath(): String;
var
  ResultCode: Integer;
  TempFile: String;
  Lines: TArrayOfString;
  I: Integer;
  Line: String;
  Pos1: Integer;
begin
  Result := '';
  
  // 使用临时文件捕获 sc qc 输出
  // 注意：Inno Setup 的 Exec 不支持直接捕获输出到变量，必须使用文件
  TempFile := ExpandConstant('{tmp}\sc_query_stelliberty.txt');
  
  // 查询服务配置
  if Exec('cmd.exe', '/c sc qc StellibertyService > "' + TempFile + '" 2>&1', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    // 读取输出
    if LoadStringsFromFile(TempFile, Lines) then
    begin
      for I := 0 to GetArrayLength(Lines) - 1 do
      begin
        Line := Trim(Lines[I]);
        // 查找 BINARY_PATH_NAME 行
        if Pos('BINARY_PATH_NAME', Line) > 0 then
        begin
          // 提取路径
          Pos1 := Pos(':', Line);
          if Pos1 > 0 then
          begin
            Result := Trim(Copy(Line, Pos1 + 1, Length(Line)));
            // 移除可能的引号
            StringChangeEx(Result, '"', '', True);
            Break;
          end;
        end;
      end;
    end;
  end;
  
  // 清理临时文件
  if FileExists(TempFile) then
    DeleteFile(TempFile);
end;

function InitializeUninstall(): Boolean;
var
  ResultCode: Integer;
  ServicePath: String;
  MsgText: String;
  AppRunning: Boolean;
  ClashRunning: Boolean;
begin
  // 检查主程序和相关进程是否在运行
  AppRunning := CheckForMutexes('Global\\StelliibertyMutex') or IsProcessRunning('{#MyAppExeName}');
  ClashRunning := IsProcessRunning('clash-core.exe');
  
  // 动态查询 Windows 服务路径
  ServicePath := GetServicePath();
  
  // 构建提示信息
  if ServicePath <> '' then
  begin
    MsgText := 'Windows Service detected at:' #13#10 + ServicePath + #13#10#13#10 +
               'The uninstaller will automatically:' #13#10 +
               '1. Stop and close {#MyAppName} application' #13#10 +
               '2. Stop the Windows Service' #13#10 +
               '3. Remove the Windows Service' #13#10 +
               '4. Stop Clash process' #13#10 +
               '5. Delete service files' #13#10 +
               '6. Uninstall the application' #13#10#13#10;
    
    if AppRunning or ClashRunning then
      MsgText := MsgText + 'Note: Active processes will be forcefully terminated.' #13#10#13#10;
    
    MsgText := MsgText + 'Continue with uninstallation?';
  end
  else
  begin
    MsgText := 'The uninstaller will automatically:' #13#10 +
               '1. Stop and close {#MyAppName} application' #13#10 +
               '2. Stop Clash process' #13#10 +
               '3. Uninstall the application' #13#10#13#10;
    
    if AppRunning or ClashRunning then
      MsgText := MsgText + 'Note: Active processes will be forcefully terminated.' #13#10#13#10;
    
    MsgText := MsgText + 'Continue with uninstallation?';
  end;
  
  // 显示确认对话框
  if MsgBox(MsgText, mbConfirmation, MB_YESNO) = IDNO then
  begin
    Result := False;
    Exit;
  end;
  
  // 强制终止主程序
  if AppRunning then
  begin
    KillProcess('{#MyAppExeName}');
  end;
  
  // 处理 Windows 服务
  if ServicePath <> '' then
  begin
    // 停止服务
    Exec('sc.exe', 'stop StellibertyService', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(1500);
    
    // 删除服务
    Exec('sc.exe', 'delete StellibertyService', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
  
  // 强制停止所有 clash-core.exe 进程
  if ClashRunning then
  begin
    KillProcess('clash-core.exe');
  end;
  
  // 最终验证：确保所有关键进程都已停止
  if IsProcessRunning('{#MyAppExeName}') or IsProcessRunning('clash-core.exe') then
  begin
    MsgBox('Failed to stop all processes.' #13#10#13#10 +
           'Some processes are still running. The uninstaller will continue,' #13#10 +
           'but some files may not be removed.', mbError, MB_OK);
  end;
  
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  AppDir: String;
  ServicePath: String;
  ServiceDir: String;
begin
  // 卸载完成后，清理服务文件和残留目录
  if CurUninstallStep = usPostUninstall then
  begin
    AppDir := ExpandConstant('{app}');
    
    // 动态获取服务路径
    ServicePath := GetServicePath();
    
    if ServicePath <> '' then
    begin
      // 提取服务目录
      ServiceDir := ExtractFileDir(ServicePath);
      
      // 强制删除服务文件（如果存在）
      if FileExists(ServicePath) then
      begin
        DeleteFile(ServicePath);
      end;
      
      // 尝试删除服务目录
      if DirExists(ServiceDir) then
      begin
        RemoveDir(ServiceDir);
      end;
    end;
    
    // 尝试删除安装目录（如果为空）
    RemoveDir(AppDir);
  end;
end;
''';
}

// 使用 Inno Setup 打包为安装程序
Future<void> packInnoSetup({
  required String projectRoot,
  required String sourceDir,
  required String outputPath,
  required String appName,
  required String version,
  required String arch,
}) async {
  if (!Platform.isWindows) {
    throw Exception('Inno Setup 打包仅支持 Windows 平台');
  }

  log('▶️  正在使用 Inno Setup 打包为安装程序...');

  // 检查 Inno Setup 6 是否安装
  final innoSetupPaths = [
    r'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    r'C:\Program Files\Inno Setup 6\ISCC.exe',
  ];

  String? isccPath;
  for (final path in innoSetupPaths) {
    if (await File(path).exists()) {
      isccPath = path;
      break;
    }
  }

  if (isccPath == null) {
    throw Exception(
      '未找到 Inno Setup 编译器 (ISCC.exe)。\n'
      '请运行以下命令安装: dart run scripts/prebuild.dart --installer',
    );
  }

  log('✅ 找到 Inno Setup: $isccPath');

  // 生成 ISS 配置文件
  final appNameCapitalized =
      '${appName.substring(0, 1).toUpperCase()}${appName.substring(1)}';
  // 支持 x64 和 arm64 架构的 Inno Setup 配置
  final archMode = (arch == 'x64' || arch == 'arm64')
      ? 'ArchitecturesInstallIn64BitMode=$arch'
      : '';
  final outputDir = p.dirname(outputPath);
  final outputFileName = p.basenameWithoutExtension(outputPath);

  final issContent = _generateInnoSetupConfig(
    appName: appNameCapitalized,
    version: version,
    appExeName: '$appName.exe',
    outputDir: outputDir,
    outputFileName: outputFileName,
    sourceDir: sourceDir,
    archMode: archMode,
  );

  // 写入临时 ISS 文件
  final issFile = File(p.join(projectRoot, 'build', 'setup.iss'));
  await issFile.parent.create(recursive: true);
  await issFile.writeAsString(issContent);

  log('📝 生成配置文件: ${issFile.path}');

  // 运行 Inno Setup 编译器
  log('🔨 正在编译安装程序...');
  final result = await Process.run(isccPath, [
    issFile.path,
  ], workingDirectory: projectRoot);

  if (result.exitCode != 0) {
    log('❌ Inno Setup 编译失败');
    log(result.stdout);
    log(result.stderr);
    throw Exception('Inno Setup 编译失败');
  }

  // 显示文件大小
  final fileSize = await File(outputPath).length();
  final sizeInMB = (fileSize / (1024 * 1024)).toStringAsFixed(2);
  log('✅ 打包完成: ${p.basename(outputPath)} ($sizeInMB MB)');
}

// 打包为 ZIP（使用 archive 包）
Future<void> packZip({
  required String sourceDir,
  required String outputPath,
}) async {
  log('▶️  正在打包为 ZIP...');

  // 确保输出目录存在
  final outputDir = Directory(p.dirname(outputPath));
  if (!await outputDir.exists()) {
    await outputDir.create(recursive: true);
  }

  // 删除已存在的同名文件
  final outputFile = File(outputPath);
  if (await outputFile.exists()) {
    await outputFile.delete();
  }

  // 创建 Archive 对象
  final archive = Archive();

  // 递归添加所有文件
  final sourceDirectory = Directory(sourceDir);
  final files = sourceDirectory.listSync(recursive: true);

  // 移除压缩包时间戳
  final fixedTimestamp = 0;

  for (final entity in files) {
    if (entity is File) {
      final relativePath = p.relative(entity.path, from: sourceDir);
      final bytes = await entity.readAsBytes();

      // 添加文件到归档，设置固定时间戳
      final archiveFile = ArchiveFile(
        relativePath.replaceAll('\\', '/'), // 统一使用 / 作为路径分隔符
        bytes.length,
        bytes,
      );

      // 移除 ZIP 内文件的时间信息：设置为固定时间戳
      archiveFile.lastModTime = fixedTimestamp;

      archive.addFile(archiveFile);

      // 显示进度
      log('📦 添加: $relativePath');
    }
  }

  log('📦 正在压缩（最大压缩率）...');

  // 使用 ZIP 编码器压缩，设置最大压缩等级（archive 4.x 使用 9）
  final encoder = ZipEncoder();
  final zipData = encoder.encode(archive, level: 9);

  // 写入 ZIP 文件
  await File(outputPath).writeAsBytes(zipData);

  // 移除 ZIP 文件本身的时间戳
  log('🧹 正在移除 ZIP 文件时间戳...');
  final fixedTime = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  final zipFile = File(outputPath);
  await zipFile.setLastModified(fixedTime);
  await zipFile.setLastAccessed(fixedTime);
  log('✅ ZIP 文件时间戳已清除');

  // 显示文件大小
  final fileSize = await File(outputPath).length();
  final sizeInMB = (fileSize / (1024 * 1024)).toStringAsFixed(2);
  log('✅ 打包完成: ${p.basename(outputPath)} ($sizeInMB MB)');
}

// 主函数
Future<void> main(List<String> args) async {
  // 记录开始时间
  final startTime = DateTime.now();

  final parser = ArgParser()
    ..addFlag('debug', negatable: false, help: '构建 Debug 版本（默认只构建 Release）')
    ..addFlag('all', negatable: false, help: '构建所有版本（Release 和 Debug）')
    ..addFlag('clean', negatable: false, help: '执行 flutter clean 进行干净构建')
    ..addFlag('android', negatable: false, help: '构建 Android APK（可在任何平台运行）')
    ..addFlag(
      'appbundle',
      negatable: false,
      help: '构建 Android App Bundle（AAB 格式，用于 Google Play）',
    )
    ..addFlag(
      'all-installers',
      negatable: false,
      help: '生成所有安装包格式（Windows 下同时生成 EXE 安装程序和 ZIP 压缩包）',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: '显示帮助信息');

  ArgResults argResults;
  try {
    argResults = parser.parse(args);
  } catch (e) {
    log('❌ 参数错误: ${e.toString()}\n');
    log(parser.usage);
    exit(1);
  }

  if (argResults['help'] as bool) {
    log('Flutter 多平台打包脚本（桌面平台自动识别）');
    log('\n用法: dart run scripts/build.dart [选项]\n');
    log('选项:');
    log(parser.usage);
    log('\n支持平台: Windows, macOS, Linux, Android (APK/AAB)');
    log('\n示例:');
    log(
      '  dart run scripts/build.dart                       # 打包当前桌面平台 Release',
    );
    log('  dart run scripts/build.dart --debug               # 打包当前桌面平台 Debug');
    log('  dart run scripts/build.dart --android             # 打包 Android APK');
    log('  dart run scripts/build.dart --appbundle           # 打包 Android AAB');
    log('  dart run scripts/build.dart --clean               # 干净构建');
    log(
      '  dart run scripts/build.dart --all-installers      # 生成所有安装包格式（ZIP + EXE，仅 Windows）',
    );
    log('  dart run scripts/build.dart --all --clean          # 干净构建所有版本');
    log(
      '  dart run scripts/build.dart --android --all       # 构建 Android Release 和 Debug',
    );
    exit(0); // 显式退出
  }

  final projectRoot = p.dirname(p.dirname(Platform.script.toFilePath()));

  // 获取参数
  final shouldClean = argResults['clean'] as bool;
  final buildDebug = argResults['debug'] as bool;
  final buildAll = argResults['all'] as bool;
  final isAndroid = argResults['android'] as bool;
  final isAppBundle = argResults['appbundle'] as bool;
  final allInstallers = argResults['all-installers'] as bool;

  // 打包格式：--all-installers 会生成 ZIP 和 EXE 两种格式
  final shouldPackZip = !allInstallers || Platform.isWindows;
  final shouldPackInstaller = allInstallers && Platform.isWindows;

  if (allInstallers && !Platform.isWindows) {
    log('⚠️  警告: --all-installers 仅在 Windows 平台生成 EXE 安装包');
    log('    其他平台将只生成 ZIP 包');
  }

  // 确定要构建的版本
  // 默认：只构建 Release
  // --debug：只构建 Debug
  // --all：构建 Release 和 Debug
  final shouldBuildRelease = !buildDebug || buildAll;
  final shouldBuildDebug = buildDebug || buildAll;

  try {
    // 步骤 1: 识别平台
    String platform;
    bool needZipPack = true;

    if (isAndroid || isAppBundle) {
      // 检查 Android 支持
      final androidDir = Directory(p.join(projectRoot, 'android'));
      if (!await androidDir.exists()) {
        log('❌ 错误: 项目暂未适配 Android 平台');
        exit(1);
      }

      platform = isAppBundle ? 'appbundle' : 'apk';
      needZipPack = false; // Android 不需要打包成 ZIP
      log('📱 构建 Android ${isAppBundle ? 'App Bundle (AAB)' : 'APK'}');
    } else {
      platform = getCurrentPlatform();
      log('🖥️  检测到桌面平台: $platform');
    }

    // 步骤 2: 读取版本信息
    final versionInfo = await readVersionInfo(projectRoot);
    final appName = versionInfo['name']!;
    final version = versionInfo['version']!;

    log('🚀 开始打包 $appName v$version');

    // 步骤 3: 运行 flutter clean（如果指定了 --clean）
    await runFlutterClean(projectRoot, skipClean: !shouldClean);

    // 输出目录
    final outputDir = p.join(projectRoot, 'build', 'packages');

    // 步骤 4: 构建 Release
    if (shouldBuildRelease) {
      await runFlutterBuild(
        projectRoot: projectRoot,
        platform: platform,
        isRelease: true,
        isAppBundle: isAppBundle,
      );

      if (needZipPack) {
        // 桌面平台：打包成 ZIP 或/和 EXE
        final sourceDir = getBuildOutputDir(projectRoot, platform, true);
        final platformSuffix = platform == 'windows'
            ? 'win'
            : (platform == 'macos' ? 'mac' : 'linux');
        final arch = getCurrentArchitecture();

        // 打包为 ZIP
        if (shouldPackZip) {
          final outputPath = p.join(
            outputDir,
            '${appName.substring(0, 1).toUpperCase()}${appName.substring(1)}-v$version-${platformSuffix}_$arch.zip',
          );

          await packZip(sourceDir: sourceDir, outputPath: outputPath);
        }

        // 打包为 Inno Setup 安装程序
        if (shouldPackInstaller) {
          final outputPath = p.join(
            outputDir,
            '${appName.substring(0, 1).toUpperCase()}${appName.substring(1)}-v$version-${platformSuffix}_$arch-setup.exe',
          );

          await packInnoSetup(
            projectRoot: projectRoot,
            sourceDir: sourceDir,
            outputPath: outputPath,
            appName: appName,
            version: version,
            arch: arch,
          );
        }
      } else {
        // Android：直接复制 APK/AAB 文件
        final sourceDir = getBuildOutputDir(projectRoot, platform, true);
        final sourceFile = getAndroidOutputFile(sourceDir, true, isAppBundle);
        final extension = isAppBundle ? 'aab' : 'apk';

        final outputPath = p.join(
          outputDir,
          '${appName.substring(0, 1).toUpperCase()}${appName.substring(1)}-v$version-android.$extension',
        );

        await Directory(outputDir).create(recursive: true);
        await File(sourceFile).copy(outputPath);

        final fileSize = await File(outputPath).length();
        final sizeInMB = (fileSize / (1024 * 1024)).toStringAsFixed(2);
        log('✅ 已复制: ${p.basename(outputPath)} ($sizeInMB MB)');
      }
    }

    // 步骤 5: 构建 Debug
    if (shouldBuildDebug) {
      await runFlutterBuild(
        projectRoot: projectRoot,
        platform: platform,
        isRelease: false,
        isAppBundle: isAppBundle,
      );

      if (needZipPack) {
        // 桌面平台：打包成 ZIP 或/和 EXE
        final sourceDir = getBuildOutputDir(projectRoot, platform, false);
        final platformSuffix = platform == 'windows'
            ? 'win'
            : (platform == 'macos' ? 'mac' : 'linux');
        final arch = getCurrentArchitecture();

        // 打包为 ZIP
        if (shouldPackZip) {
          final outputPath = p.join(
            outputDir,
            '${appName.substring(0, 1).toUpperCase()}${appName.substring(1)}-v$version-${platformSuffix}_$arch-Debug.zip',
          );

          await packZip(sourceDir: sourceDir, outputPath: outputPath);
        }

        // 打包为 Inno Setup 安装程序
        if (shouldPackInstaller) {
          final outputPath = p.join(
            outputDir,
            '${appName.substring(0, 1).toUpperCase()}${appName.substring(1)}-v$version-${platformSuffix}_$arch-Debug-setup.exe',
          );

          await packInnoSetup(
            projectRoot: projectRoot,
            sourceDir: sourceDir,
            outputPath: outputPath,
            appName: appName,
            version: version,
            arch: arch,
          );
        }
      } else {
        // Android：直接复制 APK/AAB 文件
        final sourceDir = getBuildOutputDir(projectRoot, platform, false);
        final sourceFile = getAndroidOutputFile(sourceDir, false, isAppBundle);
        final extension = isAppBundle ? 'aab' : 'apk';

        final outputPath = p.join(
          outputDir,
          '${appName.substring(0, 1).toUpperCase()}${appName.substring(1)}-v$version-android-debug.$extension',
        );

        await Directory(outputDir).create(recursive: true);
        await File(sourceFile).copy(outputPath);

        final fileSize = await File(outputPath).length();
        final sizeInMB = (fileSize / (1024 * 1024)).toStringAsFixed(2);
        log('✅ 已复制: ${p.basename(outputPath)} ($sizeInMB MB)');
      }
    }
    // 计算总耗时
    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);
    final seconds = duration.inMilliseconds / 1000;

    log('🎉 所有打包任务已完成！');
    log('⏱️  总耗时: ${seconds.toStringAsFixed(2)} 秒');
    log('📁 输出目录: $outputDir');
  } catch (e) {
    log('❌ 任务失败: $e');
    exit(1);
  }
}
