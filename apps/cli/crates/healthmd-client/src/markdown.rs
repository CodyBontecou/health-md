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
            if placed.insert(section.name.clone()) {
                output.push_str(&replacement.heading);
                output.push_str(&replacement.body);
            } else {
                output.push_str(&section.heading);
                output.push_str(&section.body);
            }
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

/// A personal-note update must never acquire the role of a complete source export.
/// This runs before building an installable stage; errors contain no note content.
pub(crate) fn validate_personal_note_destination(existing: &str) -> Result<(), &'static str> {
    let mut lines = existing.lines();
    if lines
        .next()
        .is_none_or(|line| line.trim_start_matches('\u{feff}').trim() != "---")
    {
        return Ok(());
    }
    let mut schema_seen = false;
    let mut root_indentation = None;
    for line in lines {
        if line.trim() == "---" {
            return Ok(());
        }
        if line.trim().is_empty() || line.trim_start().starts_with('#') {
            continue;
        }
        let indentation = line.bytes().take_while(|byte| *byte == b' ').count();
        let root = *root_indentation.get_or_insert(indentation);
        if indentation < root {
            return Err("ambiguous daily note frontmatter");
        }
        if indentation > root {
            continue;
        }
        let line = &line[indentation..];
        if line.starts_with("- ") {
            continue;
        }
        let (key, value) = note_property(line).ok_or("ambiguous daily note frontmatter")?;
        if key == "<<" || key.starts_with(['*', '&', '?', '!', '{', '[']) {
            return Err("ambiguous daily note frontmatter");
        }
        if key != "schema" {
            continue;
        }
        if schema_seen {
            return Err("ambiguous daily note schema");
        }
        schema_seen = true;
        let value = note_scalar(value).ok_or("ambiguous daily note schema")?;
        if matches!(
            value.as_str(),
            "healthmd.health_data" | "healthmd.health_rollup"
        ) {
            return Err("daily note destination declares a complete export schema");
        }
    }
    Err("unterminated daily note frontmatter")
}

fn note_property(line: &str) -> Option<(String, &str)> {
    if line.starts_with(['\"', '\'']) {
        let (key, rest) = quoted_note_scalar(line)?;
        return Some((key, rest.trim_start().strip_prefix(':')?.trim()));
    }
    let (key, value) = line.split_once(':')?;
    Some((key.trim().into(), value.trim()))
}

fn note_scalar(value: &str) -> Option<String> {
    if value.starts_with(['\"', '\'']) {
        let (scalar, rest) = quoted_note_scalar(value)?;
        return (rest.trim().is_empty() || rest.trim_start().starts_with('#')).then_some(scalar);
    }
    if value.is_empty() || value.starts_with(['*', '&', '?', '!', '|', '>', '{', '[']) {
        return None;
    }
    let comment = value.char_indices().find_map(|(index, character)| {
        (character == '#' && value[..index].ends_with(char::is_whitespace)).then_some(index)
    });
    Some(value[..comment.unwrap_or(value.len())].trim().into())
}

fn quoted_note_scalar(value: &str) -> Option<(String, &str)> {
    if value.starts_with('\"') {
        let mut stream = serde_json::Deserializer::from_str(value).into_iter::<String>();
        let scalar = stream.next()?.ok()?;
        return Some((scalar, &value[stream.byte_offset()..]));
    }
    let mut scalar = String::new();
    let mut characters = value.char_indices().skip(1).peekable();
    while let Some((index, character)) = characters.next() {
        if character == '\'' {
            if characters.peek().is_some_and(|(_, next)| *next == '\'') {
                scalar.push('\'');
                characters.next();
            } else {
                return Some((scalar, &value[index + 1..]));
            }
        } else {
            scalar.push(character);
        }
    }
    None
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
    for (key, value) in existing_properties.into_iter().chain(new_properties) {
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
    #[test]
    fn personal_note_role_validation_preserves_valid_journal_shapes() {
        for existing in [
            "Personal introduction.\r\n",
            "---\r\nnotes: |\r\n  schema: healthmd.health_data\r\n---\r\nText.",
            "---\n\"schema\": \"journal\" # own role\n---\nText.",
            "---\n'schema': 'personal journal'\n---\nText.",
            "---\ntags:\n- journal\n- personal\n---\nText.",
            "---\n  schema: journal\n  title: Personal\n---\n",
            "---\n\"personal:key\": value\n---\nText.",
        ] {
            assert_eq!(
                validate_personal_note_destination(existing),
                Ok(()),
                "{existing}"
            );
        }
    }

    #[test]
    fn personal_note_role_validation_rejects_ambiguous_authority() {
        for existing in [
            "---\nschema: healthmd.health_data\n",
            "---\nschema: &role healthmd.health_data\n---\n",
            "---\n  schema: healthmd.health_data\n---\n",
            "\u{feff}---\nschema: healthmd.health_data\n---\n",
            "---\nschema: healthmd.health_data\t# complete\n---\n",
            "---\nschema: journal\nschema: other\n---\n",
            "---\n<<: *export\n---\n",
            "---\n? schema\n: healthmd.health_data\n---\n",
            "---\n{schema: healthmd.health_data}\n---\n",
            "---\n\"sche\\u006da\": healthmd.health_data\n---\n",
        ] {
            assert!(
                validate_personal_note_destination(existing).is_err(),
                "{existing}"
            );
        }
    }

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
    fn duplicate_existing_headings_do_not_duplicate_the_replacement() {
        let existing = "## Sleep\nold one\n## Sleep\nold two\n";
        let new = "## Sleep\nreplacement\n";
        let merged = merge(existing, new, false);
        assert_eq!(merged.matches("replacement").count(), 1);
        assert!(merged.contains("old two"));
        assert!(merged.len() <= existing.len() + new.len());
    }

    #[test]
    fn preserving_preamble_keeps_user_title() {
        let existing = "# My title\nintro\n## Sleep\nold\n";
        let new = "# Generated\n## Sleep\nnew\n";
        assert!(merge(existing, new, true).starts_with("# My title\nintro\n"));
    }
}
