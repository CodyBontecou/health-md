use std::path::{Component, PathBuf};

use unicode_casefold::UnicodeCaseFold as _;
use unicode_normalization::UnicodeNormalization as _;

use crate::ClientError;

const MAXIMUM_RELATIVE_PATH_BYTES: usize = 4_096;

pub(crate) fn validate_generated_relative_path(value: &str) -> Result<PathBuf, ClientError> {
    if value.is_empty()
        || value.len() > MAXIMUM_RELATIVE_PATH_BYTES
        || value.starts_with('/')
        || value.ends_with('/')
        || value.contains(['\\', '\0', ':', '<', '>', '"', '|', '?', '*'])
        || value.chars().any(char::is_control)
        || value.split('/').any(invalid_segment)
    {
        return Err(invalid("generated relative path is invalid"));
    }

    let path = PathBuf::from(value);
    if path.is_absolute()
        || path
            .components()
            .any(|component| !matches!(component, Component::Normal(_)))
    {
        return Err(invalid("generated relative path is unsafe"));
    }
    Ok(path)
}

pub(crate) fn generated_path_collision_key(value: &str) -> String {
    value.nfd().case_fold().nfd().collect()
}

pub(crate) fn generated_paths_conflict(left: &str, right: &str) -> bool {
    let left = generated_path_collision_key(left);
    let right = generated_path_collision_key(right);
    left == right
        || left
            .strip_prefix(&right)
            .is_some_and(|suffix| suffix.starts_with('/'))
        || right
            .strip_prefix(&left)
            .is_some_and(|suffix| suffix.starts_with('/'))
}

fn invalid_segment(segment: &str) -> bool {
    segment.is_empty()
        || matches!(segment, "." | "..")
        || segment.ends_with(['.', ' '])
        || is_windows_reserved_name(segment)
}

fn is_windows_reserved_name(segment: &str) -> bool {
    let stem = segment.split('.').next().unwrap_or(segment);
    let folded: String = stem.chars().case_fold().collect();
    matches!(
        folded.as_str(),
        "con" | "prn" | "aux" | "nul" | "clock$" | "conin$" | "conout$"
    ) || windows_numbered_device(&folded, "com")
        || windows_numbered_device(&folded, "lpt")
}

fn windows_numbered_device(value: &str, prefix: &str) -> bool {
    let Some(suffix) = value.strip_prefix(prefix) else {
        return false;
    };
    matches!(
        suffix,
        "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "¹" | "²" | "³"
    )
}

fn invalid(message: &str) -> ClientError {
    ClientError::InvalidTransfer(message.into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_portable_nested_paths() {
        assert_eq!(
            validate_generated_relative_path("2026/07/health.md").unwrap(),
            PathBuf::from("2026/07/health.md")
        );
        assert!(validate_generated_relative_path("health data/日記.md").is_ok());
    }

    #[test]
    fn rejects_traversal_separators_and_windows_aliases() {
        for value in [
            "",
            "/absolute.json",
            "../private.json",
            "folder/../private.json",
            "folder/./private.json",
            "folder//private.json",
            "folder/",
            "folder\\private.json",
            "daily.md:secret",
            "bad<name>.json",
            "bad>name.json",
            "bad\"name.json",
            "bad|name.json",
            "bad?name.json",
            "bad*name.json",
            "bad\u{0001}name.json",
            "trailing./daily.json",
            "trailing /daily.json",
            "CON",
            "con.json",
            "PRN.md",
            "AUX.txt",
            "NUL.json",
            "CLOCK$.json",
            "CONIN$.txt",
            "CONOUT$.txt",
            "COM0.json",
            "com1.log",
            "COM¹.md",
            "LPT0.json",
            "lpt9.log",
            "LPT³.md",
        ] {
            assert!(
                validate_generated_relative_path(value).is_err(),
                "unexpectedly accepted {value:?}"
            );
        }
    }

    #[test]
    fn detects_case_unicode_and_ancestor_collisions() {
        assert!(generated_paths_conflict("Café.md", "CAFE\u{301}.MD"));
        assert!(generated_paths_conflict("Straße.md", "STRASSE.MD"));
        assert!(generated_paths_conflict("daily", "DAILY/2026-07-31.md"));
        assert!(generated_paths_conflict("daily/2026.md", "DAILY"));
        assert!(!generated_paths_conflict("daily-a.md", "daily-b.md"));
    }
}
