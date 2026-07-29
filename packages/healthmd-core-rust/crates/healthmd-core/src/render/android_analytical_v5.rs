//! Additive Android analytical-v5 local renderer.

use super::{RenderDay, RenderError, RenderFormat, RenderSessionConfig, format};

pub(crate) fn render_day(
    config: &RenderSessionConfig,
    day: &RenderDay,
    output: RenderFormat,
) -> Result<Vec<u8>, RenderError> {
    match output {
        RenderFormat::Markdown => format::render_markdown(config, day),
        RenderFormat::ObsidianBases => {
            format::render_frontmatter(config, day, format::FrontmatterSurface::Bases)
        }
        RenderFormat::Json => day.profile_documents.json_root.as_ref().map_or_else(
            || {
                format::kotlin_pretty_json(&format::public_json_entries(
                    config,
                    day,
                    config.profile,
                )?)
            },
            format::kotlin_ordered_json,
        ),
        RenderFormat::Csv => Ok(format::render_csv(config, day, config.profile)),
    }
}

#[cfg(test)]
mod tests {
    use serde_json::Value;

    use super::*;
    use crate::semantic::SemanticProfile;

    #[test]
    fn analytical_discriminators_are_insertion_ordered() {
        let entries = vec![
            ("date".to_owned(), Value::String("2026-07-25".to_owned())),
            ("type".to_owned(), Value::String("health-data".to_owned())),
            ("units".to_owned(), Value::String("metric".to_owned())),
            (
                "schemaProfile".to_owned(),
                Value::String("android-analytical-v5".to_owned()),
            ),
            ("schemaVersion".to_owned(), Value::from(5)),
        ];
        let output = String::from_utf8(format::kotlin_pretty_json(&entries).unwrap()).unwrap();
        assert_eq!(
            output,
            "{\n    \"date\": \"2026-07-25\",\n    \"type\": \"health-data\",\n    \"units\": \"metric\",\n    \"schemaProfile\": \"android-analytical-v5\",\n    \"schemaVersion\": 5\n}"
        );
        assert_eq!(
            super::super::profile_id(SemanticProfile::AndroidAnalyticalV5),
            "android_analytical_v5"
        );
    }
}
