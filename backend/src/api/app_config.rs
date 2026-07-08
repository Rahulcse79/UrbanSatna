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
const CITY_LABEL: &str = "city_label";
const APP_DISPLAY_NAME: &str = "app_display_name";
const TAGLINE: &str = "tagline";
const THEME_PRESET: &str = "theme_preset";
const SUPPORT_PHONE: &str = "support_phone";
const ANNOUNCEMENT_ENABLED: &str = "announcement_enabled";
const ANNOUNCEMENT_TEXT: &str = "announcement_text";
pub const BOOKINGS_PAUSED: &str = "bookings_paused";
pub const BOOKINGS_PAUSED_MESSAGE: &str = "bookings_paused_message";
pub const MAX_ACTIVE_BOOKINGS: &str = "max_active_bookings";
const SUPPORT_EMAIL: &str = "support_email";
const APP_VERSION_LABEL: &str = "app_version_label";
const COUNTRY_CODES: &str = "country_codes";
const TERMS_URL: &str = "terms_url";
const PRIVACY_URL: &str = "privacy_url";
const SUPPORT_ONLINE: &str = "support_online";
const USER_POLICY_TEXT: &str = "user_policy_text";
const ACCEPTANCE_TEXT: &str = "acceptance_text";

/// The app falls back to its built-in look for unknown presets, so this
/// list only guards against typos, not app versions.
const THEME_PRESETS: &[&str] = &[
    "indigo", "emerald", "crimson", "royal", "ocean", "sunset", "teal", "gold", "rose",
];

async fn get_str(state: &AppState, key: &str) -> Result<Option<String>, AppError> {
    Ok(settings::get_json(&state.pg, key)
        .await?
        .and_then(|v| v.as_str().map(str::to_string))
        .filter(|s| !s.is_empty()))
}

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
    // Branding & text — the app falls back to built-in copy when unset.
    pub city_label: Option<String>,
    pub app_display_name: Option<String>,
    pub tagline: Option<String>,
    pub theme_preset: String,
    pub support_phone: Option<String>,
    pub announcement_enabled: bool,
    pub announcement_text: Option<String>,
    // Booking controls
    pub bookings_paused: bool,
    pub bookings_paused_message: Option<String>,
    pub max_active_bookings: i64,
    // Help, legal & registration
    pub support_email: Option<String>,
    /// Marketing version shown in the app (e.g. "v1.0.1"); admin-managed.
    pub app_version_label: Option<String>,
    /// Allowed phone country codes (registration dropdown), CSV-managed.
    pub country_codes: Vec<String>,
    pub terms_url: Option<String>,
    pub privacy_url: Option<String>,
    /// Live-support indicator: green (true) / red (false) in the app.
    pub support_online: bool,
    /// Admin-written User Policy body shown in the app (null = URL only).
    pub user_policy_text: Option<String>,
    /// Admin-written acceptance line ("I agree to …") on registration.
    pub acceptance_text: Option<String>,
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
    let announcement_enabled = settings::get_json(&state.pg, ANNOUNCEMENT_ENABLED)
        .await?
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let bookings_paused = settings::get_json(&state.pg, BOOKINGS_PAUSED)
        .await?
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let max_active_bookings = settings::get_json(&state.pg, MAX_ACTIVE_BOOKINGS)
        .await?
        .and_then(|v| v.as_i64())
        .unwrap_or(5);
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
        city_label: get_str(state, CITY_LABEL).await?,
        app_display_name: get_str(state, APP_DISPLAY_NAME).await?,
        tagline: get_str(state, TAGLINE).await?,
        theme_preset: get_str(state, THEME_PRESET)
            .await?
            .unwrap_or_else(|| "indigo".to_string()),
        support_phone: get_str(state, SUPPORT_PHONE).await?,
        announcement_enabled,
        announcement_text: get_str(state, ANNOUNCEMENT_TEXT).await?,
        bookings_paused,
        bookings_paused_message: get_str(state, BOOKINGS_PAUSED_MESSAGE).await?,
        max_active_bookings,
        support_email: get_str(state, SUPPORT_EMAIL).await?,
        app_version_label: get_str(state, APP_VERSION_LABEL).await?,
        country_codes: get_str(state, COUNTRY_CODES)
            .await?
            .unwrap_or_else(|| "+91".to_string())
            .split(',')
            .map(|c| c.trim().to_string())
            .filter(|c| !c.is_empty())
            .collect(),
        terms_url: get_str(state, TERMS_URL).await?,
        privacy_url: get_str(state, PRIVACY_URL).await?,
        support_online: settings::get_json(&state.pg, SUPPORT_ONLINE)
            .await?
            .and_then(|v| v.as_bool())
            .unwrap_or(false),
        user_policy_text: get_str(state, USER_POLICY_TEXT).await?,
        acceptance_text: get_str(state, ACCEPTANCE_TEXT).await?,
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
    pub city_label: Option<String>,
    pub app_display_name: Option<String>,
    pub tagline: Option<String>,
    pub theme_preset: Option<String>,
    pub support_phone: Option<String>,
    pub announcement_enabled: Option<bool>,
    pub announcement_text: Option<String>,
    pub bookings_paused: Option<bool>,
    pub bookings_paused_message: Option<String>,
    pub max_active_bookings: Option<i64>,
    pub support_email: Option<String>,
    pub app_version_label: Option<String>,
    /// CSV, e.g. "+91,+971" — controls the registration dropdown.
    pub country_codes: Option<String>,
    pub terms_url: Option<String>,
    pub privacy_url: Option<String>,
    pub support_online: Option<bool>,
    pub user_policy_text: Option<String>,
    pub acceptance_text: Option<String>,
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
    if let Some(preset) = body.theme_preset.as_deref() {
        if !THEME_PRESETS.contains(&preset) {
            return Err(AppError::Validation(format!(
                "theme_preset must be one of {THEME_PRESETS:?}"
            )));
        }
        settings::set_json(&state.pg, THEME_PRESET, json!(preset)).await?;
        changed.insert(THEME_PRESET.into(), json!(preset));
    }
    // Free-text branding fields: an empty string clears back to defaults.
    for (key, value) in [
        (CITY_LABEL, &body.city_label),
        (APP_DISPLAY_NAME, &body.app_display_name),
        (TAGLINE, &body.tagline),
        (SUPPORT_PHONE, &body.support_phone),
        (ANNOUNCEMENT_TEXT, &body.announcement_text),
        (BOOKINGS_PAUSED_MESSAGE, &body.bookings_paused_message),
        (SUPPORT_EMAIL, &body.support_email),
        (APP_VERSION_LABEL, &body.app_version_label),
        (COUNTRY_CODES, &body.country_codes),
        (TERMS_URL, &body.terms_url),
        (PRIVACY_URL, &body.privacy_url),
        (USER_POLICY_TEXT, &body.user_policy_text),
        (ACCEPTANCE_TEXT, &body.acceptance_text),
    ] {
        if let Some(text) = value {
            settings::set_json(&state.pg, key, json!(text.trim())).await?;
            changed.insert(key.into(), json!(text.trim()));
        }
    }
    if let Some(enabled) = body.announcement_enabled {
        settings::set_json(&state.pg, ANNOUNCEMENT_ENABLED, json!(enabled)).await?;
        changed.insert(ANNOUNCEMENT_ENABLED.into(), json!(enabled));
    }
    if let Some(paused) = body.bookings_paused {
        settings::set_json(&state.pg, BOOKINGS_PAUSED, json!(paused)).await?;
        changed.insert(BOOKINGS_PAUSED.into(), json!(paused));
    }
    if let Some(online) = body.support_online {
        settings::set_json(&state.pg, SUPPORT_ONLINE, json!(online)).await?;
        changed.insert(SUPPORT_ONLINE.into(), json!(online));
    }
    if let Some(max) = body.max_active_bookings {
        if !(1..=100).contains(&max) {
            return Err(AppError::Validation(
                "max_active_bookings must be 1-100".into(),
            ));
        }
        settings::set_json(&state.pg, MAX_ACTIVE_BOOKINGS, json!(max)).await?;
        changed.insert(MAX_ACTIVE_BOOKINGS.into(), json!(max));
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
