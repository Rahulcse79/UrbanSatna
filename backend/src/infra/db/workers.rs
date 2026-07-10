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
    pub has_kyc_doc: bool,
    pub has_kyc_selfie: bool,
    pub created_at: DateTime<Utc>,
    pub decided_at: Option<DateTime<Utc>>,
}

const SELECT: &str = "SELECT a.id, a.user_id, u.phone, u.full_name, a.status,
       a.skills, a.experience, a.note,
       (a.kyc_doc IS NOT NULL) AS has_kyc_doc,
       (a.kyc_selfie IS NOT NULL) AS has_kyc_selfie,
       a.created_at, a.decided_at
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

/// Admin review queue, one page (10): pending oldest-first so nobody
/// waits forever, decided queues newest-first.
pub async fn list(
    pg: &PgPool,
    status: &str,
    page: i64,
) -> Result<(Vec<WorkerApplication>, i64), AppError> {
    let total: i64 =
        sqlx::query_scalar("SELECT count(*) FROM worker_applications WHERE status = $1")
            .bind(status)
            .fetch_one(pg)
            .await?;
    let items = sqlx::query_as::<_, WorkerApplication>(&format!(
        "{SELECT} WHERE a.status = $1
         ORDER BY CASE WHEN a.status = 'pending' THEN a.created_at END ASC,
                  a.created_at DESC
         LIMIT 10 OFFSET $2"
    ))
    .bind(status)
    .bind((page - 1).max(0) * 10)
    .fetch_all(pg)
    .await?;
    Ok((items, total))
}

/// Attaches a KYC photo to the user's pending application.
/// `kind` is validated at the API boundary ("doc" | "selfie").
pub async fn set_kyc(
    pg: &PgPool,
    user_id: Uuid,
    kind: &str,
    bytes: &[u8],
    mime: &str,
) -> Result<(), AppError> {
    let sql = match kind {
        "doc" => {
            "UPDATE worker_applications SET kyc_doc = $2, kyc_doc_mime = $3
             WHERE user_id = $1 AND status = 'pending'"
        }
        "selfie" => {
            "UPDATE worker_applications SET kyc_selfie = $2, kyc_selfie_mime = $3
             WHERE user_id = $1 AND status = 'pending'"
        }
        _ => return Err(AppError::Validation("unknown document kind".into())),
    };
    let updated = sqlx::query(sql)
        .bind(user_id)
        .bind(bytes)
        .bind(mime)
        .execute(pg)
        .await?;
    if updated.rows_affected() == 0 {
        return Err(AppError::Conflict(
            "no pending application to attach documents to".into(),
        ));
    }
    Ok(())
}

/// KYC photo bytes for the admin review screen.
pub async fn kyc_image(
    pg: &PgPool,
    id: Uuid,
    kind: &str,
) -> Result<Option<(Vec<u8>, String)>, AppError> {
    let sql = match kind {
        "doc" => "SELECT kyc_doc, kyc_doc_mime FROM worker_applications WHERE id = $1",
        "selfie" => "SELECT kyc_selfie, kyc_selfie_mime FROM worker_applications WHERE id = $1",
        _ => return Err(AppError::Validation("unknown document kind".into())),
    };
    let row: Option<(Option<Vec<u8>>, Option<String>)> =
        sqlx::query_as(sql).bind(id).fetch_optional(pg).await?;
    Ok(match row {
        Some((Some(bytes), Some(mime))) => Some((bytes, mime)),
        _ => None,
    })
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
