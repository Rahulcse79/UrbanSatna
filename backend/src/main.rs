mod api;
mod config;
mod domain;
mod infra;
mod middleware;
mod state;

use anyhow::Context;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    dotenvy::dotenv().ok();
    let config = config::Config::from_env()?;
    init_tracing(&config);

    let pg = infra::db::connect(&config).await?;
    if config.run_migrations {
        sqlx::migrate!("./migrations")
            .run(&pg)
            .await
            .context("running database migrations")?;
        tracing::info!("database migrations applied");
    }
    let redis = infra::redis::connect(&config).await?;

    let addr = format!("{}:{}", config.host, config.port);
    let state = state::AppState::new(config, pg, redis);
    let app = api::router(state);

    let listener = tokio::net::TcpListener::bind(&addr)
        .await
        .with_context(|| format!("binding {addr}"))?;
    tracing::info!(%addr, "urbansatna-api listening");

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .context("server error")?;

    tracing::info!("shutdown complete");
    Ok(())
}

fn init_tracing(config: &config::Config) {
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("urbansatna_api=info,tower_http=info"));
    match config.log_format {
        config::LogFormat::Json => tracing_subscriber::fmt()
            .json()
            .with_env_filter(filter)
            .with_current_span(true)
            .init(),
        config::LogFormat::Pretty => tracing_subscriber::fmt().with_env_filter(filter).init(),
    }
}

async fn shutdown_signal() {
    let ctrl_c = async {
        tokio::signal::ctrl_c()
            .await
            .expect("failed to install ctrl-c handler");
    };
    let terminate = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("failed to install SIGTERM handler")
            .recv()
            .await;
    };
    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
    tracing::info!("shutdown signal received, draining connections");
}
