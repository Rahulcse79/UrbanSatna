use axum::extract::{Path, Query, State};
use axum::Json;
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use super::envelope::ApiResponse;
use crate::domain::error::AppError;
use crate::infra::db::{audit, bookings};
use crate::middleware::auth::CurrentUser;
use crate::state::AppState;

#[derive(Deserialize)]
pub struct NewBooking {
    pub service_id: Uuid,
    pub address: String,
    pub note: Option<String>,
}

pub async fn create(
    State(state): State<AppState>,
    current: CurrentUser,
    Json(body): Json<NewBooking>,
) -> Result<Json<ApiResponse<bookings::Booking>>, AppError> {
    current.require_perm("bookings:create")?;
    if body.address.trim().len() < 5 {
        return Err(AppError::Validation("address is required".into()));
    }
    let booking = bookings::create(
        &state.pg,
        current.id,
        body.service_id,
        body.address.trim(),
        body.note.as_deref(),
    )
    .await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "customer",
        "booking.created",
        "booking",
        Some(booking.id),
        Some(json!({ "service_id": booking.service_id, "price_paise": booking.price_paise })),
    )
    .await?;
    Ok(Json(ApiResponse::ok(booking)))
}

#[derive(Deserialize)]
pub struct MineQuery {
    #[serde(default)]
    pub scope: Option<String>, // active (default) | past
}

pub async fn mine(
    State(state): State<AppState>,
    current: CurrentUser,
    Query(q): Query<MineQuery>,
) -> Result<Json<ApiResponse<Vec<bookings::Booking>>>, AppError> {
    let active = q.scope.as_deref() != Some("past");
    Ok(Json(ApiResponse::ok(
        bookings::mine(&state.pg, current.id, active).await?,
    )))
}

pub async fn available_jobs(
    State(state): State<AppState>,
    current: CurrentUser,
) -> Result<Json<ApiResponse<Vec<bookings::Booking>>>, AppError> {
    current.require_role("worker")?;
    Ok(Json(ApiResponse::ok(
        bookings::available(&state.pg, current.id).await?,
    )))
}

pub async fn my_jobs(
    State(state): State<AppState>,
    current: CurrentUser,
) -> Result<Json<ApiResponse<Vec<bookings::Booking>>>, AppError> {
    current.require_role("worker")?;
    Ok(Json(ApiResponse::ok(
        bookings::my_jobs(&state.pg, current.id).await?,
    )))
}

pub async fn earnings(
    State(state): State<AppState>,
    current: CurrentUser,
) -> Result<Json<ApiResponse<bookings::Earnings>>, AppError> {
    current.require_role("worker")?;
    Ok(Json(ApiResponse::ok(
        bookings::earnings(&state.pg, current.id).await?,
    )))
}

pub async fn accept(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<bookings::Booking>>, AppError> {
    current.require_role("worker")?;
    let booking = bookings::accept(&state.pg, id, current.id).await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "worker",
        "booking.accepted",
        "booking",
        Some(id),
        None,
    )
    .await?;
    Ok(Json(ApiResponse::ok(booking)))
}

#[derive(Deserialize)]
pub struct StatusAction {
    pub action: String, // en_route | start | complete
}

pub async fn advance(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(id): Path<Uuid>,
    Json(body): Json<StatusAction>,
) -> Result<Json<ApiResponse<bookings::Booking>>, AppError> {
    current.require_role("worker")?;
    let booking = bookings::advance(&state.pg, id, current.id, &body.action).await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "worker",
        "booking.state_changed",
        "booking",
        Some(id),
        Some(json!({ "action": body.action, "status": booking.status })),
    )
    .await?;
    Ok(Json(ApiResponse::ok(booking)))
}

pub async fn cancel(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<bookings::Booking>>, AppError> {
    let booking = bookings::cancel(&state.pg, id, current.id).await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "customer",
        "booking.cancelled",
        "booking",
        Some(id),
        None,
    )
    .await?;
    Ok(Json(ApiResponse::ok(booking)))
}

#[derive(Deserialize)]
pub struct RatingBody {
    pub rating: i32,
    pub review: Option<String>,
}

pub async fn rate(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(id): Path<Uuid>,
    Json(body): Json<RatingBody>,
) -> Result<Json<ApiResponse<bookings::Booking>>, AppError> {
    let booking = bookings::rate(
        &state.pg,
        id,
        current.id,
        body.rating,
        body.review.as_deref(),
    )
    .await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "customer",
        "booking.rated",
        "booking",
        Some(id),
        Some(json!({ "rating": body.rating })),
    )
    .await?;
    Ok(Json(ApiResponse::ok(booking)))
}
