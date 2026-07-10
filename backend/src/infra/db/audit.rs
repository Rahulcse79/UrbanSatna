use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::PgPool;
use uuid::Uuid;

use crate::domain::error::AppError;

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct AuditRow {
    pub id: Uuid,
    pub actor_phone: Option<String>,
    pub actor_type: String,
    pub action: String,
    pub entity_type: String,
    pub entity_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
    /// Same value on every row of a page — the window count drives prev/next.
    #[serde(skip_serializing)]
    pub total: i64,
}

/// One page of audit entries (newest first), filterable by text. Server-side
/// pagination keeps the payload to `per_page` rows however large the trail.
pub async fn list(
    pg: &PgPool,
    page: i64,
    per_page: i64,
    q: &str,
) -> Result<Vec<AuditRow>, AppError> {
    Ok(sqlx::query_as::<_, AuditRow>(
        "SELECT a.id, u.phone AS actor_phone, a.actor_type, a.action,
                a.entity_type, a.entity_id, a.created_at,
                count(*) OVER() AS total
         FROM audit_logs a
         LEFT JOIN users u ON u.id = a.actor_id
         WHERE ($3 = '' OR a.action ILIKE '%' || $3 || '%'
                        OR a.entity_type ILIKE '%' || $3 || '%'
                        OR u.phone ILIKE '%' || $3 || '%')
         ORDER BY a.created_at DESC
         LIMIT $1 OFFSET $2",
    )
    .bind(per_page)
    .bind((page - 1).max(0) * per_page)
    .bind(q)
    .fetch_all(pg)
    .await?)
}

/// Append-only audit trail. Every state-changing endpoint records one.
pub async fn log(
    pg: &PgPool,
    actor_id: Option<Uuid>,
    actor_type: &str,
    action: &str,
    entity_type: &str,
    entity_id: Option<Uuid>,
    after: Option<serde_json::Value>,
) -> Result<(), AppError> {
    sqlx::query(
        "INSERT INTO audit_logs (id, actor_id, actor_type, action, entity_type, entity_id, after)
         VALUES ($1, $2, $3, $4, $5, $6, $7)",
    )
    .bind(Uuid::now_v7())
    .bind(actor_id)
    .bind(actor_type)
    .bind(action)
    .bind(entity_type)
    .bind(entity_id)
    .bind(after)
    .execute(pg)
    .await?;
    Ok(())
}
