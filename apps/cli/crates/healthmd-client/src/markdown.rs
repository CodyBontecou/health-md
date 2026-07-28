//! Section-aware Markdown merge compatible with Health.md's generated-file update modes.

use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone, Debug, Eq, PartialEq)]
struct Section {
    heading: String,
    name: String,
    body: String,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
struct Document {
    frontmatter: String,
    preamble: String,
    sections: Vec<Section>,
}

#[must_use]
pub fn merge(existing: &str, new: &str, preserve_preamble: bool) -> String {
    let existing = parse(existing, detect_section_level(existing));
    let new = parse(new, detect_section_level(new));
    let mut new_sections = BTreeMap::new();
    let mut new_order = Vec::new();
    for section in new.sections {
        if !new_order.contains(&section.name) {
            new_order.push(section.name.clone());
        }
        new_sections.insert(section.name.clone(), section);
    }
    let mut output = merge_frontmatter(&existing.frontmatter, &new.frontmatter);
    output.push_str(if preserve_preamble {
        &existing.preamble
    } else {
        &new.preamble
    });
    let mut placed = BTreeSet::new();
    for section in existing.sections {
        if let Some(replacement) = new_sections.get(&section.name) {
            output.push_str(&replacement.heading);
            output.push_str(&replacement.body);
            placed.insert(section.name);
        } else {
            output.push_str(&section.heading);
            output.push_str(&section.body);
        }
    }
    for name in new_order {
        if !placed.contains(&name) {
            if let Some(section) = new_sections.get(&name) {
                output.push_str(&section.heading);
                output.push_str(&section.body);
            }
        }
    }
    output
}

fn merge_frontmatter(existing: &str, new: &str) -> String {
    use std::fmt::Write as _;

    let existing_properties = frontmatter_properties(existing);
    let new_properties = frontmatter_properties(new);
    if existing_properties.is_empty() {
        return new.into();
    }
    if new_properties.is_empty() {
        return existing.into();
    }
    let mut order = Vec::new();
    let mut values = BTreeMap::new();
    for (key, value) in existing_properties
        .into_iter()
        .chain(new_properties.into_iter())
    {
        if !values.contains_key(&key) {
            order.push(key.clone());
        }
        values.insert(key, value);
    }
    let mut output = String::from("---\n");
    for key in order {
        let value = values.get(&key).expect("ordered key has a value");
        if !value.contains('\n') {
            writeln!(output, "{key}: {value}").expect("writing to a string succeeds");
        } else if value.starts_with("|\n") || value.starts_with(">\n") {
            let (marker, rest) = value.split_at(1);
            writeln!(output, "{key}: {marker}\n{}", rest.trim_start_matches('\n'))
                .expect("writing to a string succeeds");
        } else {
            writeln!(output, "{key}:\n{value}").expect("writing to a string succeeds");
        }
    }
    output.push_str("---\n");
    output
}

fn frontmatter_properties(frontmatter: &str) -> Vec<(String, String)> {
    let mut properties = Vec::new();
    let mut current_key: Option<String> = None;
    let mut current_value = String::new();
    let mut multiline = false;
    for line in frontmatter.lines() {
        let trimmed = line.trim();
        if trimmed == "---" || (trimmed.is_empty() && !multiline) {
            continue;
        }
        if let Some(colon) = line
            .find(':')
            .filter(|_| !multiline || !line.starts_with(' '))
        {
            if let Some(key) = current_key.take() {
                properties.push((key, current_value.trim_matches('\n').into()));
            }
            current_key = Some(line[..colon].trim().into());
            current_value = line[colon + 1..].trim().into();
            multiline = current_value.is_empty()
                || current_value == "|"
                || current_value == ">"
                || (current_value.starts_with('[') && !current_value.ends_with(']'));
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
        properties.push((key, current_value.trim_matches('\n').into()));
    }
    properties
}

fn parse(content: &str, section_level: usize) -> Document {
    let lines: Vec<_> = content.split('\n').collect();
    let mut document = Document::default();
    let mut start = 0;
    if lines.first().is_some_and(|line| line.trim() == "---") {
        if let Some(end) = lines
            .iter()
            .enumerate()
            .skip(1)
            .find_map(|(index, line)| (line.trim() == "---").then_some(index))
        {
            document.frontmatter = format!("{}\n", lines[..=end].join("\n"));
            start = end + 1;
        }
    }
    let mut current: Option<Section> = None;
    for line in &lines[start..] {
        if heading_level(line) == section_level {
            if let Some(section) = current.take() {
                document.sections.push(section);
            }
            current = Some(Section {
                heading: format!("{line}\n"),
                name: normalize_heading(line),
                body: String::new(),
            });
        } else if let Some(section) = current.as_mut() {
            section.body.push_str(line);
            section.body.push('\n');
        } else {
            document.preamble.push_str(line);
            document.preamble.push('\n');
        }
    }
    if let Some(section) = current {
        document.sections.push(section);
    }
    document
}

fn heading_level(line: &str) -> usize {
    let trimmed = line.trim_start();
    let level = trimmed.bytes().take_while(|byte| *byte == b'#').count();
    if level > 0 && trimmed.as_bytes().get(level) == Some(&b' ') {
        level
    } else {
        0
    }
}

fn normalize_heading(heading: &str) -> String {
    heading
        .trim_start_matches(['#', ' '])
        .chars()
        .filter(|character| character.is_ascii_alphanumeric() || *character == ' ')
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
}

fn detect_section_level(content: &str) -> usize {
    const KNOWN: &[&str] = &[
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
    content
        .lines()
        .find_map(|line| {
            let level = heading_level(line);
            (level > 0 && KNOWN.contains(&normalize_heading(line).as_str())).then_some(level)
        })
        .unwrap_or(2)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn managed_sections_update_and_user_sections_survive() {
        let existing = "---\nnote: mine\nsteps: 1\n---\n# Day\n## Sleep\nold\n## My Notes\nkeep\n";
        let new =
            "---\nsteps: 2\nsource: healthmd\n---\n# Fresh\n## Sleep\nnew\n## Activity\nactive\n";
        let merged = merge(existing, new, false);
        assert!(merged.contains("note: mine"));
        assert!(merged.contains("steps: 2"));
        assert!(merged.contains("## Sleep\nnew"));
        assert!(merged.contains("## My Notes\nkeep"));
        assert!(merged.contains("## Activity\nactive"));
        assert!(!merged.contains("old"));
    }

    #[test]
    fn preserving_preamble_keeps_user_title() {
        let existing = "# My title\nintro\n## Sleep\nold\n";
        let new = "# Generated\n## Sleep\nnew\n";
        assert!(merge(existing, new, true).starts_with("# My title\nintro\n"));
    }
}
