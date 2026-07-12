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
    /// May be empty when the message is attachment-only.
    pub body: String,
    /// When present, the client fetches bytes at .../messages/{id}/attachment.
    pub attachment_mime: Option<String>,
    pub created_at: DateTime<Utc>,
}

fn select() -> String {
    format!(
        "SELECT m.id, m.user_id, m.sender_id, u.full_name AS sender_name,
                (m.sender_id <> m.user_id) AS from_support,
                (u.phone = '{}') AS from_bot,
                COALESCE(m.body, '') AS body,
                m.attachment_mime, m.created_at
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

/// Insert a text and/or attachment message. At least one of `body` /
/// `attachment` must be present — enforced both here and by the CHECK
/// constraint on the table.
pub async fn send(
    pg: &PgPool,
    user_id: Uuid,
    sender_id: Uuid,
    body: Option<&str>,
    attachment: Option<(&[u8], &str)>,
) -> Result<SupportMessage, AppError> {
    if body.is_none() && attachment.is_none() {
        return Err(AppError::Validation(
            "message must have text or an attachment".into(),
        ));
    }
    let (att_bytes, att_mime) = match attachment {
        Some((bytes, mime)) => (Some(bytes), Some(mime)),
        None => (None, None),
    };
    let id = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO support_messages
             (id, user_id, sender_id, body, attachment, attachment_mime)
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(id)
    .bind(user_id)
    .bind(sender_id)
    .bind(body)
    .bind(att_bytes)
    .bind(att_mime)
    .execute(pg)
    .await?;
    sqlx::query_as::<_, SupportMessage>(&format!("{} WHERE m.id = $1", select()))
        .bind(id)
        .fetch_one(pg)
        .await
        .map_err(Into::into)
}

/// Bytes + mime for the given support message; None when there is no
/// attachment or the message doesn't belong to the requested thread.
pub async fn attachment(
    pg: &PgPool,
    user_id: Uuid,
    message_id: Uuid,
) -> Result<Option<(Vec<u8>, String)>, AppError> {
    let row: Option<(Option<Vec<u8>>, Option<String>)> = sqlx::query_as(
        "SELECT attachment, attachment_mime FROM support_messages
         WHERE id = $1 AND user_id = $2",
    )
    .bind(message_id)
    .bind(user_id)
    .fetch_optional(pg)
    .await?;
    Ok(row.and_then(|(bytes, mime)| match (bytes, mime) {
        (Some(b), Some(m)) => Some((b, m)),
        _ => None,
    }))
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
