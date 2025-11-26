pub mod init_logger;
mod messages;

pub fn init() {
    init_logger::setup_logger();
}
