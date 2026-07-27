//! Profile-exact managed Markdown merge behavior.

use std::collections::{HashMap, HashSet};

use super::RenderError;
use crate::semantic::SemanticProfile;

const MAX_MERGE_BYTES: usize = 8 * 1024 * 1024;

/// Merge one generated Markdown document using the deployed profile behavior.
///
/// Apple daily-note injection sets `preserve_preamble`; ordinary Apple update and Android ignore
/// it according to their shipped contracts.
///
/// # Errors
/// Returns a stable artifact-size error for oversized or NUL-containing documents.
pub fn merge_profile_markdown(
    profile: SemanticProfile,
    existing: &str,
    generated: &str,
    preserve_preamble: bool,
) -> Result<String, RenderError> {
    validate(existing, generated)?;
    Ok(match profile {
        SemanticProfile::AppleHealthDataV7 => apple_merge(existing, generated, preserve_preamble),
        SemanticProfile::AndroidFrozenV4 | SemanticProfile::AndroidAnalyticalV5 => {
            android_merge(existing, generated)
        }
    })
}

fn validate(existing: &str, generated: &str) -> Result<(), RenderError> {
    if existing.len() > MAX_MERGE_BYTES
        || generated.len() > MAX_MERGE_BYTES
        || existing.contains('\0')
        || generated.contains('\0')
    {
        return Err(RenderError::ArtifactTooLarge);
    }
    Ok(())
}

#[derive(Clone)]
struct AppleSection {
    heading: String,
    name: String,
    body: String,
}

struct AppleDocument {
    frontmatter: String,
    preamble: String,
    sections: Vec<AppleSection>,
}

fn apple_merge(existing: &str, generated: &str, preserve_preamble: bool) -> String {
    let existing = apple_parse(existing, apple_section_level(existing));
    let generated = apple_parse(generated, apple_section_level(generated));
    let mut generated_by_name = HashMap::new();
    let mut generated_order = Vec::new();
    for section in &generated.sections {
        generated_by_name.insert(section.name.clone(), section.clone());
        if !generated_order.contains(&section.name) {
            generated_order.push(section.name.clone());
        }
    }
    let mut output = apple_merge_frontmatter(&existing.frontmatter, &generated.frontmatter);
    output.push_str(if preserve_preamble {
        &existing.preamble
    } else {
        &generated.preamble
    });
    let mut placed = HashSet::new();
    for section in existing.sections {
        if let Some(replacement) = generated_by_name.get(&section.name) {
            output.push_str(&replacement.heading);
            output.push_str(&replacement.body);
            placed.insert(section.name);
        } else {
            output.push_str(&section.heading);
            output.push_str(&section.body);
        }
    }
    for name in generated_order {
        if !placed.contains(&name) {
            if let Some(section) = generated_by_name.get(&name) {
                output.push_str(&section.heading);
                output.push_str(&section.body);
            }
        }
    }
    output
}

fn apple_parse(content: &str, section_level: usize) -> AppleDocument {
    let lines = content.split('\n').collect::<Vec<_>>();
    let mut frontmatter = String::new();
    let mut start = 0;
    if lines.first().is_some_and(|line| line.trim() == "---") {
        if let Some(index) = lines
            .iter()
            .enumerate()
            .skip(1)
            .find_map(|(index, line)| (line.trim() == "---").then_some(index))
        {
            frontmatter = format!("{}\n", lines[..=index].join("\n"));
            start = index + 1;
        }
    }
    let mut preamble = String::new();
    let mut sections = Vec::new();
    let mut heading: Option<String> = None;
    let mut name: Option<String> = None;
    let mut body = Vec::new();
    for line in &lines[start..] {
        if apple_heading_level(line) == section_level {
            if let (Some(heading), Some(name)) = (heading.take(), name.take()) {
                sections.push(AppleSection {
                    heading,
                    name,
                    body: lines_with_newlines(&body),
                });
                body.clear();
            }
            heading = Some(format!("{line}\n"));
            name = Some(apple_heading_name(line));
        } else if heading.is_none() {
            preamble.push_str(line);
            preamble.push('\n');
        } else {
            body.push(*line);
        }
    }
    if let (Some(heading), Some(name)) = (heading, name) {
        sections.push(AppleSection {
            heading,
            name,
            body: lines_with_newlines(&body),
        });
    }
    AppleDocument {
        frontmatter,
        preamble,
        sections,
    }
}

fn lines_with_newlines(lines: &[&str]) -> String {
    let mut output = String::new();
    for line in lines {
        output.push_str(line);
        output.push('\n');
    }
    output
}

fn apple_heading_level(line: &str) -> usize {
    let line = line.trim();
    let level = line.bytes().take_while(|byte| *byte == b'#').count();
    if level == 0 || level >= line.len() || line.as_bytes()[level] != b' ' {
        0
    } else {
        level
    }
}

fn apple_heading_name(line: &str) -> String {
    line.trim_start_matches(['#', ' '])
        .chars()
        .filter(|character| character.is_ascii_alphanumeric() || *character == ' ')
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_ascii_lowercase()
}

fn apple_section_level(content: &str) -> usize {
    const MANAGED: &[&str] = &[
        "sleep",
        "activity",
        "heart",
        "vitals",
        "body",
        "nutrition",
        "mindfulness",
        "mobility",
        "hearing",
        "workouts",
        "medications",
    ];
    for line in content.split('\n') {
        let level = apple_heading_level(line);
        if level > 0 && MANAGED.contains(&apple_heading_name(line).as_str()) {
            return level;
        }
    }
    2
}

fn apple_merge_frontmatter(existing: &str, generated: &str) -> String {
    let existing_values = apple_frontmatter_properties(existing);
    let generated_values = apple_frontmatter_properties(generated);
    if existing_values.is_empty() && generated_values.is_empty() {
        return String::new();
    }
    if existing_values.is_empty() {
        return generated.to_owned();
    }
    if generated_values.is_empty() {
        return existing.to_owned();
    }
    let mut order = Vec::new();
    let mut values = HashMap::new();
    for (key, value) in existing_values.into_iter().chain(generated_values) {
        if !order.contains(&key) {
            order.push(key.clone());
        }
        values.insert(key, value);
    }
    let mut output = String::from("---\n");
    for key in order {
        if let Some(value) = values.get(&key) {
            output.push_str(&apple_frontmatter_property(&key, value));
        }
    }
    output.push_str("---\n");
    output
}

fn apple_frontmatter_properties(frontmatter: &str) -> Vec<(String, String)> {
    let mut properties = Vec::new();
    let mut current_key: Option<String> = None;
    let mut current_value = String::new();
    let mut multiline = false;
    for line in frontmatter.split('\n') {
        let trimmed = line.trim();
        if trimmed == "---" {
            continue;
        }
        if trimmed.is_empty() && !multiline {
            continue;
        }
        if let Some(colon) = line
            .find(':')
            .filter(|_| !multiline || !line.starts_with(' '))
        {
            if let Some(key) = current_key.take() {
                properties.push((key, current_value.trim_matches('\n').to_owned()));
            }
            let key = line[..colon].trim().to_owned();
            let value = line[colon + 1..].trim().to_owned();
            multiline = value.is_empty()
                || value == "|"
                || value == ">"
                || value.starts_with('[') && !value.ends_with(']');
            current_key = Some(key);
            current_value = value;
        } else if multiline && current_key.is_some() {
            if !current_value.is_empty() {
                current_value.push('\n');
            }
            current_value.push_str(line);
            if current_value.starts_with('[') && line.contains(']') {
                multiline = false;
            }
        }
    }
    if let Some(key) = current_key {
        properties.push((key, current_value.trim_matches('\n').to_owned()));
    }
    properties
}

fn apple_frontmatter_property(key: &str, value: &str) -> String {
    if !value.contains('\n') {
        return format!("{key}: {value}\n");
    }
    let mut lines = value.split('\n');
    let first = lines.next().unwrap_or_default();
    if matches!(first, "|" | ">") {
        format!("{key}: {first}\n{}\n", lines.collect::<Vec<_>>().join("\n"))
    } else {
        format!("{key}:\n{value}\n")
    }
}

#[derive(Clone)]
struct AndroidSection {
    heading: String,
    content: String,
}

struct AndroidBody {
    preamble: String,
    sections: Vec<AndroidSection>,
}

fn android_merge(existing: &str, generated: &str) -> String {
    if existing.trim().is_empty() {
        return generated.to_owned();
    }
    let (existing_front, existing_body) = android_split_frontmatter(existing);
    let (generated_front, generated_body) = android_split_frontmatter(generated);
    let frontmatter = android_merge_frontmatter(existing_front, generated_front);
    let body = android_merge_body(existing_body, generated_body);
    let mut output = String::new();
    if !frontmatter.trim().is_empty() {
        output.push_str("---\n");
        output.push_str(frontmatter.trim_end());
        output.push_str("\n---\n\n");
    }
    output.push_str(body.trim_end());
    output.push('\n');
    output
}

fn android_split_frontmatter(content: &str) -> (&str, &str) {
    if !content.starts_with("---") {
        return ("", content);
    }
    let Some(first_end) = content.find('\n') else {
        return ("", content);
    };
    let Some(relative_close) = content[first_end + 1..].find("\n---") else {
        return ("", content);
    };
    let close = first_end + 1 + relative_close;
    let close_end = content[close + 4..]
        .find('\n')
        .map_or(content.len(), |index| close + 4 + index + 1);
    (&content[first_end + 1..close], &content[close_end..])
}

fn android_frontmatter_map(value: &str) -> Vec<(String, String)> {
    let mut result = Vec::new();
    for line in value.split('\n') {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some(index) = line.find(':').filter(|index| *index > 0) {
            let key = line[..index].trim().to_owned();
            let value = line[index + 1..].trim().to_owned();
            if let Some(existing) = result
                .iter_mut()
                .find(|entry: &&mut (String, String)| entry.0 == key)
            {
                existing.1 = value;
            } else {
                result.push((key, value));
            }
        }
    }
    result
}

fn android_merge_frontmatter(existing: &str, generated: &str) -> String {
    let mut merged = android_frontmatter_map(existing);
    for (key, value) in android_frontmatter_map(generated) {
        if let Some(existing) = merged.iter_mut().find(|entry| entry.0 == key) {
            existing.1 = value;
        } else {
            merged.push((key, value));
        }
    }
    merged
        .into_iter()
        .map(|(key, value)| {
            if value.is_empty() {
                format!("{key}:")
            } else {
                format!("{key}: {value}")
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn android_parse_body(body: &str) -> AndroidBody {
    let mut preamble = String::new();
    let mut sections = Vec::new();
    let mut heading: Option<String> = None;
    let mut content = String::new();
    for line in body.split('\n') {
        if is_markdown_heading(line) {
            if let Some(previous) = heading.replace(line.to_owned()) {
                sections.push(AndroidSection {
                    heading: previous,
                    content: std::mem::take(&mut content),
                });
            }
        } else if heading.is_none() {
            preamble.push_str(line);
            preamble.push('\n');
        } else {
            content.push_str(line);
            content.push('\n');
        }
    }
    if let Some(heading) = heading {
        sections.push(AndroidSection { heading, content });
    }
    AndroidBody { preamble, sections }
}

fn is_markdown_heading(line: &str) -> bool {
    let hashes = line.bytes().take_while(|byte| *byte == b'#').count();
    (1..=6).contains(&hashes) && line.as_bytes().get(hashes) == Some(&b' ')
}

fn android_managed_key(heading: &str) -> Option<String> {
    const MANAGED: &[&str] = &[
        "sleep",
        "activity",
        "heart",
        "vitals",
        "body",
        "nutrition",
        "mobility",
        "reproductive health",
        "mindfulness",
        "workouts",
    ];
    let normalized = heading
        .to_ascii_lowercase()
        .chars()
        .filter(|character| !matches!(character, '#' | '*' | '_' | '~' | '`'))
        .map(|character| {
            if character.is_ascii_alphanumeric() || character == ' ' {
                character
            } else {
                ' '
            }
        })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    if normalized.starts_with("health data") {
        Some("health data".to_owned())
    } else {
        MANAGED.contains(&normalized.as_str()).then_some(normalized)
    }
}

fn android_merge_body(existing: &str, generated: &str) -> String {
    let existing = android_parse_body(existing);
    let generated = android_parse_body(generated);
    if generated.sections.is_empty() {
        return existing.preamble;
    }
    if existing.sections.is_empty() {
        let mut output = generated.preamble;
        for section in generated.sections {
            output.push_str(&section.heading);
            output.push('\n');
            output.push_str(&section.content);
        }
        return output;
    }
    let mut replacements: Vec<(String, AndroidSection)> = Vec::new();
    for section in generated.sections {
        if let Some(key) = android_managed_key(&section.heading) {
            if let Some(existing) = replacements.iter_mut().find(|entry| entry.0 == key) {
                existing.1 = section;
            } else {
                replacements.push((key, section));
            }
        }
    }
    let mut merged = Vec::new();
    for section in existing.sections {
        let replacement = android_managed_key(&section.heading)
            .and_then(|key| replacements.iter().position(|entry| entry.0 == key))
            .map(|index| replacements.remove(index).1);
        merged.push(replacement.unwrap_or(section));
    }
    merged.extend(replacements.into_iter().map(|entry| entry.1));
    let mut output = String::new();
    if !existing.preamble.trim().is_empty() {
        output.push_str(existing.preamble.trim_end());
        output.push_str("\n\n");
    } else if !generated.preamble.trim().is_empty() {
        output.push_str(generated.preamble.trim_end());
        output.push_str("\n\n");
    }
    for (index, section) in merged.into_iter().enumerate() {
        if index > 0 {
            output.push('\n');
        }
        output.push_str(section.heading.trim_end());
        output.push('\n');
        output.push_str(section.content.trim_end());
        output.push('\n');
    }
    output
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn apple_and_android_keep_their_distinct_preamble_contracts() {
        let existing =
            "---\ndate: old\nuser: keep\n---\n# User title\n\n## Sleep\nold\n## Notes\nkeep\n";
        let generated =
            "---\ndate: new\n---\n# Health Data — new\n\n## Sleep\nnew\n## Activity\nsteps\n";
        let apple = merge_profile_markdown(
            SemanticProfile::AppleHealthDataV7,
            existing,
            generated,
            false,
        )
        .unwrap();
        assert!(apple.contains("# Health Data — new"));
        assert!(!apple.contains("# User title"));
        assert!(apple.contains("## Notes\nkeep"));
        let android =
            merge_profile_markdown(SemanticProfile::AndroidFrozenV4, existing, generated, false)
                .unwrap();
        assert!(android.contains("# User title"));
        assert!(android.contains("# Health Data — new"));
        assert!(android.contains("## Notes\nkeep"));
    }
}
