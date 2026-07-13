use serde::Serialize;

/// Uniform response envelope. Every endpoint returns this shape —
/// the mobile apps and admin panel depend on it (CLAUDE.md §7).
#[derive(Debug, Serialize)]
pub struct ApiResponse<T: Serialize> {
    pub success: bool,
    pub data: Option<T>,
    pub error: Option<ApiErrorBody>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub meta: Option<serde_json::Value>,
}

#[derive(Debug, Serialize)]
pub struct ApiErrorBody {
    pub code: String,
    pub message: String,
}

impl<T: Serialize> ApiResponse<T> {
    pub fn ok(data: T) -> Self {
        Self {
            success: true,
            data: Some(data),
            error: None,
            meta: None,
        }
    }

    pub fn ok_with_meta(data: T, meta: serde_json::Value) -> Self {
        Self {
            success: true,
            data: Some(data),
            error: None,
            meta: Some(meta),
        }
    }

    pub fn error(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            success: false,
            data: None,
            error: Some(ApiErrorBody {
                code: code.into(),
                message: message.into(),
            }),
            meta: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ok_envelope_shape() {
        let json = serde_json::to_value(ApiResponse::ok(serde_json::json!({"id": 1}))).unwrap();
        assert_eq!(json["success"], true);
        assert_eq!(json["data"]["id"], 1);
        assert!(json["error"].is_null());
        assert!(json.get("meta").is_none(), "meta omitted when None");
    }

    #[test]
    fn error_envelope_shape() {
        let json =
            serde_json::to_value(ApiResponse::<()>::error("NOT_FOUND", "route not found")).unwrap();
        assert_eq!(json["success"], false);
        assert!(json["data"].is_null());
        assert_eq!(json["error"]["code"], "NOT_FOUND");
        assert_eq!(json["error"]["message"], "route not found");
    }
}
