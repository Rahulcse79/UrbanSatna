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
}

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct Service {
    pub id: Uuid,
    pub category_id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub base_price_paise: i64,
    pub duration_min: i32,
}

pub async fn list_categories(pg: &PgPool) -> Result<Vec<Category>, AppError> {
    Ok(sqlx::query_as::<_, Category>(
        "SELECT id, name, icon, sort_order FROM categories
         WHERE is_active AND deleted_at IS NULL
         ORDER BY sort_order, name",
    )
    .fetch_all(pg)
    .await?)
}

pub async fn list_services(pg: &PgPool, category_id: Uuid) -> Result<Vec<Service>, AppError> {
    Ok(sqlx::query_as::<_, Service>(
        "SELECT id, category_id, name, description, base_price_paise, duration_min
         FROM services
         WHERE category_id = $1 AND is_active AND deleted_at IS NULL
         ORDER BY name",
    )
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
    Ok(sqlx::query_as::<_, Category>(
        "INSERT INTO categories (id, name, icon, sort_order)
         VALUES ($1, $2, $3, $4)
         RETURNING id, name, icon, sort_order",
    )
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
    Ok(sqlx::query_as::<_, Service>(
        "INSERT INTO services (id, category_id, name, description, base_price_paise, duration_min)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id, category_id, name, description, base_price_paise, duration_min",
    )
    .bind(Uuid::now_v7())
    .bind(category_id)
    .bind(name)
    .bind(description)
    .bind(base_price_paise)
    .bind(duration_min)
    .fetch_one(pg)
    .await?)
}
