use axum::body::Bytes;
use axum::extract::State;
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::{Deserialize, Serialize};

use super::envelope::ApiResponse;
use crate::domain::error::AppError;
use crate::infra::db::{audit, users, workers};
use crate::middleware::auth::CurrentUser;
use crate::state::AppState;

const MAX_AVATAR_BYTES: usize = 1_000_000; // product rule: ≤ 1 MB

#[derive(Serialize)]
pub struct Me {
    #[serde(flatten)]
    pub user: users::User,
    pub roles: Vec<String>,
}

pub async fn get_me(
    State(state): State<AppState>,
    current: CurrentUser,
) -> Result<Json<ApiResponse<Me>>, AppError> {
    let user = users::get(&state.pg, current.id).await?;
    let (roles, _) = users::roles_and_perms(&state.pg, current.id).await?;
    Ok(Json(ApiResponse::ok(Me { user, roles })))
}

#[derive(Deserialize, Default)]
pub struct UpdateMe {
    pub full_name: Option<String>,
    pub email: Option<String>,
    pub address: Option<String>,
    pub state: Option<String>,
    pub city: Option<String>,
    pub pincode: Option<String>,
    /// First-registration T&C acceptance (stamped once, never cleared).
    #[serde(default)]
    pub accept_terms: bool,
}

pub async fn update_me(
    State(state): State<AppState>,
    current: CurrentUser,
    Json(body): Json<UpdateMe>,
) -> Result<Json<ApiResponse<users::User>>, AppError> {
    if let Some(email) = body.email.as_deref() {
        if !email.contains('@') {
            return Err(AppError::Validation("invalid email".into()));
        }
    }
    if let Some(pin) = body.pincode.as_deref() {
        if !pin.is_empty() && (pin.len() != 6 || !pin.chars().all(|c| c.is_ascii_digit())) {
            return Err(AppError::Validation("PIN code must be 6 digits".into()));
        }
    }
    let user = users::update_profile(
        &state.pg,
        current.id,
        body.full_name.as_deref(),
        body.email.as_deref(),
        body.address.as_deref(),
        body.state.as_deref(),
        body.city.as_deref(),
        body.pincode.as_deref(),
        body.accept_terms,
    )
    .await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "customer",
        "user.profile_updated",
        "user",
        Some(current.id),
        None,
    )
    .await?;
    Ok(Json(ApiResponse::ok(user)))
}

#[derive(Deserialize, Default)]
pub struct WorkerApplicationBody {
    pub skills: Option<String>,
    pub experience: Option<String>,
}

/// Apply to become a worker. The worker role is granted only when an admin
/// approves the application (verified-only accept gate, PRODUCT.md §12.3).
/// Also mounted on the legacy /me/become-worker route, so old APKs get a
/// pending application instead of an instant role.
pub async fn apply_worker(
    State(state): State<AppState>,
    current: CurrentUser,
    body: Option<Json<WorkerApplicationBody>>,
) -> Result<Json<ApiResponse<workers::WorkerApplication>>, AppError> {
    let body = body.map(|Json(b)| b).unwrap_or_default();
    let application = workers::apply(
        &state.pg,
        current.id,
        body.skills.as_deref(),
        body.experience.as_deref(),
    )
    .await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "customer",
        "worker.applied",
        "worker_application",
        Some(application.id),
        None,
    )
    .await?;
    Ok(Json(ApiResponse::ok(application)))
}

pub async fn my_worker_application(
    State(state): State<AppState>,
    current: CurrentUser,
) -> Result<Json<ApiResponse<Option<workers::WorkerApplication>>>, AppError> {
    Ok(Json(ApiResponse::ok(
        workers::latest_for_user(&state.pg, current.id).await?,
    )))
}

/// PNG/JPEG only, ≤ 1 MB; the magic bytes are checked, not just the header.
pub fn validate_image(body: &Bytes, headers: &HeaderMap) -> Result<&'static str, AppError> {
    if body.len() > MAX_AVATAR_BYTES {
        return Err(AppError::Validation("image must be under 1 MB".into()));
    }
    let mime = if body.starts_with(&[0x89, b'P', b'N', b'G']) {
        "image/png"
    } else if body.starts_with(&[0xFF, 0xD8, 0xFF]) {
        "image/jpeg"
    } else {
        return Err(AppError::Validation(
            "only PNG or JPG images allowed".into(),
        ));
    };
    // The declared content-type must not contradict the actual bytes.
    if let Some(declared) = headers
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
    {
        if !declared.starts_with("image/") {
            return Err(AppError::Validation("content-type must be an image".into()));
        }
    }
    Ok(mime)
}

pub async fn upload_avatar(
    State(state): State<AppState>,
    current: CurrentUser,
    headers: HeaderMap,
    body: Bytes,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    let mime = validate_image(&body, &headers)?;
    sqlx::query("UPDATE users SET avatar = $2, avatar_mime = $3 WHERE id = $1")
        .bind(current.id)
        .bind(body.as_ref())
        .bind(mime)
        .execute(&state.pg)
        .await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "customer",
        "user.avatar_updated",
        "user",
        Some(current.id),
        None,
    )
    .await?;
    Ok(Json(ApiResponse::ok(
        serde_json::json!({ "updated": true }),
    )))
}

/// KYC photo ("doc" or "selfie") for the caller's pending application.
pub async fn upload_kyc(
    State(state): State<AppState>,
    current: CurrentUser,
    axum::extract::Path(kind): axum::extract::Path<String>,
    headers: HeaderMap,
    body: Bytes,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    if kind != "doc" && kind != "selfie" {
        return Err(AppError::Validation("kind must be doc or selfie".into()));
    }
    let mime = validate_image(&body, &headers)?;
    workers::set_kyc(&state.pg, current.id, &kind, &body, mime).await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "customer",
        "worker.kyc_uploaded",
        "worker_application",
        None,
        Some(serde_json::json!({ "kind": kind })),
    )
    .await?;
    Ok(Json(ApiResponse::ok(
        serde_json::json!({ "uploaded": true }),
    )))
}

pub async fn get_avatar(
    State(state): State<AppState>,
    current: CurrentUser,
) -> Result<Response, AppError> {
    let row: Option<(Option<Vec<u8>>, Option<String>)> =
        sqlx::query_as("SELECT avatar, avatar_mime FROM users WHERE id = $1")
            .bind(current.id)
            .fetch_optional(&state.pg)
            .await?;
    match row {
        Some((Some(bytes), Some(mime))) => {
            Ok(([(header::CONTENT_TYPE, mime)], bytes).into_response())
        }
        _ => Ok(StatusCode::NOT_FOUND.into_response()),
    }
}
