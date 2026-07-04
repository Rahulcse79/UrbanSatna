use sqlx::PgPool;

use crate::domain::error::AppError;

/// Admin-managed runtime settings (key → jsonb). Missing keys fall back
/// to code defaults, so a fresh database behaves sensibly.
pub async fn get_json(pg: &PgPool, key: &str) -> Result<Option<serde_json::Value>, AppError> {
    let row: Option<(serde_json::Value,)> =
        sqlx::query_as("SELECT value FROM app_settings WHERE key = $1")
            .bind(key)
            .fetch_optional(pg)
            .await?;
    Ok(row.map(|(v,)| v))
}

pub async fn set_json(pg: &PgPool, key: &str, value: serde_json::Value) -> Result<(), AppError> {
    sqlx::query(
        "INSERT INTO app_settings (key, value) VALUES ($1, $2)
         ON CONFLICT (key) DO UPDATE SET value = $2, updated_at = now()",
    )
    .bind(key)
    .bind(value)
    .execute(pg)
    .await?;
    Ok(())
}
