use anyhow::{bail, Context};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LogFormat {
    Json,
    Pretty,
}

#[derive(Debug, Clone)]
pub struct Config {
    pub host: String,
    pub port: u16,
    pub database_url: String,
    pub redis_url: String,
    pub run_migrations: bool,
    pub log_format: LogFormat,
    pub db_max_connections: u32,
}

impl Config {
    pub fn from_env() -> anyhow::Result<Self> {
        let host = env_or("APP_HOST", "0.0.0.0");
        let port: u16 = env_or("APP_PORT", "8080")
            .parse()
            .context("APP_PORT must be a number")?;
        let database_url = required("DATABASE_URL")?;
        let redis_url = required("REDIS_URL")?;
        let run_migrations = env_or("RUN_MIGRATIONS", "true") == "true";
        let log_format = match env_or("LOG_FORMAT", "json").as_str() {
            "pretty" => LogFormat::Pretty,
            "json" => LogFormat::Json,
            other => bail!("LOG_FORMAT must be 'json' or 'pretty', got '{other}'"),
        };
        let db_max_connections: u32 = env_or("DB_MAX_CONNECTIONS", "10")
            .parse()
            .context("DB_MAX_CONNECTIONS must be a number")?;

        Ok(Self {
            host,
            port,
            database_url,
            redis_url,
            run_migrations,
            log_format,
            db_max_connections,
        })
    }
}

fn env_or(key: &str, default: &str) -> String {
    std::env::var(key).unwrap_or_else(|_| default.to_string())
}

fn required(key: &str) -> anyhow::Result<String> {
    std::env::var(key).with_context(|| format!("{key} must be set"))
}
