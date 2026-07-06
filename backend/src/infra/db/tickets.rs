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

pub async fn mine(pg: &PgPool, user_id: Uuid) -> Result<Vec<Ticket>, AppError> {
    Ok(sqlx::query_as::<_, Ticket>(&format!(
        "{SELECT} WHERE t.user_id = $1 ORDER BY t.created_at DESC"
    ))
    .bind(user_id)
    .fetch_all(pg)
    .await?)
}

/// Admin queue: open tickets oldest-first so nobody waits forever.
pub async fn list(pg: &PgPool, status: &str) -> Result<Vec<Ticket>, AppError> {
    Ok(sqlx::query_as::<_, Ticket>(&format!(
        "{SELECT} WHERE t.status = $1
         ORDER BY CASE WHEN t.status = 'open' THEN t.created_at END ASC,
                  t.created_at DESC"
    ))
    .bind(status)
    .fetch_all(pg)
    .await?)
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
