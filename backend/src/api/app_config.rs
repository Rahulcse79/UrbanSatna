use axum::extract::State;
use axum::Json;
use serde::{Deserialize, Serialize};
use serde_json::json;

use super::envelope::ApiResponse;
use crate::domain::error::AppError;
use crate::infra::db::{audit, settings};
use crate::middleware::auth::CurrentUser;
use crate::state::AppState;

const ALLOW_SERVER_URL_CHANGE: &str = "allow_server_url_change";

#[derive(Debug, Serialize)]
pub struct AppConfig {
    pub allow_server_url_change: bool,
}

async fn load(state: &AppState) -> Result<AppConfig, AppError> {
    let allow = settings::get_json(&state.pg, ALLOW_SERVER_URL_CHANGE)
        .await?
        .and_then(|v| v.as_bool())
        .unwrap_or(true); // default: users may change the server URL
    Ok(AppConfig {
        allow_server_url_change: allow,
    })
}

/// Public: the app reads this at startup to know which features are
/// enabled. Must stay unauthenticated — it is fetched before login.
pub async fn get(State(state): State<AppState>) -> Result<Json<ApiResponse<AppConfig>>, AppError> {
    Ok(Json(ApiResponse::ok(load(&state).await?)))
}

#[derive(Deserialize)]
pub struct UpdateAppConfig {
    pub allow_server_url_change: Option<bool>,
}

/// Admin: toggle app behavior at runtime (perm settings:manage).
pub async fn update(
    State(state): State<AppState>,
    current: CurrentUser,
    Json(body): Json<UpdateAppConfig>,
) -> Result<Json<ApiResponse<AppConfig>>, AppError> {
    current.require_perm("settings:manage")?;
    if let Some(allow) = body.allow_server_url_change {
        settings::set_json(&state.pg, ALLOW_SERVER_URL_CHANGE, json!(allow)).await?;
        audit::log(
            &state.pg,
            Some(current.id),
            "admin",
            "settings.updated",
            "app_setting",
            None,
            Some(json!({ "key": ALLOW_SERVER_URL_CHANGE, "value": allow })),
        )
        .await?;
    }
    Ok(Json(ApiResponse::ok(load(&state).await?)))
}
