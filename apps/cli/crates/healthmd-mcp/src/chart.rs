#![allow(
    clippy::cast_possible_truncation,
    clippy::cast_possible_wrap,
    clippy::cast_sign_loss
)]

use std::collections::{BTreeMap, BTreeSet};

use serde_json::Value;

const WIDTH: usize = 1_200;
const HEIGHT: usize = 675;
const COLORS: &[[u8; 4]] = &[
    [9, 105, 218, 255],
    [24, 121, 78, 255],
    [138, 82, 204, 255],
    [201, 117, 0, 255],
    [199, 34, 46, 255],
    [34, 139, 139, 255],
];

#[derive(Clone)]
struct Point {
    date: String,
    value: Option<f64>,
}

fn collect_series(response: &Value) -> Option<Vec<(String, String, Vec<Point>)>> {
    let items: Vec<&Value> = if let Some(items) = response.get("items").and_then(Value::as_array) {
        items.iter().collect()
    } else {
        response
            .get("pages")?
            .as_array()?
            .iter()
            .filter_map(|page| page.get("items").and_then(Value::as_array))
            .flatten()
            .collect()
    };
    if items.is_empty() {
        return None;
    }
    let mut pending = Vec::new();
    let mut known_units: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    for item in items {
        if item.get("type").and_then(Value::as_str) != Some("metric") {
            continue;
        }
        let metric = item.get("metric")?.as_object()?;
        let metric_id = metric.get("metric_id")?.as_str()?.to_owned();
        let date = metric.get("owner_date")?.as_str()?.to_owned();
        let available = metric.get("status").and_then(Value::as_str) == Some("available");
        let typed_value = metric.get("value");
        let value = if available {
            typed_value.and_then(numeric)
        } else {
            None
        };
        let unit = typed_value
            .and_then(typed_unit)
            .unwrap_or("unknown")
            .to_owned();
        if unit != "unknown" {
            known_units
                .entry(metric_id.clone())
                .or_default()
                .insert(unit.clone());
        }
        pending.push((metric_id, unit, Point { date, value }));
    }
    let mut grouped: BTreeMap<(String, String), Vec<Point>> = BTreeMap::new();
    for (metric_id, unit, point) in pending {
        if unit == "unknown" {
            if let Some(units) = known_units.get(&metric_id) {
                if !units.is_empty() {
                    for known_unit in units {
                        grouped
                            .entry((metric_id.clone(), known_unit.clone()))
                            .or_default()
                            .push(point.clone());
                    }
                    continue;
                }
            }
        }
        grouped.entry((metric_id, unit)).or_default().push(point);
    }
    if grouped.is_empty() {
        return None;
    }
    Some(
        grouped
            .into_iter()
            .take(6)
            .map(|((name, unit), mut points)| {
                points.sort_by(|left, right| left.date.cmp(&right.date));
                (name, unit, points)
            })
            .collect(),
    )
}

#[allow(clippy::too_many_lines)]
pub fn render(response: &Value) -> Option<Vec<u8>> {
    let series = collect_series(response)?;
    let dates: Vec<String> = series
        .iter()
        .flat_map(|(_, _, points)| points.iter().map(|point| point.date.clone()))
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect();
    if dates.is_empty() {
        return None;
    }
    let date_index: BTreeMap<&str, usize> = dates
        .iter()
        .enumerate()
        .map(|(index, date)| (date.as_str(), index))
        .collect();
    if !series
        .iter()
        .any(|(_, _, points)| points.iter().any(|point| point.value.is_some()))
    {
        return None;
    }

    let mut canvas = Canvas::new(WIDTH, HEIGHT, [247, 248, 250, 255]);
    canvas.fill_rect(24, 24, WIDTH - 48, HEIGHT - 48, [255, 255, 255, 255]);
    canvas.stroke_rect(24, 24, WIDTH - 48, HEIGHT - 48, [220, 225, 232, 255]);
    canvas.text(
        52,
        48,
        "HEALTH.MD DIRECT IPHONE METRICS",
        3,
        [23, 32, 42, 255],
    );

    let left = 92_i32;
    let right = (WIDTH - 54) as i32;
    let top = 94_i32;
    let bottom = (HEIGHT - 88) as i32;
    let gap = 8_i32;
    let panel_height = (bottom - top - gap * (series.len() as i32 - 1)) / series.len() as i32;
    for (series_index, (name, unit, points)) in series.iter().enumerate() {
        let color = COLORS[series_index % COLORS.len()];
        let panel_top = top + series_index as i32 * (panel_height + gap);
        let panel_bottom = panel_top + panel_height;
        let plot_top = panel_top + 16;
        let plot_bottom = panel_bottom - 3;
        canvas.line(left, plot_top, right, plot_top, [225, 229, 235, 255]);
        canvas.line(left, plot_bottom, right, plot_bottom, [225, 229, 235, 255]);
        canvas.line(left, plot_top, left, plot_bottom, [100, 110, 122, 255]);
        canvas.fill_rect(left as usize + 8, panel_top as usize + 2, 14, 8, color);
        canvas.text(
            left as usize + 30,
            panel_top as usize + 1,
            &format!("{name} [{unit}]"),
            1,
            [45, 55, 68, 255],
        );
        let values: Vec<f64> = points
            .iter()
            .filter_map(|point| point.value)
            .filter(|value| value.is_finite())
            .collect();
        if values.is_empty() {
            continue;
        }
        let mut minimum = values.iter().copied().fold(f64::INFINITY, f64::min);
        let mut maximum = values.iter().copied().fold(f64::NEG_INFINITY, f64::max);
        if (maximum - minimum).abs() < f64::EPSILON {
            let padding = maximum.abs().max(1.0) * 0.08;
            minimum -= padding;
            maximum += padding;
        }
        canvas.text(
            38,
            plot_top as usize,
            &format_number(maximum),
            1,
            [74, 85, 99, 255],
        );
        canvas.text(
            38,
            (plot_bottom - 6) as usize,
            &format_number(minimum),
            1,
            [74, 85, 99, 255],
        );
        let mut previous: Option<(i32, i32)> = None;
        for point in points {
            let Some(index) = date_index.get(point.date.as_str()).copied() else {
                previous = None;
                continue;
            };
            let Some(value) = point.value.filter(|value| value.is_finite()) else {
                previous = None;
                continue;
            };
            let x = if dates.len() == 1 {
                (left + right) / 2
            } else {
                left + ((right - left) as usize * index / (dates.len() - 1)) as i32
            };
            let ratio = ((value - minimum) / (maximum - minimum)).clamp(0.0, 1.0);
            let y = plot_bottom - (ratio * f64::from(plot_bottom - plot_top)).round() as i32;
            if let Some((old_x, old_y)) = previous {
                canvas.thick_line(old_x, old_y, x, y, 2, color);
            }
            canvas.circle(x, y, 4, color);
            previous = Some((x, y));
        }
    }

    if let Some(first) = dates.first() {
        canvas.text(
            left as usize,
            bottom as usize + 22,
            first,
            1,
            [74, 85, 99, 255],
        );
    }
    if let Some(last) = dates.last() {
        let width = text_width(last, 1);
        canvas.text(
            (right as usize).saturating_sub(width),
            bottom as usize + 22,
            last,
            1,
            [74, 85, 99, 255],
        );
    }
    canvas.text(
        52,
        HEIGHT - 48,
        "UP TO 6 SERIES; ONLY STATUS=AVAILABLE IS PLOTTED; JSON IS AUTHORITATIVE",
        1,
        [74, 85, 99, 255],
    );
    canvas.png().ok()
}

fn numeric(value: &Value) -> Option<f64> {
    let object = value.as_object()?;
    match object.get("type")?.as_str()? {
        "quantity" | "count" => object.get("value")?.as_f64(),
        "duration" => object.get("seconds")?.as_f64(),
        _ => None,
    }
}

fn typed_unit(value: &Value) -> Option<&str> {
    let object = value.as_object()?;
    object
        .get("unit")
        .and_then(Value::as_str)
        .or_else(|| match object.get("type")?.as_str()? {
            "count" => Some("count"),
            "duration" => Some("s"),
            _ => None,
        })
}

fn format_number(value: f64) -> String {
    if value.abs() >= 1_000.0 {
        format!("{value:.0}")
    } else if value.abs() >= 10.0 {
        format!("{value:.1}")
    } else {
        format!("{value:.2}")
    }
}

struct Canvas {
    width: usize,
    height: usize,
    pixels: Vec<u8>,
}

impl Canvas {
    fn new(width: usize, height: usize, color: [u8; 4]) -> Self {
        let mut pixels = vec![0; width * height * 4];
        for pixel in pixels.chunks_exact_mut(4) {
            pixel.copy_from_slice(&color);
        }
        Self {
            width,
            height,
            pixels,
        }
    }

    fn pixel(&mut self, x: i32, y: i32, color: [u8; 4]) {
        if x < 0 || y < 0 || x >= self.width as i32 || y >= self.height as i32 {
            return;
        }
        let offset = (y as usize * self.width + x as usize) * 4;
        self.pixels[offset..offset + 4].copy_from_slice(&color);
    }

    fn fill_rect(&mut self, x: usize, y: usize, width: usize, height: usize, color: [u8; 4]) {
        for row in y..y.saturating_add(height).min(self.height) {
            for column in x..x.saturating_add(width).min(self.width) {
                self.pixel(column as i32, row as i32, color);
            }
        }
    }

    fn stroke_rect(&mut self, x: usize, y: usize, width: usize, height: usize, color: [u8; 4]) {
        self.line(x as i32, y as i32, (x + width) as i32, y as i32, color);
        self.line(x as i32, y as i32, x as i32, (y + height) as i32, color);
        self.line(
            (x + width) as i32,
            y as i32,
            (x + width) as i32,
            (y + height) as i32,
            color,
        );
        self.line(
            x as i32,
            (y + height) as i32,
            (x + width) as i32,
            (y + height) as i32,
            color,
        );
    }

    fn line(&mut self, mut x0: i32, mut y0: i32, x1: i32, y1: i32, color: [u8; 4]) {
        let dx = (x1 - x0).abs();
        let sx = if x0 < x1 { 1 } else { -1 };
        let dy = -(y1 - y0).abs();
        let sy = if y0 < y1 { 1 } else { -1 };
        let mut error = dx + dy;
        loop {
            self.pixel(x0, y0, color);
            if x0 == x1 && y0 == y1 {
                break;
            }
            let twice = 2 * error;
            if twice >= dy {
                error += dy;
                x0 += sx;
            }
            if twice <= dx {
                error += dx;
                y0 += sy;
            }
        }
    }

    fn thick_line(&mut self, x0: i32, y0: i32, x1: i32, y1: i32, radius: i32, color: [u8; 4]) {
        for offset in -radius..=radius {
            self.line(x0, y0 + offset, x1, y1 + offset, color);
        }
    }

    fn circle(&mut self, center_x: i32, center_y: i32, radius: i32, color: [u8; 4]) {
        for y in -radius..=radius {
            for x in -radius..=radius {
                if x * x + y * y <= radius * radius {
                    self.pixel(center_x + x, center_y + y, color);
                }
            }
        }
    }

    fn text(&mut self, x: usize, y: usize, value: &str, scale: usize, color: [u8; 4]) {
        let mut cursor = x;
        for character in value.chars() {
            let glyph = glyph(character.to_ascii_uppercase());
            for (row, bits) in glyph.iter().enumerate() {
                for column in 0..5 {
                    if bits & (1 << (4 - column)) != 0 {
                        self.fill_rect(
                            cursor + column * scale,
                            y + row * scale,
                            scale,
                            scale,
                            color,
                        );
                    }
                }
            }
            cursor += 6 * scale;
            if cursor >= self.width.saturating_sub(5 * scale) {
                break;
            }
        }
    }

    fn png(&self) -> Result<Vec<u8>, png::EncodingError> {
        let mut output = Vec::new();
        {
            let mut encoder = png::Encoder::new(&mut output, self.width as u32, self.height as u32);
            encoder.set_color(png::ColorType::Rgba);
            encoder.set_depth(png::BitDepth::Eight);
            let mut writer = encoder.write_header()?;
            writer.write_image_data(&self.pixels)?;
        }
        Ok(output)
    }
}

fn text_width(value: &str, scale: usize) -> usize {
    value.chars().count() * 6 * scale
}

fn glyph(character: char) -> [u8; 7] {
    match character {
        'A' => [14, 17, 17, 31, 17, 17, 17],
        'B' => [30, 17, 17, 30, 17, 17, 30],
        'C' => [14, 17, 16, 16, 16, 17, 14],
        'D' => [30, 17, 17, 17, 17, 17, 30],
        'E' => [31, 16, 16, 30, 16, 16, 31],
        'F' => [31, 16, 16, 30, 16, 16, 16],
        'G' => [14, 17, 16, 23, 17, 17, 15],
        'H' => [17, 17, 17, 31, 17, 17, 17],
        'I' => [31, 4, 4, 4, 4, 4, 31],
        'J' => [7, 2, 2, 2, 2, 18, 12],
        'K' => [17, 18, 20, 24, 20, 18, 17],
        'L' => [16, 16, 16, 16, 16, 16, 31],
        'M' => [17, 27, 21, 21, 17, 17, 17],
        'N' => [17, 25, 21, 19, 17, 17, 17],
        'O' => [14, 17, 17, 17, 17, 17, 14],
        'P' => [30, 17, 17, 30, 16, 16, 16],
        'Q' => [14, 17, 17, 17, 21, 18, 13],
        'R' => [30, 17, 17, 30, 20, 18, 17],
        'S' => [15, 16, 16, 14, 1, 1, 30],
        'T' => [31, 4, 4, 4, 4, 4, 4],
        'U' => [17, 17, 17, 17, 17, 17, 14],
        'V' => [17, 17, 17, 17, 17, 10, 4],
        'W' => [17, 17, 17, 21, 21, 21, 10],
        'X' => [17, 17, 10, 4, 10, 17, 17],
        'Y' => [17, 17, 10, 4, 4, 4, 4],
        'Z' => [31, 1, 2, 4, 8, 16, 31],
        '0' => [14, 17, 19, 21, 25, 17, 14],
        '1' => [4, 12, 4, 4, 4, 4, 14],
        '2' => [14, 17, 1, 2, 4, 8, 31],
        '3' => [30, 1, 1, 14, 1, 1, 30],
        '4' => [2, 6, 10, 18, 31, 2, 2],
        '5' => [31, 16, 16, 30, 1, 1, 30],
        '6' => [14, 16, 16, 30, 17, 17, 14],
        '7' => [31, 1, 2, 4, 8, 8, 8],
        '8' => [14, 17, 17, 14, 17, 17, 14],
        '9' => [14, 17, 17, 15, 1, 1, 14],
        '-' => [0, 0, 0, 31, 0, 0, 0],
        '_' => [0, 0, 0, 0, 0, 0, 31],
        '.' => [0, 0, 0, 0, 0, 12, 12],
        ':' => [0, 12, 12, 0, 12, 12, 0],
        '/' => [1, 2, 2, 4, 8, 8, 16],
        '=' => [0, 31, 0, 31, 0, 0, 0],
        _ => [0; 7],
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn partial_numeric_points_remain_gaps_in_png() {
        let response = serde_json::json!({
            "items": [
                {"type":"metric","metric":{"metric_id":"steps","owner_date":"2026-07-01","status":"available","value":{"type":"count","value":1000}}},
                {"type":"metric","metric":{"metric_id":"steps","owner_date":"2026-07-02","status":"partial","value":{"type":"count","value":9999}}},
                {"type":"metric","metric":{"metric_id":"steps","owner_date":"2026-07-03","status":"available","value":{"type":"count","value":3000}}}
            ]
        });
        let png = render(&response).unwrap();
        assert_eq!(&png[..8], b"\x89PNG\r\n\x1a\n");
        assert!(png.len() > 10_000);
    }

    #[test]
    fn null_missing_value_inherits_the_known_unit_and_remains_a_gap() {
        let response = serde_json::json!({
            "items": [
                {"type":"metric","metric":{"metric_id":"steps","owner_date":"2026-07-01","status":"available","value":{"type":"count","value":1000}}},
                {"type":"metric","metric":{"metric_id":"steps","owner_date":"2026-07-02","status":"missing","value":null}},
                {"type":"metric","metric":{"metric_id":"steps","owner_date":"2026-07-03","status":"available","value":{"type":"count","value":3000}}}
            ]
        });
        let series = collect_series(&response).unwrap();
        assert_eq!(series.len(), 1);
        assert_eq!(series[0].1, "count");
        assert_eq!(series[0].2.len(), 3);
        assert!(series[0].2[1].value.is_none());
    }

    #[test]
    fn identical_metric_ids_with_different_units_never_share_an_axis() {
        let response = serde_json::json!({
            "items": [
                {"type":"metric","metric":{"metric_id":"ambiguous","owner_date":"2026-07-01","status":"available","value":{"type":"quantity","unit":"mg/dL","value":90}}},
                {"type":"metric","metric":{"metric_id":"ambiguous","owner_date":"2026-07-02","status":"available","value":{"type":"quantity","unit":"mmol/L","value":5}}}
            ]
        });
        let series = collect_series(&response).unwrap();
        assert_eq!(series.len(), 2);
        assert_eq!(
            series
                .iter()
                .map(|(_, unit, _)| unit.as_str())
                .collect::<BTreeSet<_>>(),
            BTreeSet::from(["mg/dL", "mmol/L"])
        );
    }

    #[test]
    fn multipage_wrapper_also_renders() {
        let response = serde_json::json!({
            "schema":"healthmd.mcp_query_pages","schema_version":1,
            "pages":[{"items":[
                {"type":"metric","metric":{"metric_id":"steps","owner_date":"2026-07-01","status":"available","value":{"type":"count","value":1000}}}
            ]}]
        });
        assert_eq!(&render(&response).unwrap()[..8], b"\x89PNG\r\n\x1a\n");
    }
}
