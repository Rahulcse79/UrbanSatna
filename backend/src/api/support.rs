use axum::extract::{Path, Query, State};
use axum::Json;
use serde::Deserialize;
use uuid::Uuid;

use super::envelope::ApiResponse;
use crate::domain::error::AppError;
use crate::infra::bot;
use crate::infra::db::{settings, support, users};
use crate::middleware::auth::CurrentUser;
use crate::state::AppState;

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
    support::send(&state.pg, user_id, bot_user.id, &reply).await?;
    Ok(())
}

fn valid_body(body: &str) -> Result<&str, AppError> {
    let body = body.trim();
    if body.is_empty() || body.len() > 2000 {
        return Err(AppError::Validation("message must be 1-2000 chars".into()));
    }
    Ok(body)
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
    let message = support::send(&state.pg, current.id, current.id, body).await?;
    // Chatbot answers instantly when the team is offline; the client's
    // thread refresh right after sending picks it up.
    maybe_bot_reply(&state, current.id, body).await?;
    Ok(Json(ApiResponse::ok(message)))
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
        support::send(&state.pg, user_id, current.id, body).await?,
    )))
}
