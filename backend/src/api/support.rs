use axum::body::Bytes;
use axum::extract::{Path, Query, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Deserialize;
use uuid::Uuid;

use super::envelope::ApiResponse;
use crate::domain::error::AppError;
use crate::infra::bot;
use crate::infra::db::{settings, support, users};
use crate::middleware::auth::CurrentUser;
use crate::state::AppState;

/// Product rule: support-chat attachments are PNG/JPG images or short
/// MP4 videos, at most 10 MB, magic-byte checked.
pub const MAX_ATTACHMENT_BYTES: usize = 10 * 1024 * 1024;

/// First-line chatbot: instant replies (AI when configured, keyword bot
/// otherwise) while the human team is offline (support_online = false).
/// A human takes over by flipping the flag — the bot then stays silent.
async fn maybe_bot_reply(state: &AppState, user_id: Uuid, text: &str) -> Result<(), AppError> {
    let online = settings::get_json(&state.pg, "support_online")
        .await?
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    if online {
        return Ok(()); // humans are on shift; the bot stays quiet
    }
    let (bot_user, created) = users::find_or_create_by_phone(&state.pg, bot::BOT_PHONE).await?;
    if created || bot_user.full_name.is_none() {
        users::update_profile(
            &state.pg,
            bot_user.id,
            Some(bot::BOT_NAME),
            None,
            None,
            None,
            None,
            None,
            false,
        )
        .await?;
    }
    // Includes the message just sent — that's the turn the bot answers.
    let history = support::thread(&state.pg, user_id).await?;
    let reply = state.bot.reply(&history, user_id, text).await;
    support::send(&state.pg, user_id, bot_user.id, Some(&reply), None).await?;
    Ok(())
}

fn valid_body(body: &str) -> Result<&str, AppError> {
    let body = body.trim();
    if body.is_empty() || body.len() > 2000 {
        return Err(AppError::Validation("message must be 1-2000 chars".into()));
    }
    Ok(body)
}

/// Enforces the 10 MB ceiling and detects PNG / JPG / MP4 by magic
/// bytes, so a mis-typed content-type can't smuggle another format past
/// the client. Kept in sync with the mobile picker's validation.
fn validate_media(body: &Bytes, headers: &HeaderMap) -> Result<&'static str, AppError> {
    if body.len() > MAX_ATTACHMENT_BYTES {
        return Err(AppError::Validation(
            "attachment must be under 10 MB".into(),
        ));
    }
    let mime = if body.starts_with(&[0x89, b'P', b'N', b'G']) {
        "image/png"
    } else if body.starts_with(&[0xFF, 0xD8, 0xFF]) {
        "image/jpeg"
    } else if body.len() > 12 && &body[4..8] == b"ftyp" {
        "video/mp4"
    } else {
        return Err(AppError::Validation(
            "only PNG, JPG or MP4 attachments allowed".into(),
        ));
    };
    if let Some(declared) = headers
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
    {
        if !declared.starts_with("image/") && !declared.starts_with("video/") {
            return Err(AppError::Validation(
                "content-type must be image or video".into(),
            ));
        }
    }
    Ok(mime)
}

/// The signed-in user's own support thread.
pub async fn my_thread(
    State(state): State<AppState>,
    current: CurrentUser,
) -> Result<Json<ApiResponse<Vec<support::SupportMessage>>>, AppError> {
    Ok(Json(ApiResponse::ok(
        support::thread(&state.pg, current.id).await?,
    )))
}

#[derive(Deserialize)]
pub struct NewMessage {
    pub body: String,
}

pub async fn send(
    State(state): State<AppState>,
    current: CurrentUser,
    Json(msg): Json<NewMessage>,
) -> Result<Json<ApiResponse<support::SupportMessage>>, AppError> {
    let body = valid_body(&msg.body)?;
    let message = support::send(&state.pg, current.id, current.id, Some(body), None).await?;
    // Chatbot answers instantly when the team is offline; the client's
    // thread refresh right after sending picks it up.
    maybe_bot_reply(&state, current.id, body).await?;
    Ok(Json(ApiResponse::ok(message)))
}

/// Upload an attachment on the customer's own thread. Raw body, PNG/JPG
/// image or short MP4 video, ≤ 10 MB. The chatbot is intentionally quiet
/// here — it only reacts to text.
pub async fn send_attachment(
    State(state): State<AppState>,
    current: CurrentUser,
    headers: HeaderMap,
    body: Bytes,
) -> Result<Json<ApiResponse<support::SupportMessage>>, AppError> {
    let mime = validate_media(&body, &headers)?;
    let message =
        support::send(&state.pg, current.id, current.id, None, Some((&body, mime))).await?;
    Ok(Json(ApiResponse::ok(message)))
}

/// Bytes for one attachment on the signed-in user's own thread.
pub async fn attachment(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(message_id): Path<Uuid>,
) -> Result<Response, AppError> {
    match support::attachment(&state.pg, current.id, message_id).await? {
        Some((bytes, mime)) => Ok(([(header::CONTENT_TYPE, mime)], bytes).into_response()),
        None => Ok(StatusCode::NOT_FOUND.into_response()),
    }
}

#[derive(Deserialize)]
pub struct InboxQuery {
    #[serde(default)]
    pub page: Option<i64>,
}

/// Admin inbox: one row per conversation, paginated 10/page
/// (perm bookings:manage:any).
pub async fn threads(
    State(state): State<AppState>,
    current: CurrentUser,
    Query(query): Query<InboxQuery>,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    current.require_perm("bookings:manage:any")?;
    let page = query.page.unwrap_or(1).max(1);
    let items = support::threads(&state.pg, page, 10).await?;
    let total = items.first().map(|t| t.total).unwrap_or(0);
    Ok(Json(ApiResponse::ok(serde_json::json!({
        "items": items,
        "total": total,
        "page": page,
        "per_page": 10,
    }))))
}

pub async fn admin_thread(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(user_id): Path<Uuid>,
) -> Result<Json<ApiResponse<Vec<support::SupportMessage>>>, AppError> {
    current.require_perm("bookings:manage:any")?;
    Ok(Json(ApiResponse::ok(
        support::thread(&state.pg, user_id).await?,
    )))
}

pub async fn admin_send(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(user_id): Path<Uuid>,
    Json(msg): Json<NewMessage>,
) -> Result<Json<ApiResponse<support::SupportMessage>>, AppError> {
    current.require_perm("bookings:manage:any")?;
    let body = valid_body(&msg.body)?;
    Ok(Json(ApiResponse::ok(
        support::send(&state.pg, user_id, current.id, Some(body), None).await?,
    )))
}

/// Staff attaches an image / video to a customer's thread.
pub async fn admin_send_attachment(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(user_id): Path<Uuid>,
    headers: HeaderMap,
    body: Bytes,
) -> Result<Json<ApiResponse<support::SupportMessage>>, AppError> {
    current.require_perm("bookings:manage:any")?;
    let mime = validate_media(&body, &headers)?;
    Ok(Json(ApiResponse::ok(
        support::send(&state.pg, user_id, current.id, None, Some((&body, mime))).await?,
    )))
}

/// Staff downloads an attachment from a customer's thread.
pub async fn admin_attachment(
    State(state): State<AppState>,
    current: CurrentUser,
    Path((user_id, message_id)): Path<(Uuid, Uuid)>,
) -> Result<Response, AppError> {
    current.require_perm("bookings:manage:any")?;
    match support::attachment(&state.pg, user_id, message_id).await? {
        Some((bytes, mime)) => Ok(([(header::CONTENT_TYPE, mime)], bytes).into_response()),
        None => Ok(StatusCode::NOT_FOUND.into_response()),
    }
}
