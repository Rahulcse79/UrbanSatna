use chrono::{Duration, Utc};
use rand::RngCore;
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use uuid::Uuid;

use crate::domain::error::AppError;

fn new_refresh_token() -> String {
    let mut bytes = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut bytes);
    format!("rt_{}", hex::encode(bytes))
}

fn hash_token(token: &str) -> String {
    hex::encode(Sha256::digest(token.as_bytes()))
}

/// Creates a device session; returns (session_id, plain refresh token).
/// Only the hash is stored.
pub async fn create(
    pg: &PgPool,
    user_id: Uuid,
    device_id: Option<&str>,
    device_name: Option<&str>,
    ttl_days: i64,
) -> Result<(Uuid, String), AppError> {
    let token = new_refresh_token();
    let id = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO sessions (id, user_id, refresh_token_hash, device_id, device_name, expires_at)
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(id)
    .bind(user_id)
    .bind(hash_token(&token))
    .bind(device_id)
    .bind(device_name)
    .bind(Utc::now() + Duration::days(ttl_days))
    .execute(pg)
    .await?;
    Ok((id, token))
}

/// Rotates a refresh token: the old token is atomically replaced, so a
/// stolen-and-replayed old token fails. Returns (session_id, user_id,
/// new plain token).
pub async fn rotate(
    pg: &PgPool,
    refresh_token: &str,
    ttl_days: i64,
) -> Result<(Uuid, Uuid, String), AppError> {
    let new_token = new_refresh_token();
    let row: Option<(Uuid, Uuid)> = sqlx::query_as(
        "UPDATE sessions
         SET refresh_token_hash = $2, last_used_at = now(), expires_at = $3
         WHERE refresh_token_hash = $1 AND revoked_at IS NULL AND expires_at > now()
         RETURNING id, user_id",
    )
    .bind(hash_token(refresh_token))
    .bind(hash_token(&new_token))
    .bind(Utc::now() + Duration::days(ttl_days))
    .fetch_optional(pg)
    .await?;
    let (sid, user_id) = row.ok_or(AppError::Unauthorized)?;
    Ok((sid, user_id, new_token))
}

pub async fn revoke(pg: &PgPool, session_id: Uuid, user_id: Uuid) -> Result<(), AppError> {
    sqlx::query(
        "UPDATE sessions SET revoked_at = now()
         WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL",
    )
    .bind(session_id)
    .bind(user_id)
    .execute(pg)
    .await?;
    Ok(())
}

pub async fn revoke_all(pg: &PgPool, user_id: Uuid) -> Result<(), AppError> {
    sqlx::query("UPDATE sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL")
        .bind(user_id)
        .execute(pg)
        .await?;
    Ok(())
}
