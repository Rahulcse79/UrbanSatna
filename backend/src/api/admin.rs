use axum::extract::{Path, Query, State};
use axum::http::{header, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use serde::Serialize;

use super::envelope::ApiResponse;
use crate::domain::error::AppError;
use crate::infra::db::{audit, users, workers};
use crate::middleware::auth::CurrentUser;
use crate::state::AppState;

/// Dashboard numbers for the admin panel header.
#[derive(Serialize, sqlx::FromRow)]
pub struct Stats {
    pub bookings_today: i64,
    pub revenue_today_paise: i64,
    pub active_bookings: i64,
    pub open_tickets: i64,
    pub pending_applications: i64,
    pub total_users: i64,
}

pub async fn stats(
    State(state): State<AppState>,
    current: CurrentUser,
) -> Result<Json<ApiResponse<Stats>>, AppError> {
    current.require_perm("bookings:manage:any")?;
    let stats = sqlx::query_as::<_, Stats>(
        "SELECT
          (SELECT count(*) FROM bookings
            WHERE created_at >= date_trunc('day', now())) AS bookings_today,
          (SELECT COALESCE(sum(price_paise), 0) FROM bookings
            WHERE status = 'completed'
              AND completed_at >= date_trunc('day', now()))::bigint AS revenue_today_paise,
          (SELECT count(*) FROM bookings
            WHERE status NOT IN ('completed','cancelled')) AS active_bookings,
          (SELECT count(*) FROM tickets WHERE status = 'open') AS open_tickets,
          (SELECT count(*) FROM worker_applications
            WHERE status = 'pending') AS pending_applications,
          (SELECT count(*) FROM users WHERE deleted_at IS NULL) AS total_users",
    )
    .fetch_one(&state.pg)
    .await?;
    Ok(Json(ApiResponse::ok(stats)))
}

#[derive(Deserialize)]
pub struct UsersQuery {
    #[serde(default)]
    pub page: Option<i64>,
    #[serde(default)]
    pub q: Option<String>,
}

/// Paginated user directory: 10 per page, prev/next driven by `total`.
pub async fn list_users(
    State(state): State<AppState>,
    current: CurrentUser,
    Query(query): Query<UsersQuery>,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    current.require_perm("users:manage:any")?;
    let page = query.page.unwrap_or(1).max(1);
    let q = query.q.unwrap_or_default();
    let items = users::list_admin(&state.pg, page, 10, q.trim()).await?;
    let total = items.first().map(|u| u.total).unwrap_or(0);
    Ok(Json(ApiResponse::ok(json!({
        "items": items,
        "total": total,
        "page": page,
        "per_page": 10,
    }))))
}

#[derive(Deserialize, Default)]
pub struct BlockBody {
    pub reason: Option<String>,
}

pub async fn block_user(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(id): Path<Uuid>,
    body: Option<Json<BlockBody>>,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    current.require_perm("users:manage:any")?;
    if id == current.id {
        return Err(AppError::Validation("you cannot block yourself".into()));
    }
    let reason = body.and_then(|Json(b)| b.reason).filter(|r| !r.is_empty());
    users::set_blocked(&state.pg, id, true, reason.as_deref()).await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "admin",
        "user.blocked",
        "user",
        Some(id),
        reason.as_ref().map(|r| json!({ "reason": r })),
    )
    .await?;
    Ok(Json(ApiResponse::ok(json!({ "blocked": true }))))
}

pub async fn unblock_user(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    current.require_perm("users:manage:any")?;
    users::set_blocked(&state.pg, id, false, None).await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "admin",
        "user.unblocked",
        "user",
        Some(id),
        None,
    )
    .await?;
    Ok(Json(ApiResponse::ok(json!({ "blocked": false }))))
}

#[derive(Deserialize)]
pub struct LogsQuery {
    #[serde(default)]
    pub q: Option<String>,
}

/// Latest 100 audit entries, text-filterable (perm audit:read).
pub async fn audit_logs(
    State(state): State<AppState>,
    current: CurrentUser,
    Query(query): Query<LogsQuery>,
) -> Result<Json<ApiResponse<Vec<audit::AuditRow>>>, AppError> {
    current.require_perm("audit:read")?;
    Ok(Json(ApiResponse::ok(
        audit::list(&state.pg, query.q.unwrap_or_default().trim()).await?,
    )))
}

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
