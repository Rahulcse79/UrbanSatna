use serde::Serialize;
use sqlx::PgPool;
use uuid::Uuid;

use crate::domain::error::AppError;

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct Category {
    pub id: Uuid,
    pub name: String,
    pub icon: Option<String>,
    pub sort_order: i32,
    pub is_active: bool,
}

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct Service {
    pub id: Uuid,
    pub category_id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub base_price_paise: i64,
    pub duration_min: i32,
    pub is_active: bool,
}

const CATEGORY_COLS: &str = "id, name, icon, sort_order, is_active";
const SERVICE_COLS: &str =
    "id, category_id, name, description, base_price_paise, duration_min, is_active";

/// Public listing: active rows only.
pub async fn list_categories(pg: &PgPool) -> Result<Vec<Category>, AppError> {
    Ok(sqlx::query_as::<_, Category>(&format!(
        "SELECT {CATEGORY_COLS} FROM categories
         WHERE is_active AND deleted_at IS NULL
         ORDER BY sort_order, name"
    ))
    .fetch_all(pg)
    .await?)
}

pub async fn list_services(pg: &PgPool, category_id: Uuid) -> Result<Vec<Service>, AppError> {
    Ok(sqlx::query_as::<_, Service>(&format!(
        "SELECT {SERVICE_COLS} FROM services
         WHERE category_id = $1 AND is_active AND deleted_at IS NULL
         ORDER BY name"
    ))
    .bind(category_id)
    .fetch_all(pg)
    .await?)
}

/// Admin listing: includes deactivated rows so they can be re-enabled.
pub async fn list_categories_all(pg: &PgPool) -> Result<Vec<Category>, AppError> {
    Ok(sqlx::query_as::<_, Category>(&format!(
        "SELECT {CATEGORY_COLS} FROM categories
         WHERE deleted_at IS NULL ORDER BY sort_order, name"
    ))
    .fetch_all(pg)
    .await?)
}

pub async fn list_services_all(pg: &PgPool, category_id: Uuid) -> Result<Vec<Service>, AppError> {
    Ok(sqlx::query_as::<_, Service>(&format!(
        "SELECT {SERVICE_COLS} FROM services
         WHERE category_id = $1 AND deleted_at IS NULL ORDER BY name"
    ))
    .bind(category_id)
    .fetch_all(pg)
    .await?)
}

pub async fn create_category(
    pg: &PgPool,
    name: &str,
    icon: Option<&str>,
    sort_order: i32,
) -> Result<Category, AppError> {
    Ok(sqlx::query_as::<_, Category>(&format!(
        "INSERT INTO categories (id, name, icon, sort_order)
         VALUES ($1, $2, $3, $4) RETURNING {CATEGORY_COLS}"
    ))
    .bind(Uuid::now_v7())
    .bind(name)
    .bind(icon)
    .bind(sort_order)
    .fetch_one(pg)
    .await?)
}

pub async fn create_service(
    pg: &PgPool,
    category_id: Uuid,
    name: &str,
    description: Option<&str>,
    base_price_paise: i64,
    duration_min: i32,
) -> Result<Service, AppError> {
    Ok(sqlx::query_as::<_, Service>(&format!(
        "INSERT INTO services (id, category_id, name, description, base_price_paise, duration_min)
         VALUES ($1, $2, $3, $4, $5, $6) RETURNING {SERVICE_COLS}"
    ))
    .bind(Uuid::now_v7())
    .bind(category_id)
    .bind(name)
    .bind(description)
    .bind(base_price_paise)
    .bind(duration_min)
    .fetch_one(pg)
    .await?)
}

/// Partial update; absent fields keep their current values.
pub async fn update_category(
    pg: &PgPool,
    id: Uuid,
    name: Option<&str>,
    icon: Option<&str>,
    sort_order: Option<i32>,
    is_active: Option<bool>,
) -> Result<Category, AppError> {
    sqlx::query_as::<_, Category>(&format!(
        "UPDATE categories SET
           name = COALESCE($2, name),
           icon = COALESCE($3, icon),
           sort_order = COALESCE($4, sort_order),
           is_active = COALESCE($5, is_active)
         WHERE id = $1 AND deleted_at IS NULL
         RETURNING {CATEGORY_COLS}"
    ))
    .bind(id)
    .bind(name)
    .bind(icon)
    .bind(sort_order)
    .bind(is_active)
    .fetch_optional(pg)
    .await?
    .ok_or(AppError::NotFound("category"))
}

pub async fn update_service(
    pg: &PgPool,
    id: Uuid,
    name: Option<&str>,
    description: Option<&str>,
    base_price_paise: Option<i64>,
    duration_min: Option<i32>,
    is_active: Option<bool>,
) -> Result<Service, AppError> {
    sqlx::query_as::<_, Service>(&format!(
        "UPDATE services SET
           name = COALESCE($2, name),
           description = COALESCE($3, description),
           base_price_paise = COALESCE($4, base_price_paise),
           duration_min = COALESCE($5, duration_min),
           is_active = COALESCE($6, is_active)
         WHERE id = $1 AND deleted_at IS NULL
         RETURNING {SERVICE_COLS}"
    ))
    .bind(id)
    .bind(name)
    .bind(description)
    .bind(base_price_paise)
    .bind(duration_min)
    .bind(is_active)
    .fetch_optional(pg)
    .await?
    .ok_or(AppError::NotFound("service"))
}
