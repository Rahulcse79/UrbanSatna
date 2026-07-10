use axum::extract::State;
use axum::Json;
use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::json;

use super::envelope::ApiResponse;
use crate::domain::error::AppError;
use crate::infra::db::{audit, sessions, users};
use crate::infra::{jwt, otp};
use crate::middleware::auth::CurrentUser;
use crate::state::AppState;

fn validate_phone(phone: &str) -> Result<(), AppError> {
    let ok = phone.starts_with('+')
        && phone.len() >= 11
        && phone.len() <= 16
        && phone[1..].chars().all(|c| c.is_ascii_digit());
    if ok {
        Ok(())
    } else {
        Err(AppError::Validation(
            "phone must be E.164, e.g. +919876543210".into(),
        ))
    }
}

#[derive(Deserialize)]
pub struct OtpRequest {
    pub phone: String,
}

#[derive(Serialize)]
pub struct OtpRequested {
    pub message: &'static str,
    /// Present only when DEV_RETURN_OTP=true (no SMS provider wired yet).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dev_otp: Option<String>,
}

pub async fn request_otp(
    State(state): State<AppState>,
    Json(body): Json<OtpRequest>,
) -> Result<Json<ApiResponse<OtpRequested>>, AppError> {
    validate_phone(&body.phone)?;
    let mut redis = state.redis.clone();
    let code = otp::request(&mut redis, &body.phone, &state.config.jwt_secret).await?;
    // SMS provider integration lands in Phase 4; until then the dev flag
    // is the only way to receive the OTP.
    tracing::info!(phone = %mask(&body.phone), "OTP generated");
    Ok(Json(ApiResponse::ok(OtpRequested {
        message: "OTP sent",
        dev_otp: state.config.dev_return_otp.then_some(code),
    })))
}

#[derive(Deserialize)]
pub struct OtpVerify {
    pub phone: String,
    pub otp: String,
    pub device_id: Option<String>,
    pub device_name: Option<String>,
}

#[derive(Serialize)]
pub struct TokenPair {
    pub access_token: String,
    pub refresh_token: String,
    pub expires_in: i64,
    pub user: users::User,
    pub roles: Vec<String>,
}

pub async fn verify_otp(
    State(state): State<AppState>,
    Json(body): Json<OtpVerify>,
) -> Result<Json<ApiResponse<TokenPair>>, AppError> {
    validate_phone(&body.phone)?;
    let mut redis = state.redis.clone();
    otp::verify(&mut redis, &body.phone, &body.otp, &state.config.jwt_secret).await?;

    let (user, created) = users::find_or_create_by_phone(&state.pg, &body.phone).await?;
    // Blocked users cannot log in (admin lifts the block in User management).
    if user.is_blocked {
        return Err(AppError::Conflict(format!(
            "account blocked: {}",
            user.block_reason.as_deref().unwrap_or("contact support")
        )));
    }
    // Staff are not customers: admin accounts carry the admin role only
    // (self-heals accounts that predate the separation), everyone else
    // is a customer.
    if state.config.admin_phones.contains(&body.phone) {
        users::grant_role(&state.pg, user.id, "admin").await?;
        users::revoke_role(&state.pg, user.id, "customer").await?;
    } else {
        users::grant_role(&state.pg, user.id, "customer").await?;
    }
    if created {
        audit::log(
            &state.pg,
            Some(user.id),
            "customer",
            "user.registered",
            "user",
            Some(user.id),
            None,
        )
        .await?;
    }

    let (session_id, refresh_token) = sessions::create(
        &state.pg,
        user.id,
        body.device_id.as_deref(),
        body.device_name.as_deref(),
        state.config.refresh_ttl_days,
    )
    .await?;
    audit::log(
        &state.pg,
        Some(user.id),
        "customer",
        "auth.login",
        "session",
        Some(session_id),
        None,
    )
    .await?;

    let pair = issue_tokens(&state, user, session_id, refresh_token).await?;
    Ok(Json(ApiResponse::ok(pair)))
}

#[derive(Deserialize)]
pub struct RefreshRequest {
    pub refresh_token: String,
}

pub async fn refresh(
    State(state): State<AppState>,
    Json(body): Json<RefreshRequest>,
) -> Result<Json<ApiResponse<TokenPair>>, AppError> {
    let (session_id, user_id, new_refresh) = sessions::rotate(
        &state.pg,
        &body.refresh_token,
        state.config.refresh_ttl_days,
    )
    .await?;
    let user = users::get(&state.pg, user_id).await?;
    if user.is_blocked {
        return Err(AppError::Unauthorized);
    }
    let pair = issue_tokens(&state, user, session_id, new_refresh).await?;
    Ok(Json(ApiResponse::ok(pair)))
}

#[derive(Deserialize, Default)]
pub struct LogoutRequest {
    #[serde(default)]
    pub all_devices: bool,
}

pub async fn logout(
    State(state): State<AppState>,
    current: CurrentUser,
    body: Option<Json<LogoutRequest>>,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    let all = body.map(|b| b.all_devices).unwrap_or(false);
    if all {
        sessions::revoke_all(&state.pg, current.id).await?;
    } else {
        sessions::revoke(&state.pg, current.session_id, current.id).await?;
    }
    audit::log(
        &state.pg,
        Some(current.id),
        "customer",
        "auth.logout",
        "session",
        Some(current.session_id),
        Some(json!({ "all_devices": all })),
    )
    .await?;
    Ok(Json(ApiResponse::ok(json!({ "logged_out": true }))))
}

async fn issue_tokens(
    state: &AppState,
    user: users::User,
    session_id: uuid::Uuid,
    refresh_token: String,
) -> Result<TokenPair, AppError> {
    let (roles, perms) = users::roles_and_perms(&state.pg, user.id).await?;
    let now = Utc::now().timestamp();
    let claims = jwt::Claims {
        sub: user.id,
        sid: session_id,
        phone: user.phone.clone(),
        roles: roles.clone(),
        perms,
        iat: now,
        exp: now + state.config.access_ttl_secs,
    };
    Ok(TokenPair {
        access_token: jwt::sign(&claims, &state.config.jwt_secret)?,
        refresh_token,
        expires_in: state.config.access_ttl_secs,
        user,
        roles,
    })
}

fn mask(phone: &str) -> String {
    if phone.len() > 4 {
        format!("{}••••{}", &phone[..3], &phone[phone.len() - 2..])
    } else {
        "••••".into()
    }
}
