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
}

/// Latest 100 entries for the admin logs screen, filterable by text.
pub async fn list(pg: &PgPool, q: &str) -> Result<Vec<AuditRow>, AppError> {
    Ok(sqlx::query_as::<_, AuditRow>(
        "SELECT a.id, u.phone AS actor_phone, a.actor_type, a.action,
                a.entity_type, a.entity_id, a.created_at
         FROM audit_logs a
         LEFT JOIN users u ON u.id = a.actor_id
         WHERE ($1 = '' OR a.action ILIKE '%' || $1 || '%'
                        OR a.entity_type ILIKE '%' || $1 || '%'
                        OR u.phone ILIKE '%' || $1 || '%')
         ORDER BY a.created_at DESC
         LIMIT 100",
    )
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
