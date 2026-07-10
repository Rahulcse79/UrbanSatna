use axum::extract::{Path, Query, State};
use axum::Json;
use serde::{Deserialize, Serialize};
use serde_json::json;
use uuid::Uuid;

use super::envelope::ApiResponse;
use crate::domain::error::AppError;
use crate::infra::db::{audit, coupons};
use crate::middleware::auth::CurrentUser;
use crate::state::AppState;

#[derive(Deserialize)]
pub struct CheckQuery {
    pub code: String,
    pub service_id: Uuid,
}

#[derive(Serialize)]
pub struct CouponQuote {
    pub code: String,
    pub discount_paise: i64,
    pub final_paise: i64,
}

/// Live quote for the booking screen: is this code valid for me, and
/// what would I pay? Never redeems.
pub async fn check(
    State(state): State<AppState>,
    current: CurrentUser,
    Query(q): Query<CheckQuery>,
) -> Result<Json<ApiResponse<CouponQuote>>, AppError> {
    let base: Option<i64> = sqlx::query_scalar(
        "SELECT base_price_paise FROM services
         WHERE id = $1 AND is_active AND deleted_at IS NULL",
    )
    .bind(q.service_id)
    .fetch_optional(&state.pg)
    .await?;
    let Some(base_price) = base else {
        return Err(AppError::NotFound("service"));
    };
    let (_, discount) = coupons::preview(&state.pg, &q.code, current.id, base_price).await?;
    Ok(Json(ApiResponse::ok(CouponQuote {
        code: q.code.trim().to_uppercase(),
        discount_paise: discount,
        final_paise: base_price - discount,
    })))
}

#[derive(Deserialize)]
pub struct ListQuery {
    #[serde(default)]
    pub page: Option<i64>,
}

/// Admin coupon list, paginated 10/page.
pub async fn list(
    State(state): State<AppState>,
    current: CurrentUser,
    Query(q): Query<ListQuery>,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    current.require_perm("catalog:manage")?;
    let page = q.page.unwrap_or(1).max(1);
    let items = coupons::list_page(&state.pg, page, 10).await?;
    let total = items.first().map(|c| c.total).unwrap_or(0);
    Ok(Json(ApiResponse::ok(json!({
        "items": items,
        "total": total,
        "page": page,
        "per_page": 10,
    }))))
}

/// Offers the signed-in user can still use (active, never redeemed by
/// them) — powers the offer dropdown on the booking screen.
pub async fn available(
    State(state): State<AppState>,
    current: CurrentUser,
) -> Result<Json<ApiResponse<Vec<coupons::Coupon>>>, AppError> {
    Ok(Json(ApiResponse::ok(
        coupons::available_for(&state.pg, current.id).await?,
    )))
}

#[derive(Deserialize)]
pub struct NewCoupon {
    pub code: String,
    pub percent_off: Option<i32>,
    pub flat_off_paise: Option<i64>,
}

pub async fn create(
    State(state): State<AppState>,
    current: CurrentUser,
    Json(body): Json<NewCoupon>,
) -> Result<Json<ApiResponse<coupons::Coupon>>, AppError> {
    current.require_perm("catalog:manage")?;
    let code = body.code.trim();
    if code.len() < 3 || code.len() > 20 {
        return Err(AppError::Validation("code must be 3-20 characters".into()));
    }
    match (body.percent_off, body.flat_off_paise) {
        (Some(p), None) if (1..=90).contains(&p) => {}
        (None, Some(f)) if f > 0 => {}
        _ => {
            return Err(AppError::Validation(
                "set either percent_off (1-90) or flat_off_paise (> 0)".into(),
            ))
        }
    }
    let coupon = coupons::create(&state.pg, code, body.percent_off, body.flat_off_paise).await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "admin",
        "coupon.created",
        "coupon",
        Some(coupon.id),
        Some(json!({ "code": coupon.code })),
    )
    .await?;
    Ok(Json(ApiResponse::ok(coupon)))
}

#[derive(Deserialize)]
pub struct UpdateCoupon {
    pub is_active: bool,
}

pub async fn update(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(id): Path<Uuid>,
    Json(body): Json<UpdateCoupon>,
) -> Result<Json<ApiResponse<coupons::Coupon>>, AppError> {
    current.require_perm("catalog:manage")?;
    let coupon = coupons::set_active(&state.pg, id, body.is_active).await?;
    audit::log(
        &state.pg,
        Some(current.id),
        "admin",
        "coupon.updated",
        "coupon",
        Some(id),
        Some(json!({ "is_active": coupon.is_active })),
    )
    .await?;
    Ok(Json(ApiResponse::ok(coupon)))
}
