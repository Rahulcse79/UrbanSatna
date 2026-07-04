pub mod audit;
pub mod bookings;
pub mod catalog;
pub mod sessions;
pub mod settings;
pub mod users;

use std::time::Duration;

use anyhow::Context;
use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;

use crate::config::Config;

pub async fn connect(config: &Config) -> anyhow::Result<PgPool> {
    let pool = PgPoolOptions::new()
        .max_connections(config.db_max_connections)
        .acquire_timeout(Duration::from_secs(5))
        .connect(&config.database_url)
        .await
        .context("connecting to PostgreSQL")?;
    tracing::info!(
        max_connections = config.db_max_connections,
        "connected to PostgreSQL"
    );
    Ok(pool)
}
