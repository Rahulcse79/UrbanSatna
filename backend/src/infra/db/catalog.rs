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

/// Admin category row: enriched with the count of its (non-deleted)
/// services so the card can show it without an extra request per row.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct AdminCategory {
    pub id: Uuid,
    pub name: String,
    pub icon: Option<String>,
    pub sort_order: i32,
    pub is_active: bool,
    pub service_count: i64,
    /// Same value on every row of a page — drives prev/next.
    #[serde(skip_serializing)]
    pub total: i64,
}

/// Admin listing, one page: includes deactivated rows so they can be
/// re-enabled. Server-side pagination keeps the payload to `per_page`.
pub async fn list_categories_page(
    pg: &PgPool,
    page: i64,
    per_page: i64,
) -> Result<Vec<AdminCategory>, AppError> {
    Ok(sqlx::query_as::<_, AdminCategory>(
        "SELECT c.id, c.name, c.icon, c.sort_order, c.is_active,
                (SELECT count(*) FROM services s
                   WHERE s.category_id = c.id AND s.deleted_at IS NULL)
                    AS service_count,
                count(*) OVER() AS total
         FROM categories c
         WHERE c.deleted_at IS NULL
         ORDER BY c.sort_order, c.name
         LIMIT $1 OFFSET $2",
    )
    .bind(per_page)
    .bind((page - 1).max(0) * per_page)
    .fetch_all(pg)
    .await?)
}

/// A service row plus the page's total (window count) for pagination.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct AdminService {
    pub id: Uuid,
    pub category_id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub base_price_paise: i64,
    pub duration_min: i32,
    pub is_active: bool,
    #[serde(skip_serializing)]
    pub total: i64,
}

/// Admin listing for one category, one page (includes deactivated rows).
pub async fn list_services_page(
    pg: &PgPool,
    category_id: Uuid,
    page: i64,
    per_page: i64,
) -> Result<Vec<AdminService>, AppError> {
    Ok(sqlx::query_as::<_, AdminService>(
        "SELECT id, category_id, name, description, base_price_paise,
                duration_min, is_active, count(*) OVER() AS total
         FROM services
         WHERE category_id = $1 AND deleted_at IS NULL
         ORDER BY name
         LIMIT $2 OFFSET $3",
    )
    .bind(category_id)
    .bind(per_page)
    .bind((page - 1).max(0) * per_page)
    .fetch_all(pg)
    .await?)
}

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct SearchResult {
    pub id: Uuid,
    pub category_id: Uuid,
    pub category_name: String,
    pub name: String,
    pub description: Option<String>,
    pub base_price_paise: i64,
    pub duration_min: i32,
}

/// Advanced search across service name/description/category, optional
/// price ceiling; active rows only.
pub async fn search(
    pg: &PgPool,
    q: &str,
    max_price_paise: Option<i64>,
) -> Result<Vec<SearchResult>, AppError> {
    Ok(sqlx::query_as::<_, SearchResult>(
        "SELECT s.id, s.category_id, c.name AS category_name, s.name,
                s.description, s.base_price_paise, s.duration_min
         FROM services s
         JOIN categories c ON c.id = s.category_id
         WHERE s.is_active AND s.deleted_at IS NULL
           AND c.is_active AND c.deleted_at IS NULL
           AND ($1 = '' OR s.name ILIKE '%' || $1 || '%'
                        OR s.description ILIKE '%' || $1 || '%'
                        OR c.name ILIKE '%' || $1 || '%')
           AND ($2::bigint IS NULL OR s.base_price_paise <= $2)
         ORDER BY s.base_price_paise ASC
         LIMIT 50",
    )
    .bind(q)
    .bind(max_price_paise)
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
