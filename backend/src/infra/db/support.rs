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
    /// True when a staff member or the bot sent it (renders on the other side).
    pub from_support: bool,
    /// True when the chatbot sent it (renders with the bot identity).
    pub from_bot: bool,
    pub body: String,
    pub created_at: DateTime<Utc>,
}

fn select() -> String {
    format!(
        "SELECT m.id, m.user_id, m.sender_id, u.full_name AS sender_name,
                (m.sender_id <> m.user_id) AS from_support,
                (u.phone = '{}') AS from_bot, m.body, m.created_at
           FROM support_messages m JOIN users u ON u.id = m.sender_id",
        crate::infra::bot::BOT_PHONE
    )
}

pub async fn thread(pg: &PgPool, user_id: Uuid) -> Result<Vec<SupportMessage>, AppError> {
    Ok(sqlx::query_as::<_, SupportMessage>(&format!(
        "{} WHERE m.user_id = $1 ORDER BY m.created_at ASC LIMIT 500",
        select()
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
    sqlx::query_as::<_, SupportMessage>(&format!("{} WHERE m.id = $1", select()))
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
    /// Same value on every row of a page — drives prev/next.
    #[serde(skip_serializing)]
    pub total: i64,
}

/// Inbox, one page (most recently active first). Server-side pagination
/// keeps the payload to `per_page` conversations.
pub async fn threads(
    pg: &PgPool,
    page: i64,
    per_page: i64,
) -> Result<Vec<SupportThread>, AppError> {
    Ok(sqlx::query_as::<_, SupportThread>(
        "SELECT t.*, count(*) OVER() AS total FROM (
            SELECT DISTINCT ON (m.user_id)
                   m.user_id, u.phone, u.full_name,
                   m.body AS last_body, m.created_at AS last_at,
                   (m.sender_id = m.user_id) AS awaiting_reply
            FROM support_messages m
            JOIN users u ON u.id = m.user_id
            ORDER BY m.user_id, m.created_at DESC
         ) t ORDER BY t.last_at DESC
         LIMIT $1 OFFSET $2",
    )
    .bind(per_page)
    .bind((page - 1).max(0) * per_page)
    .fetch_all(pg)
    .await?)
}
