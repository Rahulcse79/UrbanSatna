use axum::extract::{Path, Query, State};
use axum::Json;
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use super::app_config;
use super::envelope::ApiResponse;
use crate::domain::error::AppError;
use crate::infra::db::{audit, bookings, settings};
use crate::middleware::auth::CurrentUser;
use crate::state::AppState;

#[derive(Deserialize)]
pub struct NewBooking {
    pub service_id: Uuid,
    pub address: String,
    pub note: Option<String>,
    /// Optional GPS pin the customer chose to share.
    pub lat: Option<f64>,
    pub lng: Option<f64>,
    pub coupon_code: Option<String>,
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
    // Admin booking controls: holiday pause + per-customer active cap.
    let paused = settings::get_json(&state.pg, app_config::BOOKINGS_PAUSED)
        .await?
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    if paused {
        let message = settings::get_json(&state.pg, app_config::BOOKINGS_PAUSED_MESSAGE)
            .await?
            .and_then(|v| v.as_str().map(str::to_string))
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| "bookings are temporarily paused, try again later".into());
        return Err(AppError::Conflict(message));
    }
    let max_active = settings::get_json(&state.pg, app_config::MAX_ACTIVE_BOOKINGS)
        .await?
        .and_then(|v| v.as_i64())
        .unwrap_or(5);
    let active: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM bookings
         WHERE customer_id = $1 AND status NOT IN ('completed','cancelled')",
    )
    .bind(current.id)
    .fetch_one(&state.pg)
    .await?;
    if active >= max_active {
        return Err(AppError::Conflict(format!(
            "you already have {active} active bookings — complete or cancel one first"
        )));
    }
    if body.lat.is_some_and(|v| !(-90.0..=90.0).contains(&v))
        || body.lng.is_some_and(|v| !(-180.0..=180.0).contains(&v))
    {
        return Err(AppError::Validation("invalid coordinates".into()));
    }
    let booking = bookings::create(
        &state.pg,
        current.id,
        body.service_id,
        body.address.trim(),
        body.note.as_deref(),
        body.lat,
        body.lng,
        body.coupon_code.as_deref(),
    )
    .await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "customer",
        "booking.created",
        "booking",
        Some(booking.id),
        Some(json!({
            "service_id": booking.service_id,
            "price_paise": booking.price_paise,
            "discount_paise": booking.discount_paise,
            "coupon_code": booking.coupon_code,
        })),
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
    let jobs = bookings::redact_all_for_worker(bookings::available(&state.pg, current.id).await?)
        .into_iter()
        .map(bookings::Booking::redact_contact)
        .collect::<Vec<_>>();
    Ok(Json(ApiResponse::ok(jobs)))
}

pub async fn my_jobs(
    State(state): State<AppState>,
    current: CurrentUser,
) -> Result<Json<ApiResponse<Vec<bookings::Booking>>>, AppError> {
    current.require_role("worker")?;
    Ok(Json(ApiResponse::ok(bookings::redact_all_for_worker(
        bookings::my_jobs(&state.pg, current.id).await?,
    ))))
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

/// Worker payment history: completed jobs, newest first.
pub async fn history(
    State(state): State<AppState>,
    current: CurrentUser,
) -> Result<Json<ApiResponse<Vec<bookings::Booking>>>, AppError> {
    current.require_role("worker")?;
    Ok(Json(ApiResponse::ok(bookings::redact_all_for_worker(
        bookings::worker_history(&state.pg, current.id).await?,
    ))))
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
    Ok(Json(ApiResponse::ok(booking.redact_for_worker())))
}

#[derive(Deserialize)]
pub struct StatusAction {
    pub action: String, // en_route | arrived | start | complete
    /// Customer's arrival OTP; required for `start`.
    pub otp: Option<String>,
}

pub async fn advance(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(id): Path<Uuid>,
    Json(body): Json<StatusAction>,
) -> Result<Json<ApiResponse<bookings::Booking>>, AppError> {
    current.require_role("worker")?;
    let booking =
        bookings::advance(&state.pg, id, current.id, &body.action, body.otp.as_deref()).await?;
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
    Ok(Json(ApiResponse::ok(booking.redact_for_worker())))
}

#[derive(Deserialize, Default)]
pub struct CancelBody {
    pub reason: Option<String>,
}

pub async fn cancel(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(id): Path<Uuid>,
    body: Option<Json<CancelBody>>,
) -> Result<Json<ApiResponse<bookings::Booking>>, AppError> {
    let reason = body.and_then(|Json(b)| b.reason).filter(|r| !r.is_empty());
    let booking = bookings::cancel(&state.pg, id, current.id, reason.as_deref()).await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "customer",
        "booking.cancelled",
        "booking",
        Some(id),
        reason.as_ref().map(|r| json!({ "reason": r })),
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
