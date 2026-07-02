use anyhow::Context;
use redis::aio::ConnectionManager;

use crate::config::Config;

pub async fn connect(config: &Config) -> anyhow::Result<ConnectionManager> {
    let client = redis::Client::open(config.redis_url.as_str()).context("parsing REDIS_URL")?;
    let mut manager = client
        .get_connection_manager()
        .await
        .context("connecting to Redis")?;
    // Fail fast at startup rather than on the first request.
    redis::cmd("PING")
        .query_async::<String>(&mut manager)
        .await
        .context("pinging Redis")?;
    tracing::info!("connected to Redis");
    Ok(manager)
}
