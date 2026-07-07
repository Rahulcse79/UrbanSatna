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
    pub city: Option<String>,
    pub is_blocked: bool,
    pub block_reason: Option<String>,
    pub roles: Vec<String>,
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
        "SELECT u.id, u.phone, u.full_name, u.city,
                (u.blocked_at IS NOT NULL) AS is_blocked, u.block_reason,
                COALESCE(array_agg(DISTINCT r.name)
                    FILTER (WHERE r.name IS NOT NULL), '{}') AS roles,
                u.created_at, count(*) OVER() AS total
         FROM users u
         LEFT JOIN user_roles ur ON ur.user_id = u.id
         LEFT JOIN roles r ON r.id = ur.role_id
         WHERE u.deleted_at IS NULL
           AND ($3 = '' OR u.phone ILIKE '%' || $3 || '%'
                        OR u.full_name ILIKE '%' || $3 || '%')
         GROUP BY u.id
         ORDER BY u.created_at DESC
         LIMIT $1 OFFSET $2",
    )
    .bind(per_page)
    .bind((page - 1).max(0) * per_page)
    .bind(q)
    .fetch_all(pg)
    .await?)
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
