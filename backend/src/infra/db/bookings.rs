use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::PgPool;
use uuid::Uuid;

use crate::domain::booking as bk;
use crate::domain::error::AppError;

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct Booking {
    pub id: Uuid,
    pub status: String,
    pub service_id: Uuid,
    pub service_name: String,
    pub category_name: String,
    pub customer_id: Uuid,
    pub customer_name: Option<String>,
    pub worker_id: Option<Uuid>,
    pub worker_name: Option<String>,
    pub address: String,
    pub note: Option<String>,
    pub price_paise: i64,
    pub rating: Option<i32>,
    pub review: Option<String>,
    pub created_at: DateTime<Utc>,
}

const SELECT: &str = "SELECT b.id, b.status, b.service_id, s.name AS service_name,
       c.name AS category_name, b.customer_id, cu.full_name AS customer_name,
       b.worker_id, w.full_name AS worker_name, b.address, b.note,
       b.price_paise, b.rating, b.review, b.created_at
  FROM bookings b
  JOIN services s ON s.id = b.service_id
  JOIN categories c ON c.id = s.category_id
  JOIN users cu ON cu.id = b.customer_id
  LEFT JOIN users w ON w.id = b.worker_id";

pub async fn get(pg: &PgPool, id: Uuid) -> Result<Booking, AppError> {
    sqlx::query_as::<_, Booking>(&format!("{SELECT} WHERE b.id = $1"))
        .bind(id)
        .fetch_optional(pg)
        .await?
        .ok_or(AppError::NotFound("booking"))
}

/// Creates a booking, snapshotting the service price.
pub async fn create(
    pg: &PgPool,
    customer_id: Uuid,
    service_id: Uuid,
    address: &str,
    note: Option<&str>,
) -> Result<Booking, AppError> {
    let id = Uuid::now_v7();
    let inserted = sqlx::query(
        "INSERT INTO bookings (id, customer_id, service_id, status, address, note, price_paise)
         SELECT $1, $2, s.id, 'pending', $4, $5, s.base_price_paise
         FROM services s
         WHERE s.id = $3 AND s.is_active AND s.deleted_at IS NULL",
    )
    .bind(id)
    .bind(customer_id)
    .bind(service_id)
    .bind(address)
    .bind(note)
    .execute(pg)
    .await?;
    if inserted.rows_affected() == 0 {
        return Err(AppError::NotFound("service"));
    }
    get(pg, id).await
}

/// Customer's bookings. `active` = not yet completed/cancelled.
pub async fn mine(pg: &PgPool, customer_id: Uuid, active: bool) -> Result<Vec<Booking>, AppError> {
    let filter = if active {
        "b.status NOT IN ('completed','cancelled')"
    } else {
        "b.status IN ('completed','cancelled')"
    };
    Ok(sqlx::query_as::<_, Booking>(&format!(
        "{SELECT} WHERE b.customer_id = $1 AND {filter} ORDER BY b.created_at DESC"
    ))
    .bind(customer_id)
    .fetch_all(pg)
    .await?)
}

/// Unassigned pending jobs any worker can pick up (not their own bookings).
pub async fn available(pg: &PgPool, worker_id: Uuid) -> Result<Vec<Booking>, AppError> {
    Ok(sqlx::query_as::<_, Booking>(&format!(
        "{SELECT} WHERE b.status = 'pending' AND b.worker_id IS NULL
          AND b.customer_id <> $1
          ORDER BY b.created_at DESC"
    ))
    .bind(worker_id)
    .fetch_all(pg)
    .await?)
}

/// Jobs assigned to this worker that are still in progress.
pub async fn my_jobs(pg: &PgPool, worker_id: Uuid) -> Result<Vec<Booking>, AppError> {
    Ok(sqlx::query_as::<_, Booking>(&format!(
        "{SELECT} WHERE b.worker_id = $1 AND b.status NOT IN ('completed','cancelled')
         ORDER BY b.created_at DESC"
    ))
    .bind(worker_id)
    .fetch_all(pg)
    .await?)
}

/// First-accept-wins: the conditional UPDATE is atomic, so a second
/// worker's accept affects zero rows and turns into a CONFLICT.
pub async fn accept(pg: &PgPool, id: Uuid, worker_id: Uuid) -> Result<Booking, AppError> {
    let updated = sqlx::query(
        "UPDATE bookings SET status = 'accepted', worker_id = $2, accepted_at = now()
         WHERE id = $1 AND status = 'pending' AND worker_id IS NULL AND customer_id <> $2",
    )
    .bind(id)
    .bind(worker_id)
    .execute(pg)
    .await?;
    if updated.rows_affected() == 0 {
        return Err(AppError::Conflict(
            "job already taken or no longer available".into(),
        ));
    }
    get(pg, id).await
}

/// Assigned worker advances the state machine (en_route/start/complete).
pub async fn advance(
    pg: &PgPool,
    id: Uuid,
    worker_id: Uuid,
    action: &str,
) -> Result<Booking, AppError> {
    let booking = get(pg, id).await?;
    if booking.worker_id != Some(worker_id) {
        return Err(AppError::Forbidden);
    }
    let next = bk::next_status_for_action(action, &booking.status)?;
    let completed_at = if next == bk::COMPLETED {
        Some(Utc::now())
    } else {
        None
    };
    // Guard on current status again so concurrent transitions can't skip states.
    let updated = sqlx::query(
        "UPDATE bookings SET status = $3, completed_at = COALESCE($4, completed_at)
         WHERE id = $1 AND worker_id = $2 AND status = $5",
    )
    .bind(id)
    .bind(worker_id)
    .bind(next)
    .bind(completed_at)
    .bind(&booking.status)
    .execute(pg)
    .await?;
    if updated.rows_affected() == 0 {
        return Err(AppError::Conflict("booking changed, retry".into()));
    }
    get(pg, id).await
}

pub async fn cancel(pg: &PgPool, id: Uuid, customer_id: Uuid) -> Result<Booking, AppError> {
    let booking = get(pg, id).await?;
    if booking.customer_id != customer_id {
        return Err(AppError::Forbidden);
    }
    if !bk::can_cancel(&booking.status) {
        return Err(AppError::Conflict(format!(
            "cannot cancel a booking in status {}",
            booking.status
        )));
    }
    let updated = sqlx::query(
        "UPDATE bookings SET status = 'cancelled', cancelled_at = now()
         WHERE id = $1 AND customer_id = $2 AND status = $3",
    )
    .bind(id)
    .bind(customer_id)
    .bind(&booking.status)
    .execute(pg)
    .await?;
    if updated.rows_affected() == 0 {
        return Err(AppError::Conflict("booking changed, retry".into()));
    }
    get(pg, id).await
}

pub async fn rate(
    pg: &PgPool,
    id: Uuid,
    customer_id: Uuid,
    rating: i32,
    review: Option<&str>,
) -> Result<Booking, AppError> {
    if !(1..=5).contains(&rating) {
        return Err(AppError::Validation("rating must be 1-5".into()));
    }
    let updated = sqlx::query(
        "UPDATE bookings SET rating = $3, review = $4
         WHERE id = $1 AND customer_id = $2 AND status = 'completed' AND rating IS NULL",
    )
    .bind(id)
    .bind(customer_id)
    .bind(rating)
    .bind(review)
    .execute(pg)
    .await?;
    if updated.rows_affected() == 0 {
        return Err(AppError::Conflict(
            "booking is not completed or already rated".into(),
        ));
    }
    get(pg, id).await
}

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct Earnings {
    pub completed_jobs: i64,
    pub total_paise: i64,
    pub avg_rating: Option<f64>,
}

pub async fn earnings(pg: &PgPool, worker_id: Uuid) -> Result<Earnings, AppError> {
    Ok(sqlx::query_as::<_, Earnings>(
        "SELECT count(*) AS completed_jobs,
                COALESCE(sum(price_paise), 0)::bigint AS total_paise,
                avg(rating)::float8 AS avg_rating
         FROM bookings WHERE worker_id = $1 AND status = 'completed'",
    )
    .bind(worker_id)
    .fetch_one(pg)
    .await?)
}
