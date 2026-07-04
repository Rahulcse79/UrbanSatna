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
    pub jwt_secret: String,
    pub access_ttl_secs: i64,
    pub refresh_ttl_days: i64,
    /// Phones auto-granted the admin role on login (bootstrap; CSV env).
    pub admin_phones: Vec<String>,
    /// Dev flag: include the OTP in the response instead of sending SMS.
    /// MUST stay false anywhere real users exist.
    pub dev_return_otp: bool,
}

impl Config {
    pub fn from_env() -> anyhow::Result<Self> {
        let host = env_or("APP_HOST", "0.0.0.0");
        // PORT is the platform convention (Render/Heroku); APP_PORT is ours.
        let port: u16 = std::env::var("PORT")
            .unwrap_or_else(|_| env_or("APP_PORT", "8080"))
            .parse()
            .context("PORT/APP_PORT must be a number")?;
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
        let jwt_secret = required("JWT_SECRET")?;
        let access_ttl_secs: i64 = env_or("ACCESS_TTL_SECS", "900")
            .parse()
            .context("ACCESS_TTL_SECS must be a number")?;
        let refresh_ttl_days: i64 = env_or("REFRESH_TTL_DAYS", "30")
            .parse()
            .context("REFRESH_TTL_DAYS must be a number")?;
        let admin_phones: Vec<String> = env_or("ADMIN_PHONES", "")
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();
        let dev_return_otp = env_or("DEV_RETURN_OTP", "false") == "true";

        Ok(Self {
            host,
            port,
            database_url,
            redis_url,
            run_migrations,
            log_format,
            db_max_connections,
            jwt_secret,
            access_ttl_secs,
            refresh_ttl_days,
            admin_phones,
            dev_return_otp,
        })
    }
}

fn env_or(key: &str, default: &str) -> String {
    std::env::var(key).unwrap_or_else(|_| default.to_string())
}

fn required(key: &str) -> anyhow::Result<String> {
    std::env::var(key).with_context(|| format!("{key} must be set"))
}

#[cfg(test)]
mod tests {
    use super::*;

    // Single test: std::env is process-global, so parallel tests that
    // mutate it would race.
    #[test]
    fn from_env_applies_defaults_and_requires_urls() {
        std::env::remove_var("DATABASE_URL");
        std::env::remove_var("REDIS_URL");
        std::env::remove_var("LOG_FORMAT");
        std::env::remove_var("JWT_SECRET");
        std::env::remove_var("PORT");
        assert!(
            Config::from_env().is_err(),
            "DATABASE_URL/REDIS_URL/JWT_SECRET must be required"
        );

        std::env::set_var("DATABASE_URL", "postgres://localhost/test");
        std::env::set_var("REDIS_URL", "redis://localhost");
        std::env::set_var("JWT_SECRET", "test-secret");
        std::env::set_var("ADMIN_PHONES", "+911111111111, +922222222222");
        let config = Config::from_env().unwrap();
        assert_eq!(config.access_ttl_secs, 900);
        assert_eq!(config.admin_phones, vec!["+911111111111", "+922222222222"]);
        assert!(!config.dev_return_otp);
        assert_eq!(config.host, "0.0.0.0");
        assert_eq!(config.port, 8080);
        assert!(config.run_migrations);
        assert_eq!(config.log_format, LogFormat::Json);
        assert_eq!(config.db_max_connections, 10);

        std::env::set_var("LOG_FORMAT", "sideways");
        assert!(Config::from_env().is_err(), "bad LOG_FORMAT must fail");
        std::env::remove_var("LOG_FORMAT");
    }
}
