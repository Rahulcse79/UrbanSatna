use crate::domain::error::AppError;

/// Booking lifecycle (mockup flow, no payments/maps yet):
/// pending → accepted → en_route → in_progress → completed
/// pending|accepted → cancelled (by the customer)
pub const PENDING: &str = "pending";
pub const ACCEPTED: &str = "accepted";
pub const EN_ROUTE: &str = "en_route";
pub const IN_PROGRESS: &str = "in_progress";
pub const COMPLETED: &str = "completed";
#[allow(dead_code)] // used by tests today; dispatch/cleanup jobs next
pub const CANCELLED: &str = "cancelled";

/// Worker actions advancing an assigned booking.
pub fn next_status_for_action(action: &str, current: &str) -> Result<&'static str, AppError> {
    match (action, current) {
        ("en_route", ACCEPTED) => Ok(EN_ROUTE),
        ("start", EN_ROUTE) => Ok(IN_PROGRESS),
        ("complete", IN_PROGRESS) => Ok(COMPLETED),
        ("en_route" | "start" | "complete", _) => Err(AppError::Conflict(format!(
            "cannot {action} a booking in status {current}"
        ))),
        _ => Err(AppError::Validation(format!("unknown action '{action}'"))),
    }
}

pub fn can_cancel(current: &str) -> bool {
    matches!(current, PENDING | ACCEPTED)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn happy_path_transitions() {
        assert_eq!(
            next_status_for_action("en_route", ACCEPTED).unwrap(),
            EN_ROUTE
        );
        assert_eq!(
            next_status_for_action("start", EN_ROUTE).unwrap(),
            IN_PROGRESS
        );
        assert_eq!(
            next_status_for_action("complete", IN_PROGRESS).unwrap(),
            COMPLETED
        );
    }

    #[test]
    fn out_of_order_transitions_rejected() {
        assert!(next_status_for_action("complete", PENDING).is_err());
        assert!(next_status_for_action("start", ACCEPTED).is_err());
        assert!(next_status_for_action("en_route", COMPLETED).is_err());
        assert!(next_status_for_action("fly", ACCEPTED).is_err());
    }

    #[test]
    fn cancel_only_before_work_starts() {
        assert!(can_cancel(PENDING));
        assert!(can_cancel(ACCEPTED));
        assert!(!can_cancel(EN_ROUTE));
        assert!(!can_cancel(IN_PROGRESS));
        assert!(!can_cancel(COMPLETED));
        assert!(!can_cancel(CANCELLED));
    }
}
