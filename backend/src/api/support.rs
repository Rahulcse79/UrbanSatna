use axum::extract::{Path, State};
use axum::Json;
use serde::Deserialize;
use uuid::Uuid;

use super::envelope::ApiResponse;
use crate::domain::error::AppError;
use crate::infra::db::support;
use crate::middleware::auth::CurrentUser;
use crate::state::AppState;

fn valid_body(body: &str) -> Result<&str, AppError> {
    let body = body.trim();
    if body.is_empty() || body.len() > 2000 {
        return Err(AppError::Validation("message must be 1-2000 chars".into()));
    }
    Ok(body)
}

/// The signed-in user's own support thread.
pub async fn my_thread(
    State(state): State<AppState>,
    current: CurrentUser,
) -> Result<Json<ApiResponse<Vec<support::SupportMessage>>>, AppError> {
    Ok(Json(ApiResponse::ok(
        support::thread(&state.pg, current.id).await?,
    )))
}

#[derive(Deserialize)]
pub struct NewMessage {
    pub body: String,
}

pub async fn send(
    State(state): State<AppState>,
    current: CurrentUser,
    Json(msg): Json<NewMessage>,
) -> Result<Json<ApiResponse<support::SupportMessage>>, AppError> {
    let body = valid_body(&msg.body)?;
    Ok(Json(ApiResponse::ok(
        support::send(&state.pg, current.id, current.id, body).await?,
    )))
}

/// Admin inbox: one row per conversation (perm bookings:manage:any).
pub async fn threads(
    State(state): State<AppState>,
    current: CurrentUser,
) -> Result<Json<ApiResponse<Vec<support::SupportThread>>>, AppError> {
    current.require_perm("bookings:manage:any")?;
    Ok(Json(ApiResponse::ok(support::threads(&state.pg).await?)))
}

pub async fn admin_thread(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(user_id): Path<Uuid>,
) -> Result<Json<ApiResponse<Vec<support::SupportMessage>>>, AppError> {
    current.require_perm("bookings:manage:any")?;
    Ok(Json(ApiResponse::ok(
        support::thread(&state.pg, user_id).await?,
    )))
}

pub async fn admin_send(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(user_id): Path<Uuid>,
    Json(msg): Json<NewMessage>,
) -> Result<Json<ApiResponse<support::SupportMessage>>, AppError> {
    current.require_perm("bookings:manage:any")?;
    let body = valid_body(&msg.body)?;
    Ok(Json(ApiResponse::ok(
        support::send(&state.pg, user_id, current.id, body).await?,
    )))
}
