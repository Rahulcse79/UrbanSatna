use axum::extract::{Path, State};
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
