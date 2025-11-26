// 应用日志控制消息协议（Dart → Rust 同步开关状态）

use rinf::{DartSignal, RustSignal};
use serde::{Deserialize, Serialize};
use tokio::spawn;

#[derive(Deserialize, DartSignal)]
pub struct SetAppLogEnabled {
    pub enabled: bool,
}

#[derive(Serialize, RustSignal)]
pub struct SetAppLogEnabledResult {
    pub success: bool,
}

impl SetAppLogEnabled {
    pub fn handle(&self) {
        super::init_logger::set_app_log_enabled(self.enabled);
        SetAppLogEnabledResult { success: true }.send_signal_to_dart();
    }
}

pub fn init() {
    spawn(async {
        let receiver = SetAppLogEnabled::get_dart_signal_receiver();
        while let Some(dart_signal) = receiver.recv().await {
            let message = dart_signal.message;
            message.handle();
        }
    });
}
