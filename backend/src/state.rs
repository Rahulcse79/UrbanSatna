use std::sync::Arc;

use crate::config::Config;
use crate::infra::bot::SupportBot;

#[derive(Clone)]
pub struct AppState {
    #[allow(dead_code)] // first consumer is Phase 1 auth (JWT settings)
    pub config: Arc<Config>,
    pub pg: sqlx::PgPool,
    pub redis: redis::aio::ConnectionManager,
    pub bot: SupportBot,
}

impl AppState {
    pub fn new(config: Config, pg: sqlx::PgPool, redis: redis::aio::ConnectionManager) -> Self {
        let bot = SupportBot::new(&config);
        Self {
            config: Arc::new(config),
            pg,
            redis,
            bot,
        }
    }
}
