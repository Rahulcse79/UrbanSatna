use axum::extract::{Path, State};
use axum::Json;
use serde::Deserialize;
use uuid::Uuid;

use super::envelope::ApiResponse;
use crate::domain::error::AppError;
use crate::infra::db::{settings, support, users};
use crate::middleware::auth::CurrentUser;
use crate::state::AppState;

/// System account the chatbot speaks through (auto-provisioned).
const BOT_PHONE: &str = "+910000000001";

/// First-line chatbot: instant rule-based replies while the human team
/// is offline (support_online = false). A human takes over by flipping
/// the flag — the bot then stays silent.
fn bot_reply(text: &str) -> String {
    let t = text.to_lowercase();
    let greeting = matches!(
        t.trim(),
        "hi" | "hello" | "hey" | "namaste" | "नमस्ते" | "hii" | "hlo"
    );
    if t.contains("booking") || t.contains("बुकिंग") || t.contains("cancel") {
        "🤖 For booking help: open Bookings, tap the booking, and use \
         Cancel or Chat with your technician. Your arrival OTP is on the \
         booking card. A team member will follow up soon."
    } else if t.contains("payment")
        || t.contains("refund")
        || t.contains("भुगतान")
        || t.contains("paisa")
        || t.contains("money")
    {
        "🤖 Payments are collected after the service (cash/UPI). For a \
         wrong charge or refund, please also raise a ticket from Profile → \
         Report a problem — our team will review it quickly."
    } else if t.contains("worker")
        || t.contains("late")
        || t.contains("वर्कर")
        || t.contains("technician")
    {
        "🤖 You can see your technician's status on the booking card and \
         call them directly with the call button. If nobody accepted yet, \
         we're still searching nearby professionals."
    } else if greeting {
        "🤖 Namaste! I'm the Servexa assistant. Tell me about a booking, \
         payment, or worker issue — or type your question and our team \
         will reply as soon as they're online."
    } else {
        "🤖 Thanks for your message! Our support team is currently \
         offline and will reply as soon as possible. Meanwhile: booking \
         issues → Bookings tab · payments → pay after service (cash/UPI) \
         · urgent problems → Profile → Report a problem."
    }
    .to_string()
}

async fn maybe_bot_reply(state: &AppState, user_id: Uuid, text: &str) -> Result<(), AppError> {
    let online = settings::get_json(&state.pg, "support_online")
        .await?
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    if online {
        return Ok(()); // humans are on shift; the bot stays quiet
    }
    let (bot, created) = users::find_or_create_by_phone(&state.pg, BOT_PHONE).await?;
    if created || bot.full_name.is_none() {
        users::update_profile(
            &state.pg,
            bot.id,
            Some("Servexa Bot"),
            None,
            None,
            None,
            None,
            None,
            false,
        )
        .await?;
    }
    support::send(&state.pg, user_id, bot.id, &bot_reply(text)).await?;
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

/// Admin inbox: one row per conversation (perm bookings:manage:any).
pub async fn threads(
    State(state): State<AppState>,
    current: CurrentUser,
) -> Result<Json<ApiResponse<Vec<support::SupportThread>>>, AppError> {
    current.require_perm("bookings:manage:any")?;
    Ok(Json(ApiResponse::ok(support::threads(&state.pg).await?)))
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
