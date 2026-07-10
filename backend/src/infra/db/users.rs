use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::PgPool;
use uuid::Uuid;

use crate::domain::error::AppError;

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct User {
    pub id: Uuid,
    pub phone: String,
    pub email: Option<String>,
    pub full_name: Option<String>,
    pub address: Option<String>,
    pub state: Option<String>,
    pub city: Option<String>,
    pub pincode: Option<String>,
    pub terms_accepted: bool,
    pub is_blocked: bool,
    pub block_reason: Option<String>,
}

const COLS: &str = "id, phone, email, full_name, address, state, city, pincode,
    (terms_accepted_at IS NOT NULL) AS terms_accepted,
    (blocked_at IS NOT NULL) AS is_blocked, block_reason";

/// Returns the user for this phone, creating one on first login.
/// The bool is `true` when the user was just created.
pub async fn find_or_create_by_phone(pg: &PgPool, phone: &str) -> Result<(User, bool), AppError> {
    if let Some(user) = sqlx::query_as::<_, User>(&format!(
        "SELECT {COLS} FROM users WHERE phone = $1 AND deleted_at IS NULL"
    ))
    .bind(phone)
    .fetch_optional(pg)
    .await?
    {
        return Ok((user, false));
    }
    let user = sqlx::query_as::<_, User>(&format!(
        "INSERT INTO users (id, phone) VALUES ($1, $2) RETURNING {COLS}"
    ))
    .bind(Uuid::now_v7())
    .bind(phone)
    .fetch_one(pg)
    .await?;
    Ok((user, true))
}

pub async fn get(pg: &PgPool, id: Uuid) -> Result<User, AppError> {
    sqlx::query_as::<_, User>(&format!(
        "SELECT {COLS} FROM users WHERE id = $1 AND deleted_at IS NULL"
    ))
    .bind(id)
    .fetch_optional(pg)
    .await?
    .ok_or(AppError::NotFound("user"))
}

/// Partial profile update; `accept_terms` stamps first acceptance only.
#[allow(clippy::too_many_arguments)]
pub async fn update_profile(
    pg: &PgPool,
    id: Uuid,
    full_name: Option<&str>,
    email: Option<&str>,
    address: Option<&str>,
    state: Option<&str>,
    city: Option<&str>,
    pincode: Option<&str>,
    accept_terms: bool,
) -> Result<User, AppError> {
    sqlx::query_as::<_, User>(&format!(
        "UPDATE users SET
           full_name = COALESCE($2, full_name),
           email = COALESCE($3, email),
           address = COALESCE($4, address),
           state = COALESCE($5, state),
           city = COALESCE($6, city),
           pincode = COALESCE($7, pincode),
           terms_accepted_at = CASE WHEN $8 THEN COALESCE(terms_accepted_at, now())
                                    ELSE terms_accepted_at END
         WHERE id = $1 AND deleted_at IS NULL
         RETURNING {COLS}"
    ))
    .bind(id)
    .bind(full_name)
    .bind(email)
    .bind(address)
    .bind(state)
    .bind(city)
    .bind(pincode)
    .bind(accept_terms)
    .fetch_optional(pg)
    .await?
    .ok_or(AppError::NotFound("user"))
}

/// Idempotently grants a role by name.
pub async fn grant_role(pg: &PgPool, user_id: Uuid, role: &str) -> Result<(), AppError> {
    sqlx::query(
        "INSERT INTO user_roles (user_id, role_id)
         SELECT $1, id FROM roles WHERE name = $2
         ON CONFLICT DO NOTHING",
    )
    .bind(user_id)
    .bind(role)
    .execute(pg)
    .await?;
    Ok(())
}

/// Idempotently removes a role by name.
pub async fn revoke_role(pg: &PgPool, user_id: Uuid, role: &str) -> Result<(), AppError> {
    sqlx::query(
        "DELETE FROM user_roles ur USING roles r
         WHERE ur.user_id = $1 AND ur.role_id = r.id AND r.name = $2",
    )
    .bind(user_id)
    .bind(role)
    .execute(pg)
    .await?;
    Ok(())
}

/// All role names + permission codes for the user (for JWT claims).
pub async fn roles_and_perms(
    pg: &PgPool,
    user_id: Uuid,
) -> Result<(Vec<String>, Vec<String>), AppError> {
    let rows: Vec<(String, Option<String>)> = sqlx::query_as(
        "SELECT r.name, p.code
         FROM user_roles ur
         JOIN roles r ON r.id = ur.role_id
         LEFT JOIN role_permissions rp ON rp.role_id = r.id
         LEFT JOIN permissions p ON p.id = rp.permission_id
         WHERE ur.user_id = $1",
    )
    .bind(user_id)
    .fetch_all(pg)
    .await?;

    let mut roles: Vec<String> = rows.iter().map(|(r, _)| r.clone()).collect();
    roles.sort();
    roles.dedup();
    let mut perms: Vec<String> = rows.into_iter().filter_map(|(_, p)| p).collect();
    perms.sort();
    perms.dedup();
    Ok((roles, perms))
}

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct AdminUser {
    pub id: Uuid,
    pub phone: String,
    pub full_name: Option<String>,
    pub email: Option<String>,
    pub city: Option<String>,
    pub address: Option<String>,
    pub state: Option<String>,
    pub pincode: Option<String>,
    pub is_blocked: bool,
    pub block_reason: Option<String>,
    pub has_avatar: bool,
    pub roles: Vec<String>,
    /// Latest worker application, if the user ever applied — KYC documents
    /// hang off it, so the admin detail view links there.
    pub application_id: Option<Uuid>,
    pub application_status: Option<String>,
    pub has_kyc_doc: bool,
    pub has_kyc_selfie: bool,
    pub created_at: DateTime<Utc>,
    #[serde(skip_serializing)]
    pub total: i64,
}

/// Paginated user directory for the admin panel (10/page by default).
pub async fn list_admin(
    pg: &PgPool,
    page: i64,
    per_page: i64,
    q: &str,
) -> Result<Vec<AdminUser>, AppError> {
    Ok(sqlx::query_as::<_, AdminUser>(
        "SELECT u.id, u.phone, u.full_name, u.email, u.city, u.address,
                u.state, u.pincode,
                (u.blocked_at IS NOT NULL) AS is_blocked, u.block_reason,
                (u.avatar IS NOT NULL) AS has_avatar,
                COALESCE(array_agg(DISTINCT r.name)
                    FILTER (WHERE r.name IS NOT NULL), '{}') AS roles,
                wa.id AS application_id, wa.status AS application_status,
                COALESCE(wa.has_doc, false) AS has_kyc_doc,
                COALESCE(wa.has_selfie, false) AS has_kyc_selfie,
                u.created_at, count(*) OVER() AS total
         FROM users u
         LEFT JOIN user_roles ur ON ur.user_id = u.id
         LEFT JOIN roles r ON r.id = ur.role_id
         LEFT JOIN LATERAL (
             SELECT id, status,
                    (kyc_doc IS NOT NULL) AS has_doc,
                    (kyc_selfie IS NOT NULL) AS has_selfie
             FROM worker_applications
             WHERE user_id = u.id
             ORDER BY created_at DESC
             LIMIT 1
         ) wa ON true
         WHERE u.deleted_at IS NULL
           AND ($3 = '' OR u.phone ILIKE '%' || $3 || '%'
                        OR u.full_name ILIKE '%' || $3 || '%')
         GROUP BY u.id, wa.id, wa.status, wa.has_doc, wa.has_selfie
         ORDER BY u.created_at DESC
         LIMIT $1 OFFSET $2",
    )
    .bind(per_page)
    .bind((page - 1).max(0) * per_page)
    .bind(q)
    .fetch_all(pg)
    .await?)
}

/// A user's profile photo for the admin directory; None when unset.
pub async fn avatar(pg: &PgPool, id: Uuid) -> Result<Option<(Vec<u8>, String)>, AppError> {
    let row: Option<(Option<Vec<u8>>, Option<String>)> = sqlx::query_as(
        "SELECT avatar, avatar_mime FROM users WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(id)
    .fetch_optional(pg)
    .await?;
    Ok(match row {
        Some((Some(bytes), Some(mime))) => Some((bytes, mime)),
        _ => None,
    })
}

/// Blocking also kills every session so access tokens die at refresh.
pub async fn set_blocked(
    pg: &PgPool,
    id: Uuid,
    blocked: bool,
    reason: Option<&str>,
) -> Result<(), AppError> {
    let updated = sqlx::query(
        "UPDATE users SET
           blocked_at = CASE WHEN $2 THEN now() ELSE NULL END,
           block_reason = CASE WHEN $2 THEN $3 ELSE NULL END
         WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(id)
    .bind(blocked)
    .bind(reason)
    .execute(pg)
    .await?;
    if updated.rows_affected() == 0 {
        return Err(AppError::NotFound("user"));
    }
    if blocked {
        sqlx::query("UPDATE sessions SET revoked_at = now() WHERE user_id = $1")
            .bind(id)
            .execute(pg)
            .await?;
    }
    Ok(())
}
