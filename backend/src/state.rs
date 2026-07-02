use std::sync::Arc;

use crate::config::Config;

#[derive(Clone)]
pub struct AppState {
    #[allow(dead_code)] // first consumer is Phase 1 auth (JWT settings)
    pub config: Arc<Config>,
    pub pg: sqlx::PgPool,
    pub redis: redis::aio::ConnectionManager,
}

impl AppState {
    pub fn new(config: Config, pg: sqlx::PgPool, redis: redis::aio::ConnectionManager) -> Self {
        Self {
            config: Arc::new(config),
            pg,
            redis,
        }
    }
}
