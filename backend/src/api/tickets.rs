use axum::extract::{Path, Query, State};
use axum::Json;
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use super::envelope::ApiResponse;
use crate::domain::error::AppError;
use crate::infra::db::{audit, tickets};
use crate::middleware::auth::CurrentUser;
use crate::state::AppState;

#[derive(Deserialize)]
pub struct NewTicket {
    pub subject: String,
    pub message: String,
    pub booking_id: Option<Uuid>,
}

pub async fn create(
    State(state): State<AppState>,
    current: CurrentUser,
    Json(body): Json<NewTicket>,
) -> Result<Json<ApiResponse<tickets::Ticket>>, AppError> {
    let subject = body.subject.trim();
    let message = body.message.trim();
    if subject.is_empty() || message.is_empty() {
        return Err(AppError::Validation(
            "subject and message are required".into(),
        ));
    }
    let ticket = tickets::create(&state.pg, current.id, body.booking_id, subject, message).await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "customer",
        "ticket.created",
        "ticket",
        Some(ticket.id),
        None,
    )
    .await?;
    Ok(Json(ApiResponse::ok(ticket)))
}

pub async fn mine(
    State(state): State<AppState>,
    current: CurrentUser,
) -> Result<Json<ApiResponse<Vec<tickets::Ticket>>>, AppError> {
    Ok(Json(ApiResponse::ok(
        tickets::mine(&state.pg, current.id).await?,
    )))
}

#[derive(Deserialize)]
pub struct QueueQuery {
    #[serde(default)]
    pub status: Option<String>,
    #[serde(default)]
    pub page: Option<i64>,
}

/// Admin queue, paginated 10/page. Gated on bookings:manage:any until a
/// dedicated support role/permission lands (PRODUCT.md §6.6).
pub async fn list(
    State(state): State<AppState>,
    current: CurrentUser,
    Query(q): Query<QueueQuery>,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    current.require_perm("bookings:manage:any")?;
    let status = q.status.as_deref().unwrap_or("open");
    if !matches!(status, "open" | "resolved" | "closed") {
        return Err(AppError::Validation("invalid status filter".into()));
    }
    let page = q.page.unwrap_or(1).max(1);
    let (items, total) = tickets::list(&state.pg, status, page).await?;
    Ok(Json(ApiResponse::ok(json!({
        "items": items,
        "total": total,
        "page": page,
        "per_page": 10,
    }))))
}

/// Customer reopens their resolved ticket (blocked once admin closes it).
pub async fn reopen(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<tickets::Ticket>>, AppError> {
    let ticket = tickets::reopen(&state.pg, id, current.id).await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "customer",
        "ticket.reopened",
        "ticket",
        Some(id),
        None,
    )
    .await?;
    Ok(Json(ApiResponse::ok(ticket)))
}

/// Admin permanently closes a ticket; no reopen after this.
pub async fn close(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<tickets::Ticket>>, AppError> {
    current.require_perm("bookings:manage:any")?;
    let ticket = tickets::close(&state.pg, id, current.id).await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "admin",
        "ticket.closed",
        "ticket",
        Some(id),
        None,
    )
    .await?;
    Ok(Json(ApiResponse::ok(ticket)))
}

#[derive(Deserialize)]
pub struct Resolution {
    pub resolution: String,
}

pub async fn resolve(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(id): Path<Uuid>,
    Json(body): Json<Resolution>,
) -> Result<Json<ApiResponse<tickets::Ticket>>, AppError> {
    current.require_perm("bookings:manage:any")?;
    let resolution = body.resolution.trim();
    if resolution.is_empty() {
        return Err(AppError::Validation("resolution note is required".into()));
    }
    let ticket = tickets::resolve(&state.pg, id, current.id, resolution).await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "admin",
        "ticket.resolved",
        "ticket",
        Some(id),
        Some(json!({ "resolution": resolution })),
    )
    .await?;
    Ok(Json(ApiResponse::ok(ticket)))
}
