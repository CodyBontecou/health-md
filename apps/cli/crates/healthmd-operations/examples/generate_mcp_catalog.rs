use std::io::Write as _;

fn main() {
    let catalog =
        healthmd_operations::registry::list(healthmd_operations::SurfaceProfile::LocalDirect);
    let stdout = std::io::stdout();
    let mut output = stdout.lock();
    serde_json::to_writer_pretty(&mut output, &catalog).expect("catalog encodes");
    output.write_all(b"\n").expect("catalog writes");
}
