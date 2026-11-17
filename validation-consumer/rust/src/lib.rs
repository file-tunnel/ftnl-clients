#![forbid(unsafe_code)]

use ftnl_validation::{ProblemDetails, RequestMeta};
use garde::Validate;

pub fn validated_request_headers(meta: &RequestMeta) -> Result<Vec<(String, String)>, garde::Report> {
    meta.validate()?;
    let headers = [
        Some(("x-request-id".to_owned(), meta.request_id.clone())),
        Some(("traceparent".to_owned(), meta.trace_id.clone())),
        meta.locale
            .as_ref()
            .map(|locale| ("accept-language".to_owned(), locale.clone())),
    ]
    .into_iter()
    .flatten()
    .collect();
    Ok(headers)
}

pub fn validate_problem(problem: &ProblemDetails) -> Result<(), garde::Report> {
    problem.validate()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_before_transport() {
        let meta = RequestMeta {
            request_id: "req-1".into(),
            trace_id: "trace-1".into(),
            locale: None,
        };
        assert!(validated_request_headers(&meta).is_ok());
    }
}
