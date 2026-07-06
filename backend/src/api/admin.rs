use axum::extract::{Path, Query, State};
use axum::http::{header, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use super::envelope::ApiResponse;
use crate::domain::error::AppError;
use crate::infra::db::{audit, workers};
use crate::middleware::auth::CurrentUser;
use crate::state::AppState;

/// KYC photo for the review screen (workers:verify only).
pub async fn kyc_image(
    State(state): State<AppState>,
    current: CurrentUser,
    Path((id, kind)): Path<(Uuid, String)>,
) -> Result<Response, AppError> {
    current.require_perm("workers:verify")?;
    match workers::kyc_image(&state.pg, id, &kind).await? {
        Some((bytes, mime)) => Ok(([(header::CONTENT_TYPE, mime)], bytes).into_response()),
        None => Ok(StatusCode::NOT_FOUND.into_response()),
    }
}

#[derive(Deserialize)]
pub struct QueueQuery {
    #[serde(default)]
    pub status: Option<String>, // pending (default) | approved | rejected
}

pub async fn list_worker_applications(
    State(state): State<AppState>,
    current: CurrentUser,
    Query(q): Query<QueueQuery>,
) -> Result<Json<ApiResponse<Vec<workers::WorkerApplication>>>, AppError> {
    current.require_perm("workers:verify")?;
    let status = q.status.as_deref().unwrap_or("pending");
    if !matches!(status, "pending" | "approved" | "rejected") {
        return Err(AppError::Validation("invalid status filter".into()));
    }
    Ok(Json(ApiResponse::ok(
        workers::list(&state.pg, status).await?,
    )))
}

#[derive(Deserialize)]
pub struct DecisionBody {
    pub approve: bool,
    pub note: Option<String>,
}

pub async fn decide_worker_application(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(id): Path<Uuid>,
    Json(body): Json<DecisionBody>,
) -> Result<Json<ApiResponse<workers::WorkerApplication>>, AppError> {
    current.require_perm("workers:verify")?;
    let application = workers::decide(
        &state.pg,
        id,
        current.id,
        body.approve,
        body.note.as_deref(),
    )
    .await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "admin",
        if body.approve {
            "worker.application_approved"
        } else {
            "worker.application_rejected"
        },
        "worker_application",
        Some(id),
        Some(json!({ "user_id": application.user_id })),
    )
    .await?;
    Ok(Json(ApiResponse::ok(application)))
}
