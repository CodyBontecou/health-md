use std::{collections::BTreeSet, fmt::Write as _};

use anstyle::{AnsiColor, Style};
use serde_json::{Map, Value};

const TITLE_STYLE: Style = AnsiColor::BrightCyan.on_default().bold();
const SUCCESS_STYLE: Style = AnsiColor::BrightGreen.on_default().bold();
const ERROR_STYLE: Style = AnsiColor::BrightRed.on_default().bold();
const WARNING_STYLE: Style = AnsiColor::BrightYellow.on_default().bold();
const SECTION_STYLE: Style = AnsiColor::BrightBlue.on_default().bold();
const COMMAND_STYLE: Style = AnsiColor::BrightGreen.on_default();
const NAME_STYLE: Style = AnsiColor::BrightCyan.on_default();
const RULE_STYLE: Style = AnsiColor::BrightBlack.on_default().dimmed();

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum OutputMode {
    Human,
    Json,
}

impl OutputMode {
    pub(super) const fn resolve(force_json: bool, force_human: bool, terminal: bool) -> Self {
        if force_json || (!force_human && !terminal) {
            Self::Json
        } else {
            Self::Human
        }
    }
}

pub(super) fn color_enabled(terminal: bool) -> bool {
    let disabled = std::env::var_os("NO_COLOR").is_some()
        || std::env::var_os("CLICOLOR").is_some_and(|value| value == "0")
        || std::env::var_os("TERM").is_some_and(|value| value == "dumb");
    should_color(terminal, disabled)
}

const fn should_color(terminal: bool, disabled: bool) -> bool {
    terminal && !disabled
}

pub(super) fn render(value: &Value, color: bool) -> String {
    let rendered = match value.get("schema").and_then(Value::as_str) {
        Some("healthmd.cli_guidance") => render_guidance(value),
        Some("healthmd.cli_error") => render_error(value),
        Some("healthmd.mcp_tool_catalog") => render_mcp_catalog(value),
        Some("healthmd.mcp_tool_schema") => render_mcp_tool(value),
        _ => render_document(value),
    };
    if color {
        colorize(value, &rendered)
    } else {
        rendered
    }
}

fn render_guidance(value: &Value) -> String {
    if value.get("command").and_then(Value::as_str) == Some("healthmd query")
        && value.get("recognized_operation").and_then(Value::as_bool) == Some(false)
    {
        return render_query_catalog(value);
    }
    if value.get("recognized_operation").and_then(Value::as_bool) == Some(true) {
        return render_query_operation(value);
    }

    let command = value
        .get("command")
        .and_then(Value::as_str)
        .unwrap_or("Health.md");
    let mut output = String::new();
    heading(&mut output, command);
    push_description(&mut output, value.get("description"), 0);
    push_description(&mut output, value.get("message"), 0);
    push_description(&mut output, value.get("platform_note"), 0);

    let preferred = [
        ("missing", "Missing"),
        ("required", "Required"),
        ("required_choices", "Required choices"),
        ("available_commands", "Available commands"),
        ("modes", "Modes"),
        ("selection_options", "Selection options"),
        ("output_options", "Output options"),
        ("common_options", "Common options"),
        ("optional", "Optional"),
        ("before_continuing", "Before continuing"),
        ("object_aliases", "Object aliases"),
        ("examples", "Examples"),
        ("next_actions", "Next steps"),
    ];
    let mut rendered = BTreeSet::new();
    for (key, label) in preferred {
        if let Some(section) = value.get(key).filter(|section| !is_empty(section)) {
            section_heading(&mut output, label);
            render_section(&mut output, key, section, 2);
            rendered.insert(key);
        }
    }

    let skipped = [
        "schema",
        "schema_version",
        "status",
        "backend",
        "command",
        "message",
        "description",
        "platform_note",
        "request_sent",
        "recognized_operation",
    ];
    if let Some(object) = value.as_object() {
        for (key, section) in object {
            if skipped.contains(&key.as_str())
                || rendered.contains(key.as_str())
                || is_empty(section)
            {
                continue;
            }
            section_heading(&mut output, &label(key));
            render_section(&mut output, key, section, 2);
        }
    }

    machine_hint(&mut output, command);
    finish(output)
}

fn render_query_catalog(value: &Value) -> String {
    let mut output = String::new();
    heading(&mut output, "Available health queries");
    push_description(&mut output, value.get("platform_note"), 0);

    if let Some(operations) = value.get("available_operations").and_then(Value::as_array) {
        for operation in operations {
            let name = string_at(operation, "name").unwrap_or("unknown");
            let title = string_at(operation, "title").unwrap_or(name);
            output.push_str("  ");
            output.push_str(name);
            output.push('\n');
            push_wrapped(&mut output, title, 4);
            if let Some(description) = string_at(operation, "description") {
                push_wrapped(&mut output, first_sentence(description), 4);
            }
            output.push('\n');
        }
    }

    section_heading(&mut output, "Inspect a query");
    output.push_str("  healthmd query healthmd_sleep_sessions\n");
    section_heading(&mut output, "Machine-readable catalog");
    output.push_str("  healthmd query --json\n");
    finish(output)
}

fn render_query_operation(value: &Value) -> String {
    let operation = value.get("operation").unwrap_or(&Value::Null);
    let name = string_at(operation, "name").unwrap_or("healthmd query");
    let title = string_at(operation, "title").unwrap_or(name);
    let mut output = String::new();
    heading(&mut output, title);
    output.push_str("Operation: ");
    output.push_str(name);
    output.push('\n');
    push_description(&mut output, operation.get("description"), 0);

    if let Some(schema) = value.get("input_schema") {
        render_schema_synopsis(&mut output, schema);
    }

    if let Some(examples) = value.get("examples").and_then(Value::as_array) {
        section_heading(&mut output, "Examples");
        for example in examples.iter().take(3) {
            if let Some(argv) = example.get("argv").and_then(Value::as_array) {
                push_command(&mut output, argv, 2);
            }
        }
    }

    section_heading(&mut output, "Full JSON Schema");
    output.push_str("  healthmd query ");
    output.push_str(name);
    output.push_str(" --json\n");
    finish(output)
}

fn render_schema_synopsis(output: &mut String, schema: &Value) {
    let Some(properties) = schema.get("properties").and_then(Value::as_object) else {
        return;
    };
    let required = schema
        .get("required")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .collect::<BTreeSet<_>>();

    section_heading(output, "Arguments");
    for (name, property) in properties {
        output.push_str("  ");
        output.push_str(name);
        if required.contains(name.as_str()) {
            output.push_str(" (required)");
        }
        if let Some(kind) = schema_type(property) {
            output.push_str("  ");
            output.push_str(&kind);
        }
        output.push('\n');
        push_description(output, property.get("description"), 4);
        if let Some(default) = property.get("default") {
            push_wrapped(output, &format!("Default: {}", inline_value(default)), 4);
        }
    }
}

fn render_error(value: &Value) -> String {
    let mut output = String::new();
    let code = value
        .get("error")
        .and_then(Value::as_str)
        .unwrap_or("command_failed");
    heading(&mut output, &format!("Error: {}", label(code)));
    push_description(&mut output, value.get("message"), 0);
    output.push_str("Code: ");
    output.push_str(code);
    output.push('\n');

    if let Some(arguments) = value
        .get("accepted_arguments")
        .filter(|item| !is_empty(item))
    {
        section_heading(&mut output, "Accepted arguments");
        render_section(&mut output, "accepted_arguments", arguments, 2);
    }
    if let Some(actions) = value.get("next_actions").filter(|item| !is_empty(item)) {
        section_heading(&mut output, "Next steps");
        render_section(&mut output, "next_actions", actions, 2);
    }
    if let Some(help) = value.get("help_command").and_then(Value::as_str) {
        section_heading(&mut output, "Help");
        output.push_str("  ");
        output.push_str(help);
        output.push('\n');
    }
    if let Some(command) = value.get("command").and_then(Value::as_str) {
        machine_hint(&mut output, command);
    }
    finish(output)
}

fn render_mcp_catalog(value: &Value) -> String {
    let mut output = String::new();
    heading(&mut output, "Available MCP tools");
    if let Some(tools) = value.get("tools").and_then(Value::as_array) {
        for tool in tools {
            let name = string_at(tool, "name").unwrap_or("unknown");
            output.push_str("  ");
            output.push_str(name);
            output.push('\n');
            if let Some(description) = string_at(tool, "description") {
                push_wrapped(&mut output, first_sentence(description), 4);
            }
            if let Some(required) = tool
                .pointer("/inputSchema/required")
                .and_then(Value::as_array)
                .filter(|items| !items.is_empty())
            {
                let fields = required
                    .iter()
                    .filter_map(Value::as_str)
                    .collect::<Vec<_>>()
                    .join(", ");
                push_wrapped(&mut output, &format!("Required: {fields}"), 4);
            }
            output.push('\n');
        }
    }
    section_heading(&mut output, "Inspect a tool");
    output.push_str("  healthmd mcp schema healthmd_sleep_sessions\n");
    section_heading(&mut output, "Machine-readable catalog");
    output.push_str("  healthmd mcp schema --json\n");
    finish(output)
}

fn render_mcp_tool(value: &Value) -> String {
    let tool = value.get("tool").unwrap_or(&Value::Null);
    let name = string_at(tool, "name").unwrap_or("MCP tool");
    let mut output = String::new();
    heading(&mut output, name);
    push_description(&mut output, tool.get("description"), 0);
    if let Some(schema) = tool.get("inputSchema") {
        render_schema_synopsis(&mut output, schema);
    }
    section_heading(&mut output, "Machine-readable schema");
    output.push_str("  healthmd mcp schema ");
    output.push_str(name);
    output.push_str(" --json\n");
    finish(output)
}

fn render_document(value: &Value) -> String {
    let mut output = String::new();
    let title = document_title(value);
    heading(&mut output, &title);
    push_description(&mut output, value.get("message"), 0);

    match value {
        Value::Object(object) => {
            for (key, item) in object {
                if ["schema", "schema_version", "message"].contains(&key.as_str()) {
                    continue;
                }
                render_field(&mut output, key, item, 0);
            }
        }
        _ => render_value(&mut output, value, 0),
    }
    finish(output)
}

fn document_title(value: &Value) -> String {
    if value.get("status").and_then(Value::as_str) == Some("success") {
        return "Success".to_owned();
    }
    match value.get("schema").and_then(Value::as_str) {
        Some("healthmd.direct_devices") => "Paired devices".to_owned(),
        Some("healthmd.direct_pairing_result") => "Device paired".to_owned(),
        Some("healthmd.codex_setup") => "Codex setup".to_owned(),
        Some(schema) => label(schema.rsplit('.').next().unwrap_or(schema)),
        None => "Health.md result".to_owned(),
    }
}

fn render_section(output: &mut String, key: &str, value: &Value, indent: usize) {
    match (key, value) {
        ("available_commands" | "next_actions", Value::Array(items)) => {
            for item in items {
                render_action(output, item, indent);
            }
        }
        ("examples", Value::Array(items)) => {
            for item in items {
                if let Some(description) = item.get("description").and_then(Value::as_str) {
                    push_wrapped(output, description, indent);
                }
                if let Some(argv) = item
                    .get("argv")
                    .or_else(|| item.get("argv_template"))
                    .and_then(Value::as_array)
                {
                    push_command(output, argv, indent + 2);
                } else {
                    render_value(output, item, indent);
                }
            }
        }
        ("missing" | "required" | "optional" | "common_options", Value::Array(items)) => {
            for item in items {
                render_argument(output, item, indent);
            }
        }
        ("required_choices", Value::Array(items)) => {
            for item in items {
                let name = string_at(item, "name").unwrap_or("choice");
                push_wrapped(output, &label(name), indent);
                for choices_key in ["exactly_one_of", "one_or_more_of"] {
                    if let Some(choices) = item.get(choices_key).and_then(Value::as_array) {
                        for choice in choices.iter().filter_map(Value::as_str) {
                            push_wrapped(output, &format!("- {choice}"), indent + 2);
                        }
                    }
                }
            }
        }
        ("modes", Value::Array(items)) => {
            for item in items {
                let name = string_at(item, "name").map(label).unwrap_or_default();
                push_wrapped(output, &name, indent);
                push_description(output, item.get("description"), indent + 2);
                if let Some(required) = item.get("required") {
                    output.push_str(&" ".repeat(indent + 2));
                    output.push_str("Required: ");
                    output.push_str(&inline_value(required));
                    output.push('\n');
                }
                for options_key in ["options", "settings_options"] {
                    if let Some(options) = item.get(options_key) {
                        push_wrapped(
                            output,
                            &format!("{}: {}", label(options_key), inline_value(options)),
                            indent + 2,
                        );
                    }
                }
                push_description(output, item.get("platform_note"), indent + 2);
                output.push('\n');
            }
        }
        _ => render_value(output, value, indent),
    }
}

fn render_action(output: &mut String, value: &Value, indent: usize) {
    let command = value
        .get("command")
        .or_else(|| value.get("command_template"))
        .or_else(|| value.get("action"))
        .and_then(Value::as_str);
    if let Some(command) = command {
        push_wrapped(output, command, indent);
        push_description(output, value.get("description"), indent + 2);
    } else {
        render_value(output, value, indent);
    }
}

fn render_argument(output: &mut String, value: &Value, indent: usize) {
    let name = value
        .get("argument")
        .or_else(|| value.get("name"))
        .and_then(Value::as_str);
    if let Some(name) = name {
        let mut summary = name.to_owned();
        if let Some(default) = value.get("default") {
            let _ = write!(summary, " (default: {})", inline_value(default));
        }
        push_wrapped(output, &summary, indent);
        push_description(output, value.get("description"), indent + 2);
    } else {
        render_value(output, value, indent);
    }
}

fn render_field(output: &mut String, key: &str, value: &Value, indent: usize) {
    match value {
        Value::String(text) => {
            push_wrapped(output, &format!("{}: {text}", label(key)), indent);
        }
        Value::Null | Value::Bool(_) | Value::Number(_) => {
            output.push_str(&" ".repeat(indent));
            output.push_str(&label(key));
            output.push_str(": ");
            output.push_str(&inline_value(value));
            output.push('\n');
        }
        Value::Array(items) if items.iter().all(is_scalar) && inline_value(value).len() < 80 => {
            output.push_str(&" ".repeat(indent));
            output.push_str(&label(key));
            output.push_str(": ");
            output.push_str(&inline_value(value));
            output.push('\n');
        }
        _ => {
            output.push_str(&" ".repeat(indent));
            output.push_str(&label(key));
            output.push('\n');
            render_value(output, value, indent + 2);
        }
    }
}

fn render_value(output: &mut String, value: &Value, indent: usize) {
    match value {
        Value::Object(object) => render_object(output, object, indent),
        Value::Array(items) => {
            if items.is_empty() {
                push_wrapped(output, "None", indent);
            } else if items.iter().all(is_scalar) {
                for item in items {
                    push_wrapped(output, &format!("- {}", inline_value(item)), indent);
                }
            } else {
                for (index, item) in items.iter().enumerate() {
                    if index > 0 {
                        output.push('\n');
                    }
                    match item {
                        Value::Object(object) => {
                            output.push_str(&" ".repeat(indent));
                            output.push_str("-\n");
                            render_object(output, object, indent + 2);
                        }
                        _ => render_value(output, item, indent),
                    }
                }
            }
        }
        _ => push_wrapped(output, &inline_value(value), indent),
    }
}

fn render_object(output: &mut String, object: &Map<String, Value>, indent: usize) {
    if object.is_empty() {
        push_wrapped(output, "None", indent);
        return;
    }
    for (key, value) in object {
        render_field(output, key, value, indent);
    }
}

fn schema_type(property: &Value) -> Option<String> {
    if let Some(values) = property.get("enum").and_then(Value::as_array) {
        return Some(
            values
                .iter()
                .map(inline_value)
                .collect::<Vec<_>>()
                .join(" | "),
        );
    }
    match property.get("type") {
        Some(Value::String(kind)) => Some(kind.clone()),
        Some(Value::Array(kinds)) => Some(
            kinds
                .iter()
                .filter_map(Value::as_str)
                .collect::<Vec<_>>()
                .join(" | "),
        ),
        _ if property.get("oneOf").is_some() => Some("object".to_owned()),
        _ => None,
    }
}

fn inline_value(value: &Value) -> String {
    match value {
        Value::Null => "None".to_owned(),
        Value::Bool(true) => "Yes".to_owned(),
        Value::Bool(false) => "No".to_owned(),
        Value::Number(number) => number.to_string(),
        Value::String(text) => text.clone(),
        Value::Array(items) => items
            .iter()
            .map(inline_value)
            .collect::<Vec<_>>()
            .join(", "),
        Value::Object(_) => serde_json::to_string(value).unwrap_or_else(|_| "{…}".to_owned()),
    }
}

fn is_scalar(value: &Value) -> bool {
    matches!(
        value,
        Value::Null | Value::Bool(_) | Value::Number(_) | Value::String(_)
    )
}

fn is_empty(value: &Value) -> bool {
    matches!(value, Value::Null)
        || value.as_array().is_some_and(Vec::is_empty)
        || value.as_object().is_some_and(Map::is_empty)
}

fn string_at<'a>(value: &'a Value, key: &str) -> Option<&'a str> {
    value.get(key).and_then(Value::as_str)
}

fn heading(output: &mut String, title: &str) {
    output.push_str(title);
    output.push('\n');
    output.push_str(&"=".repeat(title.chars().count().min(72)));
    output.push_str("\n\n");
}

fn section_heading(output: &mut String, title: &str) {
    if !output.ends_with("\n\n") {
        output.push('\n');
    }
    output.push_str(title);
    output.push('\n');
}

fn push_description(output: &mut String, value: Option<&Value>, indent: usize) {
    if let Some(description) = value.and_then(Value::as_str) {
        push_wrapped(output, description, indent);
    }
}

fn push_wrapped(output: &mut String, text: &str, indent: usize) {
    let width = terminal_width().saturating_sub(indent).max(30);
    let prefix = " ".repeat(indent);
    let mut line = String::new();
    for word in text.split_whitespace() {
        let separator = usize::from(!line.is_empty());
        if !line.is_empty() && line.chars().count() + separator + word.chars().count() > width {
            output.push_str(&prefix);
            output.push_str(&line);
            output.push('\n');
            line.clear();
        }
        if !line.is_empty() {
            line.push(' ');
        }
        line.push_str(word);
    }
    if !line.is_empty() {
        output.push_str(&prefix);
        output.push_str(&line);
        output.push('\n');
    }
}

fn terminal_width() -> usize {
    std::env::var("COLUMNS")
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .filter(|width| *width >= 40)
        .unwrap_or(100)
}

fn push_command(output: &mut String, argv: &[Value], indent: usize) {
    let command = argv
        .iter()
        .filter_map(Value::as_str)
        .map(shell_quote)
        .collect::<Vec<_>>()
        .join(" ");
    output.push_str(&" ".repeat(indent));
    output.push_str("$ ");
    output.push_str(&command);
    output.push('\n');
}

fn shell_quote(value: &str) -> String {
    if value
        .chars()
        .all(|character| character.is_ascii_alphanumeric() || "_-./:<>|".contains(character))
    {
        value.to_owned()
    } else {
        format!("'{}'", value.replace('\'', "'\\''"))
    }
}

fn machine_hint(output: &mut String, command: &str) {
    section_heading(output, "Machine-readable output");
    output.push_str("  ");
    output.push_str(command);
    output.push_str(" --json\n");
}

fn first_sentence(value: &str) -> &str {
    value.find(". ").map_or(value, |end| &value[..=end])
}

fn label(value: &str) -> String {
    let normalized = value
        .split(['_', '-'])
        .filter(|word| !word.is_empty())
        .collect::<Vec<_>>()
        .join(" ");
    let mut characters = normalized.chars();
    characters.next().map_or(normalized.clone(), |initial| {
        format!("{}{}", initial.to_uppercase(), characters.as_str())
    })
}

fn colorize(value: &Value, rendered: &str) -> String {
    let lines = rendered.lines().collect::<Vec<_>>();
    let mut output = String::with_capacity(rendered.len() + 128);

    for (index, line) in lines.iter().enumerate() {
        let style = if index == 0 {
            Some(document_style(value))
        } else if index == 1 && !line.is_empty() && line.chars().all(|character| character == '=') {
            Some(RULE_STYLE)
        } else if is_section_heading(&lines, index) {
            Some(SECTION_STYLE)
        } else if line.trim_start().starts_with("$ ")
            || (line.starts_with("  ") && line.trim_start().starts_with("healthmd "))
        {
            Some(COMMAND_STYLE)
        } else if line.starts_with("  ") && line.trim_start().starts_with("healthmd_") {
            Some(NAME_STYLE)
        } else {
            None
        };

        if let Some(style) = style {
            let _ = write!(output, "{style}{line}{style:#}");
        } else {
            output.push_str(line);
        }
        output.push('\n');
    }

    output
}

fn document_style(value: &Value) -> Style {
    let status = value.get("status").and_then(Value::as_str);
    if value.get("schema").and_then(Value::as_str) == Some("healthmd.cli_error")
        || matches!(status, Some("error" | "failed"))
    {
        ERROR_STYLE
    } else if status == Some("success") {
        SUCCESS_STYLE
    } else if matches!(status, Some("warning" | "paused" | "cancelled")) {
        WARNING_STYLE
    } else {
        TITLE_STYLE
    }
}

fn is_section_heading(lines: &[&str], index: usize) -> bool {
    index > 1
        && index + 1 < lines.len()
        && !lines[index].is_empty()
        && !lines[index].starts_with(char::is_whitespace)
        && lines[index - 1].is_empty()
        && lines[index + 1].starts_with(char::is_whitespace)
}

fn finish(mut output: String) -> String {
    while output.ends_with("\n\n") {
        output.pop();
    }
    if !output.ends_with('\n') {
        output.push('\n');
    }
    output
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn automatic_output_is_human_only_for_a_terminal() {
        assert_eq!(OutputMode::resolve(false, false, true), OutputMode::Human);
        assert_eq!(OutputMode::resolve(false, false, false), OutputMode::Json);
        assert_eq!(OutputMode::resolve(true, false, true), OutputMode::Json);
        assert_eq!(OutputMode::resolve(false, true, false), OutputMode::Human);
    }

    #[test]
    fn automatic_color_requires_a_capable_terminal() {
        assert!(should_color(true, false));
        assert!(!should_color(false, false));
        assert!(!should_color(true, true));
    }

    #[test]
    fn colored_human_output_styles_titles_sections_and_commands() {
        let value = json!({
            "schema": "healthmd.cli_guidance",
            "command": "healthmd export",
            "examples": [{"argv": ["healthmd", "export", "--yesterday", "--raw"]}]
        });
        let colored = render(&value, true);
        assert!(colored.starts_with(&format!("{TITLE_STYLE}healthmd export")));
        assert!(colored.contains(&format!("{SECTION_STYLE}Examples")));
        assert!(colored.contains(&format!("{COMMAND_STYLE}    $ healthmd export")));
        assert!(colored.contains("\u{1b}[0m"));

        let plain = render(&value, false);
        assert!(!plain.contains('\u{1b}'));
    }

    #[test]
    fn errors_use_the_error_title_style() {
        let value = json!({
            "schema": "healthmd.cli_error",
            "error": "invalid_request",
            "message": "The request is incomplete."
        });
        assert!(render(&value, true).starts_with(&format!("{ERROR_STYLE}Error:")));
    }

    #[test]
    fn query_catalog_is_a_scannable_list() {
        let value = json!({
            "schema": "healthmd.cli_guidance",
            "command": "healthmd query",
            "recognized_operation": false,
            "available_operations": [{
                "name": "healthmd_sleep_sessions",
                "title": "List sleep sessions",
                "description": "Preferred operation for sleep questions. More agent detail follows."
            }]
        });
        let rendered = render(&value, false);
        assert!(rendered.starts_with("Available health queries"));
        assert!(rendered.contains("healthmd_sleep_sessions"));
        assert!(rendered.contains("List sleep sessions"));
        assert!(!rendered.contains("More agent detail follows"));
        assert!(!rendered.contains("\"available_operations\""));
    }

    #[test]
    fn operation_schema_is_reduced_to_an_argument_synopsis() {
        let value = json!({
            "schema": "healthmd.cli_guidance",
            "recognized_operation": true,
            "operation": {
                "name": "healthmd_sleep_sessions",
                "title": "List sleep sessions",
                "description": "Sleep details."
            },
            "input_schema": {
                "required": ["dates"],
                "properties": {
                    "dates": {"type": "object", "description": "Date selection."},
                    "include_naps": {"type": "boolean", "default": false}
                }
            },
            "examples": [{"argv": ["healthmd", "query", "healthmd_sleep_sessions", "--arguments", "{}"]}]
        });
        let rendered = render(&value, false);
        assert!(rendered.contains("dates (required)  object"));
        assert!(rendered.contains("include_naps  boolean"));
        assert!(rendered.contains("Default: No"));
        assert!(rendered.contains("Full JSON Schema"));
    }

    #[test]
    fn errors_show_recovery_without_nested_json() {
        let value = json!({
            "schema": "healthmd.cli_error",
            "error": "invalid_request",
            "message": "The request is incomplete.",
            "command": "healthmd export",
            "help_command": "healthmd export --help",
            "next_actions": [{"command": "healthmd export --help", "description": "Review options."}]
        });
        let rendered = render(&value, false);
        assert!(rendered.starts_with("Error: Invalid request"));
        assert!(rendered.contains("Next steps"));
        assert!(!rendered.contains("\"error\""));
    }

    #[test]
    fn generic_results_keep_missingness_and_nested_records_visible() {
        let value = json!({
            "schema": "healthmd.direct_devices",
            "backend": "direct",
            "selected_device": null,
            "devices": [{"name": "Test iPhone", "connected": true}]
        });
        let rendered = render(&value, false);
        assert!(rendered.starts_with("Paired devices"));
        assert!(rendered.contains("Selected device: None"));
        assert!(rendered.contains("Name: Test iPhone"));
        assert!(rendered.contains("Connected: Yes"));
    }
}
