use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::PgPool;
use uuid::Uuid;

use crate::domain::error::AppError;

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct WorkerApplication {
    pub id: Uuid,
    pub user_id: Uuid,
    pub phone: String,
    pub full_name: Option<String>,
    pub status: String,
    pub skills: Option<String>,
    pub experience: Option<String>,
    pub note: Option<String>,
    pub created_at: DateTime<Utc>,
    pub decided_at: Option<DateTime<Utc>>,
}

const SELECT: &str = "SELECT a.id, a.user_id, u.phone, u.full_name, a.status,
       a.skills, a.experience, a.note, a.created_at, a.decided_at
  FROM worker_applications a
  JOIN users u ON u.id = a.user_id";

pub async fn apply(
    pg: &PgPool,
    user_id: Uuid,
    skills: Option<&str>,
    experience: Option<&str>,
) -> Result<WorkerApplication, AppError> {
    let roles: Vec<String> = sqlx::query_scalar(
        "SELECT r.name FROM user_roles ur JOIN roles r ON r.id = ur.role_id
          WHERE ur.user_id = $1",
    )
    .bind(user_id)
    .fetch_all(pg)
    .await?;
    if roles.iter().any(|r| r == "worker") {
        return Err(AppError::Conflict(
            "you are already a verified worker".into(),
        ));
    }
    // Separation of duties: staff accounts operate the platform, they
    // don't participate in the marketplace (PRODUCT.md role matrix).
    if roles.iter().any(|r| r == "admin" || r == "super_admin") {
        return Err(AppError::Conflict(
            "admin accounts cannot become workers".into(),
        ));
    }
    let id = Uuid::now_v7();
    let inserted = sqlx::query(
        "INSERT INTO worker_applications (id, user_id, skills, experience)
         VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING",
    )
    .bind(id)
    .bind(user_id)
    .bind(skills)
    .bind(experience)
    .execute(pg)
    .await?;
    if inserted.rows_affected() == 0 {
        return Err(AppError::Conflict(
            "an application is already pending review".into(),
        ));
    }
    get(pg, id).await
}

pub async fn get(pg: &PgPool, id: Uuid) -> Result<WorkerApplication, AppError> {
    sqlx::query_as::<_, WorkerApplication>(&format!("{SELECT} WHERE a.id = $1"))
        .bind(id)
        .fetch_optional(pg)
        .await?
        .ok_or(AppError::NotFound("worker application"))
}

/// The user's most recent application, if any.
pub async fn latest_for_user(
    pg: &PgPool,
    user_id: Uuid,
) -> Result<Option<WorkerApplication>, AppError> {
    Ok(sqlx::query_as::<_, WorkerApplication>(&format!(
        "{SELECT} WHERE a.user_id = $1 ORDER BY a.created_at DESC LIMIT 1"
    ))
    .bind(user_id)
    .fetch_optional(pg)
    .await?)
}

/// Admin review queue, oldest first so nobody waits forever.
pub async fn list(pg: &PgPool, status: &str) -> Result<Vec<WorkerApplication>, AppError> {
    Ok(sqlx::query_as::<_, WorkerApplication>(&format!(
        "{SELECT} WHERE a.status = $1 ORDER BY a.created_at ASC"
    ))
    .bind(status)
    .fetch_all(pg)
    .await?)
}

/// Approve/reject in one transaction: approval also grants the worker role,
/// so the role can never exist without a decided application behind it.
pub async fn decide(
    pg: &PgPool,
    id: Uuid,
    admin_id: Uuid,
    approve: bool,
    note: Option<&str>,
) -> Result<WorkerApplication, AppError> {
    let mut tx = pg.begin().await?;
    let status = if approve { "approved" } else { "rejected" };
    let updated = sqlx::query(
        "UPDATE worker_applications
            SET status = $2, note = $3, decided_by = $4, decided_at = now()
          WHERE id = $1 AND status = 'pending'",
    )
    .bind(id)
    .bind(status)
    .bind(note)
    .bind(admin_id)
    .execute(&mut *tx)
    .await?;
    if updated.rows_affected() == 0 {
        return Err(AppError::Conflict("application already decided".into()));
    }
    if approve {
        sqlx::query(
            "INSERT INTO user_roles (user_id, role_id)
             SELECT a.user_id, r.id FROM worker_applications a, roles r
             WHERE a.id = $1 AND r.name = 'worker'
             ON CONFLICT DO NOTHING",
        )
        .bind(id)
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    get(pg, id).await
}
