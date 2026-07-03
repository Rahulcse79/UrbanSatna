use axum::extract::State;
use axum::Json;
use serde::{Deserialize, Serialize};
use serde_json::json;

use super::envelope::ApiResponse;
use crate::domain::error::AppError;
use crate::infra::db::{audit, users};
use crate::middleware::auth::CurrentUser;
use crate::state::AppState;

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

#[derive(Deserialize)]
pub struct UpdateMe {
    pub full_name: Option<String>,
    pub email: Option<String>,
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
    let user = users::update_profile(
        &state.pg,
        current.id,
        body.full_name.as_deref(),
        body.email.as_deref(),
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

/// Self-service worker signup for the test phase. Real KYC/verification
/// replaces this in the admin flow (PLAN.md Phase 2).
pub async fn become_worker(
    State(state): State<AppState>,
    current: CurrentUser,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    users::grant_role(&state.pg, current.id, "worker").await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "customer",
        "user.became_worker",
        "user",
        Some(current.id),
        None,
    )
    .await?;
    // Roles live in the JWT; a refresh picks up the new role.
    Ok(Json(ApiResponse::ok(json!({
        "worker": true,
        "note": "refresh your token to activate the worker role"
    }))))
}
