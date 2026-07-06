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
const PROMO_BANNER: &str = "promo_banner";
const MAINTENANCE_MODE: &str = "maintenance_mode";
const MIN_BUILD: &str = "min_build";
const LATEST_BUILD: &str = "latest_build";
const REQUIRE_LATEST: &str = "require_latest";

/// Runtime app configuration — the control plane the admin edits live
/// (PRODUCT.md §6.5). Every field has a safe default so a missing row
/// or an old server never breaks the app.
#[derive(Debug, Serialize)]
pub struct AppConfig {
    pub allow_server_url_change: bool,
    pub promo_enabled: bool,
    pub promo_title: Option<String>,
    pub promo_subtitle: Option<String>,
    pub maintenance_mode: bool,
    /// Hard floor: builds below this are always blocked.
    pub min_build: i64,
    /// The newest released build (admin-maintained).
    pub latest_build: i64,
    /// Version gate: when on, only `latest_build` (or newer) may run.
    pub require_latest: bool,
}

async fn load(state: &AppState) -> Result<AppConfig, AppError> {
    let allow = settings::get_json(&state.pg, ALLOW_SERVER_URL_CHANGE)
        .await?
        .and_then(|v| v.as_bool())
        .unwrap_or(true); // default: users may change the server URL
    let promo = settings::get_json(&state.pg, PROMO_BANNER).await?;
    let maintenance = settings::get_json(&state.pg, MAINTENANCE_MODE)
        .await?
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let min_build = settings::get_json(&state.pg, MIN_BUILD)
        .await?
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    let latest_build = settings::get_json(&state.pg, LATEST_BUILD)
        .await?
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    let require_latest = settings::get_json(&state.pg, REQUIRE_LATEST)
        .await?
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    Ok(AppConfig {
        allow_server_url_change: allow,
        promo_enabled: promo
            .as_ref()
            .and_then(|p| p.get("enabled"))
            .and_then(|v| v.as_bool())
            .unwrap_or(true),
        promo_title: promo
            .as_ref()
            .and_then(|p| p.get("title"))
            .and_then(|v| v.as_str())
            .map(str::to_string),
        promo_subtitle: promo
            .as_ref()
            .and_then(|p| p.get("subtitle"))
            .and_then(|v| v.as_str())
            .map(str::to_string),
        maintenance_mode: maintenance,
        min_build,
        latest_build,
        require_latest,
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
    pub promo_enabled: Option<bool>,
    pub promo_title: Option<String>,
    pub promo_subtitle: Option<String>,
    pub maintenance_mode: Option<bool>,
    pub min_build: Option<i64>,
    pub latest_build: Option<i64>,
    pub require_latest: Option<bool>,
}

/// Admin: toggle app behavior at runtime (perm settings:manage).
pub async fn update(
    State(state): State<AppState>,
    current: CurrentUser,
    Json(body): Json<UpdateAppConfig>,
) -> Result<Json<ApiResponse<AppConfig>>, AppError> {
    current.require_perm("settings:manage")?;
    let mut changed = serde_json::Map::new();

    if let Some(allow) = body.allow_server_url_change {
        settings::set_json(&state.pg, ALLOW_SERVER_URL_CHANGE, json!(allow)).await?;
        changed.insert(ALLOW_SERVER_URL_CHANGE.into(), json!(allow));
    }
    if body.promo_enabled.is_some() || body.promo_title.is_some() || body.promo_subtitle.is_some() {
        // Merge over the current banner so a partial edit keeps the rest.
        let current_banner = load(&state).await?;
        let banner = json!({
            "enabled": body.promo_enabled.unwrap_or(current_banner.promo_enabled),
            "title": body.promo_title.or(current_banner.promo_title),
            "subtitle": body.promo_subtitle.or(current_banner.promo_subtitle),
        });
        settings::set_json(&state.pg, PROMO_BANNER, banner.clone()).await?;
        changed.insert(PROMO_BANNER.into(), banner);
    }
    if let Some(maintenance) = body.maintenance_mode {
        settings::set_json(&state.pg, MAINTENANCE_MODE, json!(maintenance)).await?;
        changed.insert(MAINTENANCE_MODE.into(), json!(maintenance));
    }
    if let Some(min_build) = body.min_build {
        if min_build < 0 {
            return Err(AppError::Validation("min_build must be >= 0".into()));
        }
        settings::set_json(&state.pg, MIN_BUILD, json!(min_build)).await?;
        changed.insert(MIN_BUILD.into(), json!(min_build));
    }
    if let Some(latest_build) = body.latest_build {
        if latest_build < 0 {
            return Err(AppError::Validation("latest_build must be >= 0".into()));
        }
        settings::set_json(&state.pg, LATEST_BUILD, json!(latest_build)).await?;
        changed.insert(LATEST_BUILD.into(), json!(latest_build));
    }
    if let Some(require_latest) = body.require_latest {
        settings::set_json(&state.pg, REQUIRE_LATEST, json!(require_latest)).await?;
        changed.insert(REQUIRE_LATEST.into(), json!(require_latest));
    }

    if !changed.is_empty() {
        audit::log(
            &state.pg,
            Some(current.id),
            "admin",
            "settings.updated",
            "app_setting",
            None,
            Some(serde_json::Value::Object(changed)),
        )
        .await?;
    }
    Ok(Json(ApiResponse::ok(load(&state).await?)))
}
