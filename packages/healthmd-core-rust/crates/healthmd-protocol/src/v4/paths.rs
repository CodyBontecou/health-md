use super::semantics::scalars::civil;
use super::{Dates, Error, ExportIntent, OutputSettings, RelativePath, ensure, shape};
use chrono::{Datelike as _, Duration};
use std::collections::BTreeSet;

/// Lexical POSIX-relative validation only. No root/handle/symlink authority is claimed.
/// Without new Unicode dependencies this increment fails closed on non-ASCII paths
/// rather than pretending ASCII lowercase proves full NFC/casefold collision safety.
/// # Errors
/// Returns fixed lexical/unsupported errors; never normalizes an approved target.
pub fn validate_relative_path(path: &str, filename: bool, tokens: &[&str]) -> Result<(), Error> {
    let safe = || Err(Error::UnsafePath);
    if path.len() > 4096
        || path.chars().any(char::is_control)
        || path.starts_with(['/', '~'])
        || path.contains(['\\', ':', '%'])
    {
        return safe();
    }
    if path.is_empty() {
        return if filename { safe() } else { Ok(()) };
    }
    if filename && path.contains('/') {
        return safe();
    }
    let parts: Vec<_> = path.split('/').collect();
    if parts.len() > 16 {
        return safe();
    }
    for part in parts {
        if part.is_empty()
            || part == "."
            || part == ".."
            || part != part.trim()
            || part.ends_with('.')
            || part.len() > 255
            || part.contains(['<', '>', '"', '|', '?', '*'])
        {
            return safe();
        }
        let mut literal = String::new();
        let mut rest = part;
        while let Some(start) = rest.find('{') {
            literal.push_str(&rest[..start]);
            rest = &rest[start + 1..];
            let Some(end) = rest.find('}') else {
                return safe();
            };
            if !tokens.contains(&&rest[..end]) {
                return safe();
            }
            literal.push('x');
            rest = &rest[end + 1..];
        }
        literal.push_str(rest);
        if literal.contains(['{', '}']) {
            return safe();
        }
        let base = literal
            .split('.')
            .next()
            .unwrap_or_default()
            .to_ascii_lowercase();
        if ["con", "prn", "aux", "nul"].contains(&base.as_str())
            || (base.len() == 4
                && (base.starts_with("com") || base.starts_with("lpt"))
                && matches!(base.as_bytes()[3], b'1'..=b'9'))
        {
            return safe();
        }
    }
    ensure(path.is_ascii(), Error::UnsupportedCapability)
}

/// ASCII collision subset, fail-closed for Unicode; filesystem races remain native.
/// # Errors
/// Rejects lexical errors, aliases and unsupported non-ASCII targets.
pub fn validate_path_collisions(paths: &[RelativePath]) -> Result<(), Error> {
    let mut aliases = BTreeSet::new();
    for path in paths {
        validate_relative_path(&path.0, false, &[])?;
        ensure(!path.0.is_empty(), Error::UnsafePath)?;
        ensure(
            aliases.insert(path.0.to_ascii_lowercase()),
            Error::PathCollision,
        )?;
    }
    Ok(())
}

pub(crate) const DAILY_TOKENS: &[&str] = &["year", "month", "day", "date"];
pub(crate) const ENTRY_TOKENS: &[&str] = &[
    "year",
    "month",
    "day",
    "date",
    "metric",
    "category",
    "record_id",
];

/// Predict configuration-only generated-file paths. Logical history remains unresolved.
/// # Errors
/// Rejects overflow/collisions/unsupported path dialects; performs no health reads.
pub fn predicted_paths(
    intent: &ExportIntent,
    settings: &OutputSettings,
) -> Result<Vec<RelativePath>, Error> {
    use super::{
        Dictionary, DictionaryProfileDictionaryV1Format as DictionaryFormat,
        OutputSettingsFormatsItem as Format, Packaging,
    };
    let dates = super::resolve_dates(&intent.dates)?;
    let Dates::Exact { range } = dates else {
        return Ok(Vec::new());
    };
    let start = civil(&range.start_date.0)?;
    let end = civil(&range.end_date.0)?;
    let days = (end - start).num_days() + 1;
    ensure(
        days > 0
            && days <= 4096
            && u64::try_from(days).map_err(|_| Error::InvalidRequest)?
                * settings.formats.len() as u64
                <= 4096,
        Error::QueryBudgetExceeded,
    )?;
    let mut paths = Vec::new();
    for offset in 0..days {
        let day = start
            .checked_add_signed(Duration::days(offset))
            .ok_or(Error::InvalidRequest)?;
        let parent = [
            expand(&settings.subfolder.0, day),
            expand(&settings.folder_template.0, day),
        ]
        .into_iter()
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join("/");
        let base = expand(&settings.filename_template.0, day);
        if !settings.daily_notes.only {
            for format in &settings.formats {
                let extension = match format {
                    Format::Json => "json",
                    Format::Csv => "csv",
                    Format::Markdown | Format::ObsidianBases => "md",
                };
                let suffix = if *format == Format::ObsidianBases
                    && settings.formats.contains(&Format::Markdown)
                {
                    "-bases"
                } else {
                    ""
                };
                paths.push(RelativePath(join(
                    &parent,
                    &format!("{base}{suffix}.{extension}"),
                )));
            }
        }
        let notes = &settings.daily_notes;
        if notes.enabled {
            paths.push(RelativePath(join(
                &expand(&notes.folder_template.0, day),
                &(expand(&notes.filename_template.0, day) + ".md"),
            )));
        }
    }
    let root = expand(&settings.subfolder.0, end);
    if let Dictionary::ProfileDictionaryV1 {
        filename_template,
        format,
    } = &settings.dictionary
    {
        let ext = if *format == DictionaryFormat::Json {
            ".json"
        } else {
            ".md"
        };
        paths.push(RelativePath(join(
            &root,
            &(expand(&filename_template.0, end) + ext),
        )));
    }
    validate_path_collisions(&paths)?;
    if let Packaging::Zip {
        filename_template,
        include_loose_files,
        max_entries,
        ..
    } = &settings.packaging
    {
        ensure(
            paths.len() as u64 <= *max_entries,
            Error::QueryBudgetExceeded,
        )?;
        let archive = RelativePath(join(&root, &(expand(&filename_template.0, end) + ".zip")));
        paths.push(archive.clone());
        validate_path_collisions(&paths)?;
        if !include_loose_files {
            paths = vec![archive];
        }
    }
    shape(paths.len() <= 4096)?;
    paths.sort();
    Ok(paths)
}
fn expand(template: &str, date: chrono::NaiveDate) -> String {
    template
        .replace("{year}", &format!("{:04}", date.year()))
        .replace("{month}", &format!("{:02}", date.month()))
        .replace("{day}", &format!("{:02}", date.day()))
        .replace("{date}", &date.to_string())
}
fn join(parent: &str, name: &str) -> String {
    if parent.is_empty() {
        name.to_owned()
    } else {
        format!("{parent}/{name}")
    }
}
