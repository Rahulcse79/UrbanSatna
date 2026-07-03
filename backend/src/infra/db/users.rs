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
}

/// Returns the user for this phone, creating one on first login.
/// The bool is `true` when the user was just created.
pub async fn find_or_create_by_phone(pg: &PgPool, phone: &str) -> Result<(User, bool), AppError> {
    if let Some(user) = sqlx::query_as::<_, User>(
        "SELECT id, phone, email, full_name FROM users
         WHERE phone = $1 AND deleted_at IS NULL",
    )
    .bind(phone)
    .fetch_optional(pg)
    .await?
    {
        return Ok((user, false));
    }
    let user = sqlx::query_as::<_, User>(
        "INSERT INTO users (id, phone) VALUES ($1, $2)
         RETURNING id, phone, email, full_name",
    )
    .bind(Uuid::now_v7())
    .bind(phone)
    .fetch_one(pg)
    .await?;
    Ok((user, true))
}

pub async fn get(pg: &PgPool, id: Uuid) -> Result<User, AppError> {
    sqlx::query_as::<_, User>(
        "SELECT id, phone, email, full_name FROM users
         WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(id)
    .fetch_optional(pg)
    .await?
    .ok_or(AppError::NotFound("user"))
}

pub async fn update_profile(
    pg: &PgPool,
    id: Uuid,
    full_name: Option<&str>,
    email: Option<&str>,
) -> Result<User, AppError> {
    sqlx::query_as::<_, User>(
        "UPDATE users SET
           full_name = COALESCE($2, full_name),
           email = COALESCE($3, email)
         WHERE id = $1 AND deleted_at IS NULL
         RETURNING id, phone, email, full_name",
    )
    .bind(id)
    .bind(full_name)
    .bind(email)
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
