// IPC 客户端原子模块：提供基础 IPC 通信能力。
// 不包含连接池与重试策略。

mod client;

pub use client::{IpcClient, IpcHttpResponse};
