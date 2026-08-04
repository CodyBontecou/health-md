//! Profile-exact managed Markdown merge behavior.

use std::{
    collections::{HashMap, HashSet},
    ops::Range,
};

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
struct PhysicalLine {
    content: String,
    ending: &'static str,
}

impl PhysicalLine {
    fn append_to(&self, output: &mut String) {
        output.push_str(&self.content);
        output.push_str(self.ending);
    }
}

#[derive(Clone)]
struct FrontmatterPropertyBlock {
    key: String,
    range: Range<usize>,
}

struct FrontmatterDocument {
    opening: PhysicalLine,
    content: Vec<PhysicalLine>,
    closing: PhysicalLine,
    suffix: Vec<PhysicalLine>,
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
    let boundary_line_ending = first_line_ending(existing)
        .or_else(|| first_line_ending(generated))
        .unwrap_or("\n");
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
    let merged_frontmatter = apple_merge_frontmatter(&existing.frontmatter, &generated.frontmatter);
    let mut output = String::new();
    append_markdown_fragment(&mut output, &merged_frontmatter, boundary_line_ending);
    append_markdown_fragment(
        &mut output,
        if preserve_preamble {
            &existing.preamble
        } else {
            &generated.preamble
        },
        boundary_line_ending,
    );
    let mut placed = HashSet::new();
    for section in existing.sections {
        if let Some(replacement) = generated_by_name.get(&section.name) {
            append_markdown_fragment(&mut output, &replacement.heading, boundary_line_ending);
            append_markdown_fragment(&mut output, &replacement.body, boundary_line_ending);
            placed.insert(section.name);
        } else {
            append_markdown_fragment(&mut output, &section.heading, boundary_line_ending);
            append_markdown_fragment(&mut output, &section.body, boundary_line_ending);
        }
    }
    for name in generated_order {
        if !placed.contains(&name) {
            if let Some(section) = generated_by_name.get(&name) {
                append_markdown_fragment(&mut output, &section.heading, boundary_line_ending);
                append_markdown_fragment(&mut output, &section.body, boundary_line_ending);
            }
        }
    }
    output
}

fn append_markdown_fragment(output: &mut String, fragment: &str, line_ending: &str) {
    if fragment.is_empty() {
        return;
    }
    if !output.is_empty()
        && !matches!(output.as_bytes().last(), Some(b'\n' | b'\r'))
        && !matches!(fragment.as_bytes().first(), Some(b'\n' | b'\r'))
    {
        output.push_str(line_ending);
    }
    output.push_str(fragment);
}

fn first_line_ending(text: &str) -> Option<&'static str> {
    physical_lines(text)
        .into_iter()
        .find_map(|line| (!line.ending.is_empty()).then_some(line.ending))
}

fn apple_parse(content: &str, section_level: usize) -> AppleDocument {
    let (frontmatter, lines) = if let Some(document) = frontmatter_document(content) {
        let frontmatter = render_frontmatter_envelope(&document);
        (frontmatter, document.suffix)
    } else {
        (String::new(), physical_lines(content))
    };

    let mut preamble = String::new();
    let mut sections = Vec::new();
    let mut heading: Option<String> = None;
    let mut name: Option<String> = None;
    let mut body = String::new();

    for line in lines {
        if apple_heading_level(&line.content) == section_level {
            if let (Some(heading), Some(name)) = (heading.take(), name.take()) {
                sections.push(AppleSection {
                    heading,
                    name,
                    body: std::mem::take(&mut body),
                });
            }
            let mut raw = String::new();
            line.append_to(&mut raw);
            heading = Some(raw);
            name = Some(apple_heading_name(&line.content));
        } else if heading.is_none() {
            line.append_to(&mut preamble);
        } else {
            line.append_to(&mut body);
        }
    }

    if let (Some(heading), Some(name)) = (heading, name) {
        sections.push(AppleSection {
            heading,
            name,
            body,
        });
    }
    AppleDocument {
        frontmatter,
        preamble,
        sections,
    }
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
    let existing_document = frontmatter_document(existing);
    let generated_document = frontmatter_document(generated);

    let Some(existing_document) = existing_document else {
        return generated_document.map_or_else(String::new, |_| generated.to_owned());
    };
    let Some(generated_document) = generated_document else {
        return existing.to_owned();
    };

    let Some(incoming_blocks) = property_blocks(&generated_document.content) else {
        return existing.to_owned();
    };
    if incoming_blocks.is_empty() {
        return existing.to_owned();
    }

    let line_ending = preferred_line_ending(&existing_document);
    let mut incoming_order = Vec::new();
    let mut incoming_by_key: HashMap<String, Vec<PhysicalLine>> = HashMap::new();
    for block in incoming_blocks {
        if !incoming_by_key.contains_key(&block.key) {
            incoming_order.push(block.key.clone());
        }
        let lines = generated_document.content[block.range]
            .iter()
            .map(|line| PhysicalLine {
                content: line.content.clone(),
                ending: line_ending,
            })
            .collect();
        incoming_by_key.insert(block.key, lines);
    }

    let Some(existing_blocks) = property_blocks(&existing_document.content) else {
        // Unsupported or ambiguous YAML remains byte-for-byte intact rather than risking a
        // partial replacement that leaves continuations attached to the wrong property.
        return existing.to_owned();
    };
    let existing_by_start = existing_blocks
        .into_iter()
        .map(|block| (block.range.start, block))
        .collect::<HashMap<_, _>>();
    let mut merged = Vec::new();
    let mut emitted = HashSet::new();
    let mut index = 0;

    while index < existing_document.content.len() {
        let Some(block) = existing_by_start.get(&index) else {
            merged.push(existing_document.content[index].clone());
            index += 1;
            continue;
        };

        if let Some(replacement) = incoming_by_key.get(&block.key) {
            if emitted.insert(block.key.clone()) {
                merged.extend(replacement.iter().cloned());
            }
        } else {
            merged.extend(
                existing_document.content[block.range.clone()]
                    .iter()
                    .cloned(),
            );
        }
        index = block.range.end;
    }

    for key in incoming_order {
        if emitted.insert(key.clone()) {
            if let Some(lines) = incoming_by_key.get(&key) {
                merged.extend(lines.iter().cloned());
            }
        }
    }

    let mut output = String::new();
    existing_document.opening.append_to(&mut output);
    append_lines(&mut output, &merged);
    existing_document.closing.append_to(&mut output);
    append_lines(&mut output, &existing_document.suffix);
    output
}

fn frontmatter_document(text: &str) -> Option<FrontmatterDocument> {
    let lines = physical_lines(text);
    if lines.len() < 2 || !is_frontmatter_delimiter(&lines[0].content) {
        return None;
    }
    let closing_index = lines
        .iter()
        .enumerate()
        .skip(1)
        .find_map(|(index, line)| is_frontmatter_delimiter(&line.content).then_some(index))?;
    Some(FrontmatterDocument {
        opening: lines[0].clone(),
        content: lines[1..closing_index].to_vec(),
        closing: lines[closing_index].clone(),
        suffix: lines[closing_index + 1..].to_vec(),
    })
}

struct FrontmatterPropertyHeader {
    key: String,
    value: String,
}

struct BlockScalarHeader {
    indentation: Option<usize>,
    keeps_trailing_blank_lines: bool,
}

enum BlockScalarHeaderParse {
    NotBlockScalar,
    Header(BlockScalarHeader),
    Invalid,
}

/// Minimal YAML flow lexer used only to prove where a top-level property's physical block ends.
/// It deliberately rejects mismatched or trailing syntax instead of guessing ownership.
#[derive(Default)]
struct FlowCollectionState {
    expected_closers: Vec<u8>,
    quote: Option<u8>,
    escaped: bool,
}

impl FlowCollectionState {
    fn is_open(&self) -> bool {
        !self.expected_closers.is_empty()
    }

    fn scan(&mut self, text: &str) -> bool {
        let bytes = text.as_bytes();
        let mut index = 0;

        while index < bytes.len() {
            let byte = bytes[index];
            if self.quote == Some(b'"') {
                if self.escaped {
                    self.escaped = false;
                } else if byte == b'\\' {
                    self.escaped = true;
                } else if byte == b'"' {
                    self.quote = None;
                }
                index += 1;
                continue;
            }

            if self.quote == Some(b'\'') {
                if byte == b'\'' {
                    if bytes.get(index + 1) == Some(&b'\'') {
                        index += 2;
                        continue;
                    }
                    self.quote = None;
                }
                index += 1;
                continue;
            }

            if byte == b'#' {
                if index == 0 || matches!(bytes[index - 1], b' ' | b'\t' | b',' | b'[' | b'{') {
                    break;
                }
            } else if matches!(byte, b'"' | b'\'') {
                self.quote = Some(byte);
            } else if byte == b'[' {
                self.expected_closers.push(b']');
            } else if byte == b'{' {
                self.expected_closers.push(b'}');
            } else if matches!(byte, b']' | b'}') {
                if self.expected_closers.last() != Some(&byte) {
                    return false;
                }
                self.expected_closers.pop();
                if self.expected_closers.is_empty() {
                    let remainder = trim_horizontal(&text[index + 1..]);
                    return remainder.is_empty() || remainder.starts_with('#');
                }
            }
            index += 1;
        }

        // A backslash at the end of a double-quoted flow line escapes the physical line break,
        // not the first character on the continuation line.
        self.escaped = false;
        true
    }
}

/// Discover complete top-level property blocks. None means some non-trivia line could not be
/// assigned safely, so callers must preserve the original frontmatter unchanged.
fn property_blocks(lines: &[PhysicalLine]) -> Option<Vec<FrontmatterPropertyBlock>> {
    let mut blocks = Vec::new();
    let mut index = 0;

    while index < lines.len() {
        let line = &lines[index].content;
        if is_yaml_trivia(line) {
            index += 1;
            continue;
        }
        if is_indented(line) {
            return None;
        }
        let header = property_header(line)?;

        let end = match block_scalar_header(&header.value) {
            BlockScalarHeaderParse::Invalid => return None,
            BlockScalarHeaderParse::Header(scalar_header) => {
                block_scalar_end(lines, index + 1, &scalar_header)?
            }
            BlockScalarHeaderParse::NotBlockScalar => {
                let mut flow_state = FlowCollectionState::default();
                let initial_node = yaml_node(&header.value)?;
                if matches!(initial_node.as_bytes().first(), Some(b'[' | b'{'))
                    && !flow_state.scan(initial_node)
                {
                    return None;
                }

                let mut continuation_end = index + 1;
                while continuation_end < lines.len() {
                    let continuation = &lines[continuation_end].content;

                    if flow_state.is_open() {
                        if !flow_state.scan(continuation) {
                            return None;
                        }
                        continuation_end += 1;
                        continue;
                    }

                    if is_indented(continuation) && !is_yaml_trivia(continuation) {
                        if let Some(node) = flow_collection_node(continuation) {
                            if !flow_state.scan(&node) {
                                return None;
                            }
                        }
                        continuation_end += 1;
                        continue;
                    }

                    if is_yaml_trivia(continuation) {
                        // Column-zero comments and blank lines can interrupt an indented mapping/list.
                        // Attach them only when another indented, non-trivia continuation follows.
                        let mut next_content = continuation_end + 1;
                        while next_content < lines.len()
                            && is_yaml_trivia(&lines[next_content].content)
                        {
                            next_content += 1;
                        }
                        if next_content < lines.len() && is_indented(&lines[next_content].content) {
                            continuation_end = next_content;
                            continue;
                        }
                        break;
                    }

                    if property_header(continuation).is_some() {
                        break;
                    }

                    // A column-zero closer, explicit complex key, directive, or other unsupported
                    // construct has ambiguous ownership. Preserve instead of emitting partial YAML.
                    return None;
                }

                if flow_state.is_open() {
                    return None;
                }
                continuation_end
            }
        };

        blocks.push(FrontmatterPropertyBlock {
            key: header.key,
            range: index..end,
        });
        index = end;
    }
    Some(blocks)
}

fn property_header(line: &str) -> Option<FrontmatterPropertyHeader> {
    let first = line.chars().next()?;
    if first.is_whitespace()
        || line.starts_with('#')
        || line.starts_with('%')
        || is_frontmatter_delimiter(line)
    {
        return None;
    }

    if matches!(first, '\'' | '"') {
        let (key, mut separator) = decoded_quoted_key(line, first)?;
        while matches!(line.as_bytes().get(separator), Some(b' ' | b'\t')) {
            separator += 1;
        }
        if line.as_bytes().get(separator) != Some(&b':') {
            return None;
        }
        let value = &line[separator + 1..];
        if !value.is_empty() && !value.chars().next().is_some_and(char::is_whitespace) {
            return None;
        }
        return Some(FrontmatterPropertyHeader {
            key,
            value: value.to_owned(),
        });
    }

    for (separator, character) in line.char_indices() {
        if character != ':' {
            continue;
        }
        let value = &line[separator + 1..];
        if value.is_empty() || value.chars().next().is_some_and(char::is_whitespace) {
            let key = line[..separator].trim();
            if !is_supported_plain_key(key) {
                return None;
            }
            return Some(FrontmatterPropertyHeader {
                key: key.to_owned(),
                value: value.to_owned(),
            });
        }
    }
    None
}

fn decoded_quoted_key(line: &str, quote: char) -> Option<(String, usize)> {
    let mut key = String::new();
    let mut index = 1;

    while index < line.len() {
        let character = line[index..].chars().next()?;
        let next_index = index + character.len_utf8();

        if quote == '\'' {
            if character == '\'' {
                if line.as_bytes().get(next_index) == Some(&b'\'') {
                    key.push('\'');
                    index = next_index + 1;
                    continue;
                }
                return Some((key, next_index));
            }
            key.push(character);
            index = next_index;
            continue;
        }

        if character == '"' {
            return Some((key, next_index));
        }
        if character != '\\' {
            key.push(character);
            index = next_index;
            continue;
        }

        let escape = *line.as_bytes().get(next_index)?;
        let after_escape = next_index + 1;
        match escape {
            b'0' => key.push('\0'),
            b'a' => key.push('\u{0007}'),
            b'b' => key.push('\u{0008}'),
            b't' | b'\t' => key.push('\t'),
            b'n' => key.push('\n'),
            b'v' => key.push('\u{000B}'),
            b'f' => key.push('\u{000C}'),
            b'r' => key.push('\r'),
            b'e' => key.push('\u{001B}'),
            b' ' => key.push(' '),
            b'"' => key.push('"'),
            b'/' => key.push('/'),
            b'\\' => key.push('\\'),
            b'N' => key.push('\u{0085}'),
            b'_' => key.push('\u{00A0}'),
            b'L' => key.push('\u{2028}'),
            b'P' => key.push('\u{2029}'),
            b'x' | b'u' | b'U' => {
                let count = match escape {
                    b'x' => 2,
                    b'u' => 4,
                    _ => 8,
                };
                let digits_end = after_escape.checked_add(count)?;
                let digits = line.as_bytes().get(after_escape..digits_end)?;
                if !digits.iter().all(u8::is_ascii_hexdigit) {
                    return None;
                }
                let digits = std::str::from_utf8(digits).ok()?;
                key.push(char::from_u32(u32::from_str_radix(digits, 16).ok()?)?);
                index = digits_end;
                continue;
            }
            _ => return None,
        }
        index = after_escape;
    }
    None
}

fn is_supported_plain_key(key: &str) -> bool {
    let Some(first) = key.chars().next() else {
        return false;
    };
    if matches!(
        first,
        '[' | ']' | '{' | '}' | ',' | '&' | '*' | '#' | '!' | '|' | '>' | '%' | '@' | '`'
    ) || key == "-"
        || key.starts_with("- ")
        || key.starts_with("-\t")
        || key == "?"
        || key.starts_with("? ")
        || key.starts_with("?\t")
    {
        return false;
    }

    let mut previous_was_whitespace = false;
    for character in key.chars() {
        if character == '#' && previous_was_whitespace {
            return false;
        }
        previous_was_whitespace = character.is_whitespace();
    }
    true
}

fn block_scalar_header(value: &str) -> BlockScalarHeaderParse {
    let Some(node) = yaml_node(value) else {
        return BlockScalarHeaderParse::Invalid;
    };
    if !matches!(node.as_bytes().first(), Some(b'|' | b'>')) {
        return BlockScalarHeaderParse::NotBlockScalar;
    }

    let mut indentation = None;
    let mut chomping = None;
    let mut index = 1;
    while index < node.len() {
        let byte = node.as_bytes()[index];
        if matches!(byte, b' ' | b'\t') {
            let remainder = trim_horizontal(&node[index..]);
            if !remainder.is_empty() && !remainder.starts_with('#') {
                return BlockScalarHeaderParse::Invalid;
            }
            return BlockScalarHeaderParse::Header(BlockScalarHeader {
                indentation,
                keeps_trailing_blank_lines: chomping == Some(b'+'),
            });
        }
        if matches!(byte, b'+' | b'-') {
            if chomping.is_some() {
                return BlockScalarHeaderParse::Invalid;
            }
            chomping = Some(byte);
        } else if (b'1'..=b'9').contains(&byte) {
            if indentation.is_some() {
                return BlockScalarHeaderParse::Invalid;
            }
            indentation = Some(usize::from(byte - b'0'));
        } else {
            return BlockScalarHeaderParse::Invalid;
        }
        index += 1;
    }

    BlockScalarHeaderParse::Header(BlockScalarHeader {
        indentation,
        keeps_trailing_blank_lines: chomping == Some(b'+'),
    })
}

fn block_scalar_end(
    lines: &[PhysicalLine],
    start: usize,
    header: &BlockScalarHeader,
) -> Option<usize> {
    let mut content_indent = header.indentation;
    let mut consumed_end = start;
    let mut last_nonblank_end = None;
    let mut index = start;

    while index < lines.len() {
        let line = &lines[index].content;
        if is_blank_yaml_line(line) {
            consumed_end = index + 1;
            index += 1;
            continue;
        }

        let indentation = leading_space_count(line)?;
        if content_indent.is_none() {
            if indentation == 0 {
                break;
            }
            content_indent = Some(indentation);
        }
        if indentation < content_indent.expect("content indentation established") {
            break;
        }

        consumed_end = index + 1;
        last_nonblank_end = Some(index + 1);
        index += 1;
    }

    Some(if header.keeps_trailing_blank_lines {
        consumed_end
    } else {
        last_nonblank_end.unwrap_or(start)
    })
}

fn flow_collection_node(line: &str) -> Option<String> {
    let mut candidate = trim_horizontal(line);
    if let Some(after_dash) = candidate.strip_prefix('-') {
        if after_dash.is_empty() || matches!(after_dash.as_bytes().first(), Some(b' ' | b'\t')) {
            candidate = trim_horizontal(after_dash);
        }
    }

    let node_text = if matches!(candidate.as_bytes().first(), Some(b'[' | b'{')) {
        candidate.to_owned()
    } else {
        property_header(candidate)?.value
    };
    let node = yaml_node(&node_text)?;
    matches!(node.as_bytes().first(), Some(b'[' | b'{')).then(|| node.to_owned())
}

/// Skip supported YAML tag/anchor node properties before a scalar or flow collection.
fn yaml_node(text: &str) -> Option<&str> {
    let mut node = trim_horizontal(text);

    while matches!(node.as_bytes().first(), Some(b'!' | b'&')) {
        let token_end = if node.starts_with("!<") {
            node.find('>')?.checked_add(1)?
        } else {
            let end = node.find([' ', '\t']).unwrap_or(node.len());
            if end == 1 {
                return None;
            }
            end
        };
        node = trim_horizontal(&node[token_end..]);
    }

    Some(node)
}

fn trim_horizontal(text: &str) -> &str {
    text.trim_start_matches([' ', '\t'])
}

fn is_yaml_trivia(line: &str) -> bool {
    is_blank_yaml_line(line) || trim_horizontal(line).starts_with('#')
}

fn is_blank_yaml_line(line: &str) -> bool {
    line.bytes().all(|byte| matches!(byte, b' ' | b'\t'))
}

fn leading_space_count(line: &str) -> Option<usize> {
    let mut count = 0;
    for byte in line.bytes() {
        if byte == b' ' {
            count += 1;
        } else if byte == b'\t' {
            return None;
        } else {
            break;
        }
    }
    Some(count)
}

fn is_indented(line: &str) -> bool {
    line.chars().next().is_some_and(char::is_whitespace)
}

fn is_frontmatter_delimiter(line: &str) -> bool {
    line.strip_prefix("---").is_some_and(|suffix| {
        suffix
            .chars()
            .all(|character| matches!(character, ' ' | '\t'))
    })
}

fn preferred_line_ending(document: &FrontmatterDocument) -> &'static str {
    std::iter::once(&document.opening)
        .chain(document.content.iter())
        .chain(std::iter::once(&document.closing))
        .find_map(|line| (!line.ending.is_empty()).then_some(line.ending))
        .unwrap_or("\n")
}

fn physical_lines(text: &str) -> Vec<PhysicalLine> {
    let bytes = text.as_bytes();
    let mut lines = Vec::new();
    let mut start = 0;
    let mut index = 0;

    while index < bytes.len() {
        if bytes[index] == b'\r' {
            let content = text[start..index].to_owned();
            if index + 1 < bytes.len() && bytes[index + 1] == b'\n' {
                lines.push(PhysicalLine {
                    content,
                    ending: "\r\n",
                });
                index += 2;
            } else {
                lines.push(PhysicalLine {
                    content,
                    ending: "\r",
                });
                index += 1;
            }
            start = index;
        } else if bytes[index] == b'\n' {
            lines.push(PhysicalLine {
                content: text[start..index].to_owned(),
                ending: "\n",
            });
            index += 1;
            start = index;
        } else {
            index += 1;
        }
    }

    if start < bytes.len() {
        lines.push(PhysicalLine {
            content: text[start..].to_owned(),
            ending: "",
        });
    }
    lines
}

fn render_frontmatter_envelope(document: &FrontmatterDocument) -> String {
    let mut output = String::new();
    document.opening.append_to(&mut output);
    append_lines(&mut output, &document.content);
    document.closing.append_to(&mut output);
    output
}

fn append_lines(output: &mut String, lines: &[PhysicalLine]) {
    for line in lines {
        line.append_to(output);
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

    #[test]
    fn apple_frontmatter_splice_preserves_physical_yaml_blocks() {
        let existing = "---\ndate: 2026-08-03\ntags:\n  - daily-notes\naliases:\n  - Health\n  - Journal\n# User-owned settings stay where they are.\n\npreferences:\n  dashboard:\n    visible: true\n---\n";
        let generated = "---\ndate: 2026-07-30\nsteps: 2119\n---\n";
        let expected = "---\ndate: 2026-07-30\ntags:\n  - daily-notes\naliases:\n  - Health\n  - Journal\n# User-owned settings stay where they are.\n\npreferences:\n  dashboard:\n    visible: true\nsteps: 2119\n---\n";

        assert_eq!(
            merge_profile_markdown(
                SemanticProfile::AppleHealthDataV7,
                existing,
                generated,
                true,
            )
            .unwrap(),
            expected
        );
    }

    #[test]
    fn apple_frontmatter_splice_removes_only_colliding_duplicates() {
        let existing = "---\nsteps: 100\ncustom: first\n# Keep this comment.\nsteps: 200\ncustom: second\n---\n";
        let generated = "---\nsteps: 300\n---\n";
        let expected =
            "---\nsteps: 300\ncustom: first\n# Keep this comment.\ncustom: second\n---\n";

        assert_eq!(
            merge_profile_markdown(
                SemanticProfile::AppleHealthDataV7,
                existing,
                generated,
                true,
            )
            .unwrap(),
            expected
        );
    }

    #[test]
    fn apple_frontmatter_splice_preserves_crlf_scalars_delimiters_and_body() {
        let frontmatter = "---\r\nsummary: |-\r\n  first line\r\n  ---\r\n  last line\r\n\r\nfolded: >+\r\n  one folded\r\n  paragraph\r\n---\r\n";
        let body = "# My Daily Note\r\n\r\nUser prose with no final newline";
        let generated = "---\nsteps: 42\n---\n";
        let expected_frontmatter = "---\r\nsummary: |-\r\n  first line\r\n  ---\r\n  last line\r\n\r\nfolded: >+\r\n  one folded\r\n  paragraph\r\nsteps: 42\r\n---\r\n";

        assert_eq!(
            merge_profile_markdown(
                SemanticProfile::AppleHealthDataV7,
                &(frontmatter.to_owned() + body),
                generated,
                true,
            )
            .unwrap(),
            expected_frontmatter.to_owned() + body
        );
    }

    #[test]
    fn apple_merge_adds_only_required_line_boundaries() {
        let frontmatter_only = "---\r\nuser: keep\r\n---";
        let user_prose = "## Notes\nUser prose with no final newline";
        let appended_section = "## Sleep\nfresh";

        assert_eq!(
            merge_profile_markdown(
                SemanticProfile::AppleHealthDataV7,
                frontmatter_only,
                appended_section,
                true,
            )
            .unwrap(),
            frontmatter_only.to_owned() + "\r\n" + appended_section
        );
        assert_eq!(
            merge_profile_markdown(
                SemanticProfile::AppleHealthDataV7,
                user_prose,
                appended_section,
                true,
            )
            .unwrap(),
            user_prose.to_owned() + "\n" + appended_section
        );
        assert_eq!(
            merge_profile_markdown(
                SemanticProfile::AppleHealthDataV7,
                frontmatter_only,
                "",
                true,
            )
            .unwrap(),
            frontmatter_only
        );
        assert_eq!(
            merge_profile_markdown(SemanticProfile::AppleHealthDataV7, user_prose, "", true)
                .unwrap(),
            user_prose
        );
    }

    #[test]
    fn apple_frontmatter_owns_comments_and_multiline_flow_continuations() {
        let existing = "---\nmetadata:\n  source: old\n# This comment interrupts the nested mapping.\n  labels:\n    - stale\nsteps: [\n  100,\n  200\n]\nkeep: unchanged\n---\n";
        let generated = "---\nmetadata: refreshed\nsteps: 300\n---\n";
        let expected = "---\nmetadata: refreshed\nsteps: 300\nkeep: unchanged\n---\n";

        assert_eq!(
            merge_profile_markdown(
                SemanticProfile::AppleHealthDataV7,
                existing,
                generated,
                true,
            )
            .unwrap(),
            expected
        );
    }

    #[test]
    fn apple_frontmatter_canonicalizes_quoted_scalar_keys() {
        let existing =
            "---\n\"steps\": 100\n'steps': 200\n\"st\\u0065ps\": 250\nkeep: unchanged\n---\n";
        let generated = "---\nsteps: 300\n---\n";
        let expected = "---\nsteps: 300\nkeep: unchanged\n---\n";

        assert_eq!(
            merge_profile_markdown(
                SemanticProfile::AppleHealthDataV7,
                existing,
                generated,
                true,
            )
            .unwrap(),
            expected
        );
    }

    #[test]
    fn apple_frontmatter_replaces_keep_chomped_scalar_blank_lines() {
        let existing = "---\nnotes: |2+\n  old\n\n\nkeep: unchanged\n---\n";
        let generated = "---\nnotes: >+2\n  fresh\n\n---\n";
        let expected = "---\nnotes: >+2\n  fresh\n\nkeep: unchanged\n---\n";

        assert_eq!(
            merge_profile_markdown(
                SemanticProfile::AppleHealthDataV7,
                existing,
                generated,
                true,
            )
            .unwrap(),
            expected
        );
    }

    #[test]
    fn apple_frontmatter_fails_closed_for_unsupported_complex_keys() {
        let existing = "---\n? \"steps\"\n: 100\nkeep: unchanged\n---\n";
        let generated = "---\nsteps: 300\n---\n";

        assert_eq!(
            merge_profile_markdown(
                SemanticProfile::AppleHealthDataV7,
                existing,
                generated,
                true,
            )
            .unwrap(),
            existing
        );
    }
}
