use axum::body::Bytes;
use axum::extract::{Path, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Deserialize;
use uuid::Uuid;

use super::envelope::ApiResponse;
use crate::domain::error::AppError;
use crate::infra::db::chat;
use crate::middleware::auth::CurrentUser;
use crate::state::AppState;

/// Product rule: chat attachments are PNG/JPG images or short MP4 videos,
/// at most 15 MB, magic-byte checked.
pub const MAX_ATTACHMENT_BYTES: usize = 15 * 1024 * 1024;

fn validate_media(body: &Bytes, headers: &HeaderMap) -> Result<&'static str, AppError> {
    if body.len() > MAX_ATTACHMENT_BYTES {
        return Err(AppError::Validation(
            "attachment must be under 15 MB".into(),
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

/// A participant is the booking's customer or its assigned worker;
/// staff with bookings:read:any (support) may read but not write.
async fn require_participant(
    state: &AppState,
    booking_id: Uuid,
    current: &CurrentUser,
    read_only: bool,
) -> Result<(), AppError> {
    if chat::is_participant(&state.pg, booking_id, current.id).await? {
        return Ok(());
    }
    if read_only && current.require_perm("bookings:read:any").is_ok() {
        return Ok(());
    }
    Err(AppError::Forbidden)
}

pub async fn list(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(booking_id): Path<Uuid>,
) -> Result<Json<ApiResponse<Vec<chat::ChatMessage>>>, AppError> {
    require_participant(&state, booking_id, &current, true).await?;
    Ok(Json(ApiResponse::ok(
        chat::list(&state.pg, booking_id).await?,
    )))
}

#[derive(Deserialize)]
pub struct NewMessage {
    pub body: String,
}

pub async fn send_text(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(booking_id): Path<Uuid>,
    Json(msg): Json<NewMessage>,
) -> Result<Json<ApiResponse<chat::ChatMessage>>, AppError> {
    require_participant(&state, booking_id, &current, false).await?;
    let body = msg.body.trim();
    if body.is_empty() || body.len() > 2000 {
        return Err(AppError::Validation("message must be 1-2000 chars".into()));
    }
    let message = chat::send(&state.pg, booking_id, current.id, Some(body), None).await?;
    Ok(Json(ApiResponse::ok(message)))
}

pub async fn send_attachment(
    State(state): State<AppState>,
    current: CurrentUser,
    Path(booking_id): Path<Uuid>,
    headers: HeaderMap,
    body: Bytes,
) -> Result<Json<ApiResponse<chat::ChatMessage>>, AppError> {
    require_participant(&state, booking_id, &current, false).await?;
    let mime = validate_media(&body, &headers)?;
    let message = chat::send(&state.pg, booking_id, current.id, None, Some((&body, mime))).await?;
    Ok(Json(ApiResponse::ok(message)))
}

pub async fn attachment(
    State(state): State<AppState>,
    current: CurrentUser,
    Path((booking_id, message_id)): Path<(Uuid, Uuid)>,
) -> Result<Response, AppError> {
    require_participant(&state, booking_id, &current, true).await?;
    match chat::attachment(&state.pg, booking_id, message_id).await? {
        Some((bytes, mime)) => Ok(([(header::CONTENT_TYPE, mime)], bytes).into_response()),
        None => Ok(StatusCode::NOT_FOUND.into_response()),
    }
}
