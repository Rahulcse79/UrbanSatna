use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::PgPool;
use uuid::Uuid;

use crate::domain::error::AppError;

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct Ticket {
    pub id: Uuid,
    pub user_id: Uuid,
    pub phone: String,
    pub full_name: Option<String>,
    pub booking_id: Option<Uuid>,
    pub subject: String,
    pub message: String,
    pub status: String,
    pub resolution: Option<String>,
    pub created_at: DateTime<Utc>,
    pub resolved_at: Option<DateTime<Utc>>,
}

const SELECT: &str = "SELECT t.id, t.user_id, u.phone, u.full_name, t.booking_id,
       t.subject, t.message, t.status, t.resolution, t.created_at, t.resolved_at
  FROM tickets t JOIN users u ON u.id = t.user_id";

pub async fn create(
    pg: &PgPool,
    user_id: Uuid,
    booking_id: Option<Uuid>,
    subject: &str,
    message: &str,
) -> Result<Ticket, AppError> {
    let id = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO tickets (id, user_id, booking_id, subject, message)
         VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(id)
    .bind(user_id)
    .bind(booking_id)
    .bind(subject)
    .bind(message)
    .execute(pg)
    .await?;
    get(pg, id).await
}

pub async fn get(pg: &PgPool, id: Uuid) -> Result<Ticket, AppError> {
    sqlx::query_as::<_, Ticket>(&format!("{SELECT} WHERE t.id = $1"))
        .bind(id)
        .fetch_optional(pg)
        .await?
        .ok_or(AppError::NotFound("ticket"))
}

/// One page (10) of the customer's own tickets, newest first.
pub async fn mine(pg: &PgPool, user_id: Uuid, page: i64) -> Result<(Vec<Ticket>, i64), AppError> {
    let total: i64 = sqlx::query_scalar("SELECT count(*) FROM tickets WHERE user_id = $1")
        .bind(user_id)
        .fetch_one(pg)
        .await?;
    let items = sqlx::query_as::<_, Ticket>(&format!(
        "{SELECT} WHERE t.user_id = $1 ORDER BY t.created_at DESC
         LIMIT 10 OFFSET $2"
    ))
    .bind(user_id)
    .bind((page - 1).max(0) * 10)
    .fetch_all(pg)
    .await?;
    Ok((items, total))
}

/// Admin queue, 10 per page: open tickets oldest-first so nobody waits.
pub async fn list(pg: &PgPool, status: &str, page: i64) -> Result<(Vec<Ticket>, i64), AppError> {
    let total: i64 = sqlx::query_scalar("SELECT count(*) FROM tickets WHERE status = $1")
        .bind(status)
        .fetch_one(pg)
        .await?;
    let items = sqlx::query_as::<_, Ticket>(&format!(
        "{SELECT} WHERE t.status = $1
         ORDER BY CASE WHEN t.status = 'open' THEN t.created_at END ASC,
                  t.created_at DESC
         LIMIT 10 OFFSET $2"
    ))
    .bind(status)
    .bind((page - 1).max(0) * 10)
    .fetch_all(pg)
    .await?;
    Ok((items, total))
}

/// Customer reopens a resolved ticket (never a closed one — closed is
/// the admin's permanent state).
pub async fn reopen(pg: &PgPool, id: Uuid, user_id: Uuid) -> Result<Ticket, AppError> {
    let updated = sqlx::query(
        "UPDATE tickets SET status = 'open'
         WHERE id = $1 AND user_id = $2 AND status = 'resolved'",
    )
    .bind(id)
    .bind(user_id)
    .execute(pg)
    .await?;
    if updated.rows_affected() == 0 {
        return Err(AppError::Conflict(
            "ticket cannot be reopened (closed or not yours)".into(),
        ));
    }
    get(pg, id).await
}

/// Admin permanently closes; the user cannot reopen after this.
pub async fn close(pg: &PgPool, id: Uuid, admin_id: Uuid) -> Result<Ticket, AppError> {
    let updated = sqlx::query(
        "UPDATE tickets SET status = 'closed', resolved_by = $2, resolved_at = now()
         WHERE id = $1 AND status <> 'closed'",
    )
    .bind(id)
    .bind(admin_id)
    .execute(pg)
    .await?;
    if updated.rows_affected() == 0 {
        return Err(AppError::Conflict("ticket already closed".into()));
    }
    get(pg, id).await
}

pub async fn resolve(
    pg: &PgPool,
    id: Uuid,
    admin_id: Uuid,
    resolution: &str,
) -> Result<Ticket, AppError> {
    let updated = sqlx::query(
        "UPDATE tickets
            SET status = 'resolved', resolution = $2, resolved_by = $3, resolved_at = now()
          WHERE id = $1 AND status = 'open'",
    )
    .bind(id)
    .bind(resolution)
    .bind(admin_id)
    .execute(pg)
    .await?;
    if updated.rows_affected() == 0 {
        return Err(AppError::Conflict("ticket already resolved".into()));
    }
    get(pg, id).await
}
