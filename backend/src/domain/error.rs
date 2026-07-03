use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};

use crate::api::envelope::ApiResponse;

/// Application error. Every failure in a request path becomes one of these
/// and is mapped centrally to an HTTP status + stable error code. Handlers
/// never build error responses by hand.
#[allow(dead_code)] // variants land with Phase 1 (auth); remove then
#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("{0}")]
    Validation(String),
    #[error("unauthorized")]
    Unauthorized,
    #[error("forbidden")]
    Forbidden,
    #[error("{0} not found")]
    NotFound(&'static str),
    #[error("{0}")]
    Conflict(String),
    #[error("too many attempts, try again later")]
    RateLimited,
    #[error("invalid OTP")]
    OtpInvalid,
    #[error("OTP expired or not requested")]
    OtpExpired,
    #[error("dependency unavailable: {0}")]
    Unavailable(String),
    #[error(transparent)]
    Internal(#[from] anyhow::Error),
}

impl AppError {
    /// Stable, SCREAMING_SNAKE error codes — clients switch on these,
    /// never on the human-readable message.
    pub fn code(&self) -> &'static str {
        match self {
            Self::Validation(_) => "VALIDATION_ERROR",
            Self::Unauthorized => "UNAUTHORIZED",
            Self::Forbidden => "FORBIDDEN",
            Self::NotFound(_) => "NOT_FOUND",
            Self::Conflict(_) => "CONFLICT",
            Self::RateLimited => "RATE_LIMITED",
            Self::OtpInvalid => "OTP_INVALID",
            Self::OtpExpired => "OTP_EXPIRED",
            Self::Unavailable(_) => "SERVICE_UNAVAILABLE",
            Self::Internal(_) => "INTERNAL_ERROR",
        }
    }

    pub fn status(&self) -> StatusCode {
        match self {
            Self::Validation(_) => StatusCode::UNPROCESSABLE_ENTITY,
            Self::Unauthorized => StatusCode::UNAUTHORIZED,
            Self::Forbidden => StatusCode::FORBIDDEN,
            Self::NotFound(_) => StatusCode::NOT_FOUND,
            Self::Conflict(_) => StatusCode::CONFLICT,
            Self::RateLimited => StatusCode::TOO_MANY_REQUESTS,
            Self::OtpInvalid | Self::OtpExpired => StatusCode::UNAUTHORIZED,
            Self::Unavailable(_) => StatusCode::SERVICE_UNAVAILABLE,
            Self::Internal(_) => StatusCode::INTERNAL_SERVER_ERROR,
        }
    }
}

impl From<sqlx::Error> for AppError {
    fn from(err: sqlx::Error) -> Self {
        match err {
            sqlx::Error::RowNotFound => Self::NotFound("resource"),
            other => Self::Internal(anyhow::Error::new(other).context("database error")),
        }
    }
}

impl From<redis::RedisError> for AppError {
    fn from(err: redis::RedisError) -> Self {
        Self::Internal(anyhow::Error::new(err).context("redis error"))
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        // Internal details are logged, never sent to the client.
        let message = match &self {
            Self::Internal(err) => {
                tracing::error!(error = ?err, "internal error");
                "something went wrong".to_string()
            }
            other => other.to_string(),
        };
        let body = ApiResponse::<()>::error(self.code(), message);
        (self.status(), axum::Json(body)).into_response()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn errors_map_to_stable_codes_and_statuses() {
        let cases: Vec<(AppError, &str, StatusCode)> = vec![
            (
                AppError::Validation("bad phone".into()),
                "VALIDATION_ERROR",
                StatusCode::UNPROCESSABLE_ENTITY,
            ),
            (
                AppError::Unauthorized,
                "UNAUTHORIZED",
                StatusCode::UNAUTHORIZED,
            ),
            (AppError::Forbidden, "FORBIDDEN", StatusCode::FORBIDDEN),
            (
                AppError::NotFound("booking"),
                "NOT_FOUND",
                StatusCode::NOT_FOUND,
            ),
            (
                AppError::Conflict("already accepted".into()),
                "CONFLICT",
                StatusCode::CONFLICT,
            ),
            (
                AppError::Unavailable("redis".into()),
                "SERVICE_UNAVAILABLE",
                StatusCode::SERVICE_UNAVAILABLE,
            ),
            (
                AppError::Internal(anyhow::anyhow!("boom")),
                "INTERNAL_ERROR",
                StatusCode::INTERNAL_SERVER_ERROR,
            ),
        ];
        for (err, code, status) in cases {
            assert_eq!(err.code(), code);
            assert_eq!(err.status(), status);
        }
    }

    #[test]
    fn sqlx_row_not_found_maps_to_not_found() {
        let err: AppError = sqlx::Error::RowNotFound.into();
        assert_eq!(err.code(), "NOT_FOUND");
    }
}
