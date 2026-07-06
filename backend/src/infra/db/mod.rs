pub mod audit;
pub mod bookings;
pub mod catalog;
pub mod chat;
pub mod coupons;
pub mod sessions;
pub mod settings;
pub mod tickets;
pub mod users;
pub mod workers;

use std::time::Duration;

use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;

use crate::config::Config;

const CONNECT_ATTEMPTS: u32 = 6;
const RETRY_DELAY: Duration = Duration::from_secs(5);

/// Connects with retries: on cloud platforms (Render etc.) the database
/// may not accept connections the instant the app boots.
pub async fn connect(config: &Config) -> anyhow::Result<PgPool> {
    let mut last_err = None;
    for attempt in 1..=CONNECT_ATTEMPTS {
        match PgPoolOptions::new()
            .max_connections(config.db_max_connections)
            .acquire_timeout(Duration::from_secs(10))
            .connect(&config.database_url)
            .await
        {
            Ok(pool) => {
                tracing::info!(
                    max_connections = config.db_max_connections,
                    "connected to PostgreSQL"
                );
                return Ok(pool);
            }
            Err(err) => {
                tracing::warn!(
                    attempt,
                    of = CONNECT_ATTEMPTS,
                    error = %err,
                    "PostgreSQL not reachable yet, retrying"
                );
                last_err = Some(err);
                if attempt < CONNECT_ATTEMPTS {
                    tokio::time::sleep(RETRY_DELAY).await;
                }
            }
        }
    }
    Err(anyhow::Error::new(last_err.expect("at least one attempt"))
        .context("connecting to PostgreSQL (check DATABASE_URL, region, and sslmode)"))
}
