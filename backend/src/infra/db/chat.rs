use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::PgPool;
use uuid::Uuid;

use crate::domain::error::AppError;

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct ChatMessage {
    pub id: Uuid,
    pub booking_id: Uuid,
    pub sender_id: Uuid,
    pub sender_name: Option<String>,
    pub body: Option<String>,
    pub has_attachment: bool,
    pub attachment_mime: Option<String>,
    pub created_at: DateTime<Utc>,
}

const SELECT: &str = "SELECT m.id, m.booking_id, m.sender_id, u.full_name AS sender_name,
       m.body, (m.attachment IS NOT NULL) AS has_attachment, m.attachment_mime,
       m.created_at
  FROM booking_messages m JOIN users u ON u.id = m.sender_id";

/// Chat is private to the two sides of the booking.
pub async fn is_participant(
    pg: &PgPool,
    booking_id: Uuid,
    user_id: Uuid,
) -> Result<bool, AppError> {
    Ok(sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM bookings
          WHERE id = $1 AND (customer_id = $2 OR worker_id = $2))",
    )
    .bind(booking_id)
    .bind(user_id)
    .fetch_one(pg)
    .await?)
}

pub async fn list(pg: &PgPool, booking_id: Uuid) -> Result<Vec<ChatMessage>, AppError> {
    Ok(sqlx::query_as::<_, ChatMessage>(&format!(
        "{SELECT} WHERE m.booking_id = $1 ORDER BY m.created_at ASC LIMIT 500"
    ))
    .bind(booking_id)
    .fetch_all(pg)
    .await?)
}

pub async fn send(
    pg: &PgPool,
    booking_id: Uuid,
    sender_id: Uuid,
    body: Option<&str>,
    attachment: Option<(&[u8], &str)>,
) -> Result<ChatMessage, AppError> {
    let id = Uuid::now_v7();
    let (bytes, mime) = match attachment {
        Some((b, m)) => (Some(b), Some(m)),
        None => (None, None),
    };
    sqlx::query(
        "INSERT INTO booking_messages (id, booking_id, sender_id, body, attachment, attachment_mime)
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(id)
    .bind(booking_id)
    .bind(sender_id)
    .bind(body)
    .bind(bytes)
    .bind(mime)
    .execute(pg)
    .await?;
    sqlx::query_as::<_, ChatMessage>(&format!("{SELECT} WHERE m.id = $1"))
        .bind(id)
        .fetch_one(pg)
        .await
        .map_err(Into::into)
}

pub async fn attachment(
    pg: &PgPool,
    booking_id: Uuid,
    message_id: Uuid,
) -> Result<Option<(Vec<u8>, String)>, AppError> {
    let row: Option<(Option<Vec<u8>>, Option<String>)> = sqlx::query_as(
        "SELECT attachment, attachment_mime FROM booking_messages
         WHERE id = $1 AND booking_id = $2",
    )
    .bind(message_id)
    .bind(booking_id)
    .fetch_optional(pg)
    .await?;
    Ok(match row {
        Some((Some(bytes), Some(mime))) => Some((bytes, mime)),
        _ => None,
    })
}
