use anyhow::Context;
use redis::aio::ConnectionManager;

use crate::config::Config;

pub async fn connect(config: &Config) -> anyhow::Result<ConnectionManager> {
    let client = redis::Client::open(config.redis_url.as_str()).context("parsing REDIS_URL")?;
    let mut last_err = None;
    for attempt in 1..=6u32 {
        match client.get_connection_manager().await {
            Ok(mut manager) => {
                // Verify at startup rather than on the first request.
                redis::cmd("PING")
                    .query_async::<String>(&mut manager)
                    .await
                    .context("pinging Redis")?;
                tracing::info!("connected to Redis");
                return Ok(manager);
            }
            Err(err) => {
                tracing::warn!(attempt, of = 6, error = %err, "Redis not reachable yet, retrying");
                last_err = Some(err);
                if attempt < 6 {
                    tokio::time::sleep(std::time::Duration::from_secs(5)).await;
                }
            }
        }
    }
    Err(anyhow::Error::new(last_err.expect("at least one attempt"))
        .context("connecting to Redis (check REDIS_URL and region)"))
}
