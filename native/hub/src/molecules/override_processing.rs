// 覆写处理分子模块

pub mod downloader;
pub mod js_executor;
pub mod processor;
pub mod yaml_merger;

pub use downloader::{DownloadOverrideRequest, DownloadOverrideResponse};
pub use processor::{
    ApplyOverridesRequest, ApplyOverridesResponse, OverrideProcessor, ParseSubscriptionRequest,
    ParseSubscriptionResponse,
};
pub use yaml_merger::YamlMerger;

// 从分子层共享类型导入
pub use super::{OverrideConfig, OverrideFormat};

pub fn init_listeners() {
    log::info!("初始化覆写处理监听器");
    processor::init_dart_signal_listeners();
    downloader::init_dart_signal_listeners();
}
