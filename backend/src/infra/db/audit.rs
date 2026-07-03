use sqlx::PgPool;
use uuid::Uuid;

use crate::domain::error::AppError;

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
