use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::PgPool;
use uuid::Uuid;

use crate::domain::error::AppError;

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct SupportMessage {
    pub id: Uuid,
    pub user_id: Uuid,
    pub sender_id: Uuid,
    pub sender_name: Option<String>,
    /// True when a staff member sent it (renders on the other side).
    pub from_support: bool,
    pub body: String,
    pub created_at: DateTime<Utc>,
}

const SELECT: &str = "SELECT m.id, m.user_id, m.sender_id, u.full_name AS sender_name,
       (m.sender_id <> m.user_id) AS from_support, m.body, m.created_at
  FROM support_messages m JOIN users u ON u.id = m.sender_id";

pub async fn thread(pg: &PgPool, user_id: Uuid) -> Result<Vec<SupportMessage>, AppError> {
    Ok(sqlx::query_as::<_, SupportMessage>(&format!(
        "{SELECT} WHERE m.user_id = $1 ORDER BY m.created_at ASC LIMIT 500"
    ))
    .bind(user_id)
    .fetch_all(pg)
    .await?)
}

pub async fn send(
    pg: &PgPool,
    user_id: Uuid,
    sender_id: Uuid,
    body: &str,
) -> Result<SupportMessage, AppError> {
    let id = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO support_messages (id, user_id, sender_id, body)
         VALUES ($1, $2, $3, $4)",
    )
    .bind(id)
    .bind(user_id)
    .bind(sender_id)
    .bind(body)
    .execute(pg)
    .await?;
    sqlx::query_as::<_, SupportMessage>(&format!("{SELECT} WHERE m.id = $1"))
        .bind(id)
        .fetch_one(pg)
        .await
        .map_err(Into::into)
}

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct SupportThread {
    pub user_id: Uuid,
    pub phone: String,
    pub full_name: Option<String>,
    pub last_body: String,
    pub last_at: DateTime<Utc>,
    /// True when the last word was the customer's — needs a reply.
    pub awaiting_reply: bool,
}

/// Inbox: every conversation, most recently active first.
pub async fn threads(pg: &PgPool) -> Result<Vec<SupportThread>, AppError> {
    Ok(sqlx::query_as::<_, SupportThread>(
        "SELECT * FROM (
            SELECT DISTINCT ON (m.user_id)
                   m.user_id, u.phone, u.full_name,
                   m.body AS last_body, m.created_at AS last_at,
                   (m.sender_id = m.user_id) AS awaiting_reply
            FROM support_messages m
            JOIN users u ON u.id = m.user_id
            ORDER BY m.user_id, m.created_at DESC
         ) t ORDER BY t.last_at DESC LIMIT 50",
    )
    .fetch_all(pg)
    .await?)
}
