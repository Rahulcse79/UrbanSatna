use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::PgPool;
use uuid::Uuid;

use crate::domain::error::AppError;

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct Coupon {
    pub id: Uuid,
    pub code: String,
    pub percent_off: Option<i32>,
    pub flat_off_paise: Option<i64>,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
}

const COLS: &str = "id, code, percent_off, flat_off_paise, is_active, created_at";

pub async fn list(pg: &PgPool) -> Result<Vec<Coupon>, AppError> {
    Ok(sqlx::query_as::<_, Coupon>(&format!(
        "SELECT {COLS} FROM coupons ORDER BY created_at DESC"
    ))
    .fetch_all(pg)
    .await?)
}

pub async fn create(
    pg: &PgPool,
    code: &str,
    percent_off: Option<i32>,
    flat_off_paise: Option<i64>,
) -> Result<Coupon, AppError> {
    sqlx::query_as::<_, Coupon>(&format!(
        "INSERT INTO coupons (id, code, percent_off, flat_off_paise)
         VALUES ($1, upper($2), $3, $4) ON CONFLICT (code) DO NOTHING
         RETURNING {COLS}"
    ))
    .bind(Uuid::now_v7())
    .bind(code.trim())
    .bind(percent_off)
    .bind(flat_off_paise)
    .fetch_optional(pg)
    .await?
    .ok_or_else(|| AppError::Conflict("coupon code already exists".into()))
}

pub async fn set_active(pg: &PgPool, id: Uuid, active: bool) -> Result<Coupon, AppError> {
    sqlx::query_as::<_, Coupon>(&format!(
        "UPDATE coupons SET is_active = $2 WHERE id = $1 RETURNING {COLS}"
    ))
    .bind(id)
    .bind(active)
    .fetch_optional(pg)
    .await?
    .ok_or(AppError::NotFound("coupon"))
}

/// Offers this user can still use: active and never redeemed by them.
pub async fn available_for(pg: &PgPool, user_id: Uuid) -> Result<Vec<Coupon>, AppError> {
    Ok(sqlx::query_as::<_, Coupon>(&format!(
        "SELECT {COLS} FROM coupons c
         WHERE c.is_active AND NOT EXISTS (
            SELECT 1 FROM coupon_redemptions r
             WHERE r.coupon_id = c.id AND r.user_id = $1)
         ORDER BY c.created_at DESC"
    ))
    .bind(user_id)
    .fetch_all(pg)
    .await?)
}

/// Discount this user would get on `price_paise`, without redeeming.
/// The final price never drops below ₹1 (schema requires price > 0).
pub async fn preview(
    pg: &PgPool,
    code: &str,
    user_id: Uuid,
    price_paise: i64,
) -> Result<(Uuid, i64), AppError> {
    let coupon: Option<Coupon> = sqlx::query_as(&format!(
        "SELECT {COLS} FROM coupons WHERE code = upper($1) AND is_active"
    ))
    .bind(code.trim())
    .fetch_optional(pg)
    .await?;
    let Some(coupon) = coupon else {
        return Err(AppError::NotFound("coupon"));
    };
    let used: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM coupon_redemptions
          WHERE coupon_id = $1 AND user_id = $2)",
    )
    .bind(coupon.id)
    .bind(user_id)
    .fetch_one(pg)
    .await?;
    if used {
        return Err(AppError::Conflict("coupon already used".into()));
    }
    let raw = match (coupon.percent_off, coupon.flat_off_paise) {
        (Some(pct), _) => price_paise * i64::from(pct) / 100,
        (None, Some(flat)) => flat,
        (None, None) => 0,
    };
    Ok((coupon.id, raw.clamp(0, price_paise - 100)))
}
