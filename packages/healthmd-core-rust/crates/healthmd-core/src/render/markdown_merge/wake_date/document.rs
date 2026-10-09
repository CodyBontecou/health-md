//! Successor-only document policies; frozen historical parsing is deliberately unchanged.

use crate::render::RenderError;

use super::super::{
    AppleDocument, AppleSection, apple_heading_level, apple_heading_name, frontmatter_document,
    is_yaml_trivia, physical_lines, property_blocks, property_header, render_frontmatter_envelope,
};

pub(super) fn preserve_filled_placeholders(generated: &str) -> Result<String, RenderError> {
    let Some(mut document) = frontmatter_document(generated) else {
        return Ok(generated.to_owned());
    };
    let blocks = property_blocks(&document.content).ok_or(RenderError::PresentationMismatch)?;
    let mut removed = vec![false; document.content.len()];
    for block in blocks {
        let lines = &document.content[block.range.clone()];
        let header = property_header(&lines[0].content).ok_or(RenderError::PresentationMismatch)?;
        if header.value.trim().is_empty()
            && lines[1..].iter().all(|line| is_yaml_trivia(&line.content))
        {
            removed[block.range].fill(true);
        }
    }
    document.content = document
        .content
        .into_iter()
        .enumerate()
        .filter_map(|(index, line)| (!removed[index]).then_some(line))
        .collect();
    let mut output = render_frontmatter_envelope(&document);
    for line in document.suffix {
        line.append_to(&mut output);
    }
    Ok(output)
}

pub(super) fn parse(content: &str) -> AppleDocument {
    let (frontmatter, lines) = if let Some(document) = frontmatter_document(content) {
        (render_frontmatter_envelope(&document), document.suffix)
    } else {
        (String::new(), physical_lines(content))
    };
    let section_level = section_level(&lines);
    let mut fence = Fence::default();
    let mut preamble = String::new();
    let mut sections = Vec::new();
    let mut heading: Option<String> = None;
    let mut name: Option<String> = None;
    let mut body = String::new();
    for line in lines {
        if !fence.protects(&line.content) && heading_level(&line.content) == section_level {
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

fn section_level(lines: &[super::super::PhysicalLine]) -> usize {
    let mut fence = Fence::default();
    for line in lines {
        if fence.protects(&line.content) {
            continue;
        }
        let level = heading_level(&line.content);
        if level > 0
            && matches!(
                apple_heading_name(&line.content).as_str(),
                "sleep"
                    | "activity"
                    | "heart"
                    | "vitals"
                    | "body"
                    | "nutrition"
                    | "mindfulness"
                    | "mobility"
                    | "hearing"
                    | "workouts"
                    | "medications"
            )
        {
            return level;
        }
    }
    2
}

fn heading_level(line: &str) -> usize {
    // Four-space/tab-indented lines are literal code, not section boundaries.
    if line.starts_with('\t') || line.bytes().take_while(|byte| *byte == b' ').count() >= 4 {
        0
    } else {
        apple_heading_level(line)
    }
}

#[derive(Default)]
struct Fence {
    open: Option<(u8, usize)>,
}

impl Fence {
    fn protects(&mut self, line: &str) -> bool {
        let trimmed = line.trim_start_matches(' ');
        let indentation = line.len() - trimmed.len();
        let marker = trimmed
            .as_bytes()
            .first()
            .copied()
            .filter(|byte| matches!(byte, b'`' | b'~'));
        let count = marker.map_or(0, |marker| {
            trimmed.bytes().take_while(|byte| *byte == marker).count()
        });
        if let Some((opened, minimum)) = self.open {
            if indentation <= 3
                && marker == Some(opened)
                && count >= minimum
                && trimmed[count..].trim().is_empty()
            {
                self.open = None;
            }
            return true;
        }
        if indentation <= 3 && count >= 3 {
            self.open = marker.map(|marker| (marker, count));
            return true;
        }
        false
    }
}
