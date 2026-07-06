use axum::extract::State;
use axum::Json;
use serde::{Deserialize, Serialize};

use super::envelope::ApiResponse;
use crate::domain::error::AppError;
use crate::infra::db::{audit, users, workers};
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
