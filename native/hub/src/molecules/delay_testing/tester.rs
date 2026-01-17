// Clash 延迟测试模块

use futures_util::stream::{self, StreamExt};
use rinf::{DartSignal, RustSignal};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::spawn;

use crate::atoms::IpcClient;

// Dart → Rust：单节点延迟测试请求
#[derive(Deserialize, DartSignal)]
pub struct SingleDelayTestRequest {
    pub node_name: String,
    pub test_url: String,
    pub timeout_ms: u32,
}

// Rust → Dart：单节点延迟测试结果
#[derive(Serialize, RustSignal)]
pub struct SingleDelayTestResult {
    pub node_name: String,
    pub delay_ms: i32, // -1 表示失败
}

// Dart → Rust：批量延迟测试请求
#[derive(Deserialize, DartSignal)]
pub struct BatchDelayTestRequest {
    pub node_names: Vec<String>,
    pub test_url: String,
    pub timeout_ms: u32,
    pub concurrency: u32,
}

// Rust → Dart：单个节点测试完成（流式进度更新）
#[derive(Serialize, RustSignal)]
pub struct DelayTestProgress {
    pub node_name: String,
    pub delay_ms: i32, // -1 表示失败
}

// Rust → Dart：批量测试完成
#[derive(Serialize, RustSignal)]
pub struct BatchDelayTestComplete {
    pub is_successful: bool,
    pub total_count: u32,
    pub success_count: u32,
    pub error_message: Option<String>,
}

// 批量测试结果
#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct BatchTestResult {
    pub node_name: String,
    pub delay_ms: i32,
}

pub fn init() {
    // 单节点延迟测试请求监听器
    spawn(async {
        let receiver = SingleDelayTestRequest::get_dart_signal_receiver();
        while let Some(dart_signal) = receiver.recv().await {
            spawn(async move {
                handle_single_delay_test_request(dart_signal.message).await;
            });
        }
        log::info!("单节点延迟测试消息通道已关闭，退出监听器");
    });

    // 批量延迟测试请求监听器
    spawn(async {
        let receiver = BatchDelayTestRequest::get_dart_signal_receiver();
        while let Some(dart_signal) = receiver.recv().await {
            spawn(async move {
                handle_batch_delay_test_request(dart_signal.message).await;
            });
        }
        log::info!("批量延迟测试消息通道已关闭，退出监听器");
    });
}

// 处理单节点延迟测试请求
async fn handle_single_delay_test_request(request: SingleDelayTestRequest) {
    log::info!("收到单节点延迟测试请求：{}", request.node_name);

    let delay_ms =
        test_single_node(&request.node_name, &request.test_url, request.timeout_ms).await;

    SingleDelayTestResult {
        node_name: request.node_name,
        delay_ms,
    }
    .send_signal_to_dart();
}

// 处理批量延迟测试请求
async fn handle_batch_delay_test_request(request: BatchDelayTestRequest) {
    log::info!(
        "收到批量延迟测试请求，节点数：{}，并发数：{}",
        request.node_names.len(),
        request.concurrency
    );

    let total_count = request.node_names.len() as u32;
    let node_names = request.node_names;
    let test_url = request.test_url;
    let timeout_ms = request.timeout_ms;
    let concurrency = request.concurrency.max(1) as usize;

    // 进度回调：每个节点测试完成后发送进度信号
    let on_progress = Arc::new(move |node_name: String, delay_ms: i32| {
        DelayTestProgress {
            node_name,
            delay_ms,
        }
        .send_signal_to_dart();
    });

    // 执行批量测试
    let results =
        batch_test_delays(node_names, test_url, timeout_ms, concurrency, on_progress).await;

    // 统计成功数量
    let success_count = results.iter().filter(|r| r.delay_ms > 0).count() as u32;

    // 发送完成信号
    BatchDelayTestComplete {
        is_successful: true,
        total_count,
        success_count,
        error_message: None,
    }
    .send_signal_to_dart();

    log::info!("批量延迟测试完成，成功：{}/{}", success_count, total_count);
}

// 批量延迟测试（并发受限的滑动窗口）。
// 返回所有节点的测试结果列表。
async fn batch_test_delays(
    node_names: Vec<String>,
    test_url: String,
    timeout_ms: u32,
    concurrency: usize,
    on_progress: Arc<dyn Fn(String, i32) + Send + Sync>,
) -> Vec<BatchTestResult> {
    if node_names.is_empty() {
        log::warn!("批量延迟测试：节点列表为空");
        return Vec::new();
    }

    let total = node_names.len();
    log::info!(
        "开始批量延迟测试，节点数：{}，并发数：{}",
        total,
        concurrency
    );

    let test_url = Arc::new(test_url);

    // 创建测试任务流
    let tasks = stream::iter(node_names.into_iter().enumerate())
        .map(|(index, node_name)| {
            let test_url = Arc::clone(&test_url);
            let on_progress = Arc::clone(&on_progress);

            async move {
                log::debug!("开始测试节点 ({}/{}): {}", index + 1, total, node_name);

                // 执行单个节点的延迟测试
                let delay_ms = test_single_node(&node_name, &test_url, timeout_ms).await;

                // 触发进度回调
                on_progress(node_name.clone(), delay_ms);

                Some(BatchTestResult {
                    node_name,
                    delay_ms,
                })
            }
        })
        .buffer_unordered(concurrency) // 滑动窗口并发执行
        .filter_map(|x| async { x }); // 过滤掉 None

    // 收集所有结果
    let results: Vec<BatchTestResult> = tasks.collect().await;

    let success_count = results.iter().filter(|r| r.delay_ms > 0).count();
    log::info!("批量延迟测试完成，成功：{}/{}", success_count, total);

    results
}

// 测试单个节点延迟：通过 IPC 调用 Clash API。
// GET /proxies/{proxyName}/delay?timeout={timeout}&url={testUrl}
async fn test_single_node(node_name: &str, test_url: &str, timeout_ms: u32) -> i32 {
    // 构建 Clash API 路径
    let encoded_name = urlencoding::encode(node_name);
    let path = format!(
        "/proxies/{}/delay?timeout={}&url={}",
        encoded_name, timeout_ms, test_url
    );

    log::debug!("测试节点延迟：{}", node_name);

    let max_retries = 3;
    for attempt in 0..=max_retries {
        match IpcClient::get(&path).await {
            Ok(body) => match serde_json::from_str::<serde_json::Value>(&body) {
                Ok(json) => {
                    if let Some(delay) = json.get("delay").and_then(|v| v.as_i64()) {
                        let delay_i32 = delay as i32;
                        if delay_i32 > 0 {
                            log::info!("节点延迟测试成功：{} - {}ms", node_name, delay_i32);
                        } else {
                            log::warn!("节点延迟测试失败：{} - 超时", node_name);
                        }
                        return delay_i32;
                    } else {
                        log::error!("节点延迟测试响应格式错误：{}", node_name);
                        return -1;
                    }
                }
                Err(e) => {
                    log::error!("节点延迟测试 JSON 解析失败：{} - {}", node_name, e);
                    return -1;
                }
            },
            Err(e) => {
                let should_retry = e.contains("HTTP 503")
                    || e.contains("HTTP 504")
                    || e.contains("os error 231")
                    || e.contains("Named Pipe");

                if attempt < max_retries && should_retry {
                    tokio::time::sleep(std::time::Duration::from_millis(80 * (attempt as u64 + 1)))
                        .await;
                    continue;
                }

                log::warn!("节点延迟测试 IPC 请求失败：{} - {}", node_name, e);
                return -1;
            }
        }
    }

    -1
}
