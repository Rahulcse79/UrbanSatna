use std::time::Duration;

use axum::extract::State;
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use serde::Serialize;

use super::envelope::ApiResponse;
use crate::state::AppState;

const CHECK_TIMEOUT: Duration = Duration::from_secs(2);

#[derive(Debug, Serialize)]
pub struct HealthReport {
    pub status: &'static str,
    pub checks: Checks,
    pub version: &'static str,
}

#[derive(Debug, Serialize)]
pub struct Checks {
    pub database: &'static str,
    pub redis: &'static str,
}

/// Liveness + readiness: verifies PostgreSQL and Redis are reachable.
/// Returns 200 when everything is up, 503 otherwise (with per-check detail).
pub async fn health(State(state): State<AppState>) -> impl IntoResponse {
    let db_ok = tokio::time::timeout(CHECK_TIMEOUT, sqlx::query("SELECT 1").execute(&state.pg))
        .await
        .map(|r| r.is_ok())
        .unwrap_or(false);

    let mut redis_conn = state.redis.clone();
    let redis_ok = tokio::time::timeout(
        CHECK_TIMEOUT,
        redis::cmd("PING").query_async::<String>(&mut redis_conn),
    )
    .await
    .map(|r| r.is_ok())
    .unwrap_or(false);

    let healthy = db_ok && redis_ok;
    let report = HealthReport {
        status: if healthy { "ok" } else { "degraded" },
        checks: Checks {
            database: if db_ok { "up" } else { "down" },
            redis: if redis_ok { "up" } else { "down" },
        },
        version: env!("CARGO_PKG_VERSION"),
    };

    let status = if healthy {
        StatusCode::OK
    } else {
        StatusCode::SERVICE_UNAVAILABLE
    };
    (status, Json(ApiResponse::ok(report)))
}
