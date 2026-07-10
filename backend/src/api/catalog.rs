use axum::extract::{Path, Query, State};
use axum::Json;
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use super::envelope::ApiResponse;
use crate::domain::error::AppError;
use crate::infra::db::{audit, catalog};
use crate::middleware::auth::CurrentUser;
use crate::state::AppState;

pub async fn list_categories(
    State(state): State<AppState>,
) -> Result<Json<ApiResponse<Vec<catalog::Category>>>, AppError> {
    Ok(Json(ApiResponse::ok(
        catalog::list_categories(&state.pg).await?,
    )))
}

pub async fn list_services(
    State(state): State<AppState>,
    Path(category_id): Path<Uuid>,
) -> Result<Json<ApiResponse<Vec<catalog::Service>>>, AppError> {
    Ok(Json(ApiResponse::ok(
        catalog::list_services(&state.pg, category_id).await?,
    )))
}

#[derive(Deserialize)]
pub struct SearchQuery {
    #[serde(default)]
    pub q: Option<String>,
    #[serde(default)]
    pub max_price_paise: Option<i64>,
}

/// Public advanced search across all services.
pub async fn search(
    State(state): State<AppState>,
    Query(query): Query<SearchQuery>,
) -> Result<Json<ApiResponse<Vec<catalog::SearchResult>>>, AppError> {
    Ok(Json(ApiResponse::ok(
        catalog::search(
            &state.pg,
            query.q.unwrap_or_default().trim(),
            query.max_price_paise,
        )
        .await?,
    )))
}

#[derive(Deserialize)]
pub struct PageQuery {
    #[serde(default)]
    pub page: Option<i64>,
}

/// Admin view: paginated (10/page), also returns deactivated rows so they
/// can be re-enabled. prev/next are driven by `total`.
pub async fn list_categories_admin(
    State(state): State<AppState>,
    current: CurrentUser,
    Query(query): Query<PageQuery>,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    current.require_perm("catalog:manage")?;
    let page = query.page.unwrap_or(1).max(1);
    let items = catalog::list_categories_page(&state.pg, page, 10).await?;
    let total = items.first().map(|c| c.total).unwrap_or(0);
    Ok(Json(ApiResponse::ok(json!({
        "items": items,
        "total": total,
        "page": page,
        "per_page": 10,
    }))))
}

/// Admin services for one category, paginated (10/page).
pub async fn list_services_admin(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(category_id): Path<Uuid>,
    Query(query): Query<PageQuery>,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    current.require_perm("catalog:manage")?;
    let page = query.page.unwrap_or(1).max(1);
    let items = catalog::list_services_page(&state.pg, category_id, page, 10).await?;
    let total = items.first().map(|s| s.total).unwrap_or(0);
    Ok(Json(ApiResponse::ok(json!({
        "items": items,
        "total": total,
        "page": page,
        "per_page": 10,
    }))))
}

#[derive(Deserialize)]
pub struct NewCategory {
    pub name: String,
    pub icon: Option<String>,
    #[serde(default)]
    pub sort_order: i32,
}

pub async fn create_category(
    State(state): State<AppState>,
    current: CurrentUser,
    Json(body): Json<NewCategory>,
) -> Result<Json<ApiResponse<catalog::Category>>, AppError> {
    current.require_perm("catalog:manage")?;
    if body.name.trim().is_empty() {
        return Err(AppError::Validation("name is required".into()));
    }
    let category = catalog::create_category(
        &state.pg,
        body.name.trim(),
        body.icon.as_deref(),
        body.sort_order,
    )
    .await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "admin",
        "category.created",
        "category",
        Some(category.id),
        Some(json!({ "name": category.name })),
    )
    .await?;
    Ok(Json(ApiResponse::ok(category)))
}

#[derive(Deserialize)]
pub struct NewService {
    pub category_id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub base_price_paise: i64,
    #[serde(default = "default_duration")]
    pub duration_min: i32,
}

fn default_duration() -> i32 {
    60
}

pub async fn create_service(
    State(state): State<AppState>,
    current: CurrentUser,
    Json(body): Json<NewService>,
) -> Result<Json<ApiResponse<catalog::Service>>, AppError> {
    current.require_perm("catalog:manage")?;
    if body.name.trim().is_empty() {
        return Err(AppError::Validation("name is required".into()));
    }
    if body.base_price_paise <= 0 {
        return Err(AppError::Validation("base_price_paise must be > 0".into()));
    }
    let service = catalog::create_service(
        &state.pg,
        body.category_id,
        body.name.trim(),
        body.description.as_deref(),
        body.base_price_paise,
        body.duration_min,
    )
    .await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "admin",
        "service.created",
        "service",
        Some(service.id),
        Some(json!({ "name": service.name, "price_paise": service.base_price_paise })),
    )
    .await?;
    Ok(Json(ApiResponse::ok(service)))
}

#[derive(Deserialize)]
pub struct UpdateCategory {
    pub name: Option<String>,
    pub icon: Option<String>,
    pub sort_order: Option<i32>,
    pub is_active: Option<bool>,
}

pub async fn update_category(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(id): Path<Uuid>,
    Json(body): Json<UpdateCategory>,
) -> Result<Json<ApiResponse<catalog::Category>>, AppError> {
    current.require_perm("catalog:manage")?;
    let category = catalog::update_category(
        &state.pg,
        id,
        body.name.as_deref(),
        body.icon.as_deref(),
        body.sort_order,
        body.is_active,
    )
    .await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "admin",
        "category.updated",
        "category",
        Some(id),
        Some(json!({ "is_active": category.is_active, "name": category.name })),
    )
    .await?;
    Ok(Json(ApiResponse::ok(category)))
}

#[derive(Deserialize)]
pub struct UpdateService {
    pub name: Option<String>,
    pub description: Option<String>,
    pub base_price_paise: Option<i64>,
    pub duration_min: Option<i32>,
    pub is_active: Option<bool>,
}

pub async fn update_service(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(id): Path<Uuid>,
    Json(body): Json<UpdateService>,
) -> Result<Json<ApiResponse<catalog::Service>>, AppError> {
    current.require_perm("catalog:manage")?;
    if body.base_price_paise.is_some_and(|p| p <= 0) {
        return Err(AppError::Validation("base_price_paise must be > 0".into()));
    }
    let service = catalog::update_service(
        &state.pg,
        id,
        body.name.as_deref(),
        body.description.as_deref(),
        body.base_price_paise,
        body.duration_min,
        body.is_active,
    )
    .await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "admin",
        "service.updated",
        "service",
        Some(id),
        Some(json!({
            "is_active": service.is_active,
            "price_paise": service.base_price_paise
        })),
    )
    .await?;
    Ok(Json(ApiResponse::ok(service)))
}
