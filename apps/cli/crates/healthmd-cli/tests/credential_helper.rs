use std::process::{Command, Stdio};

#[cfg(debug_assertions)]
#[test]
fn supervised_same_executable_helper_round_trip_succeeds() {
    let output = Command::new(env!("CARGO_BIN_EXE_healthmd"))
        .arg("__credential-supervision-probe-v1")
        .stdin(Stdio::null())
        .output()
        .expect("healthmd should launch");

    assert!(output.status.success());
    assert!(output.stdout.is_empty());
    assert!(output.stderr.is_empty());
}

#[cfg(all(debug_assertions, windows))]
#[test]
fn windows_compatibility_launcher_supervises_its_own_helper() {
    let output = Command::new(env!("CARGO_BIN_EXE_healthmd-mcp"))
        .arg("__credential-supervision-probe-v1")
        .stdin(Stdio::null())
        .output()
        .expect("healthmd-mcp should launch");

    assert!(output.status.success());
    assert!(output.stdout.is_empty());
    assert!(output.stderr.is_empty());
}

#[test]
fn private_credential_helper_rejects_direct_invocation() {
    let output = Command::new(env!("CARGO_BIN_EXE_healthmd"))
        .arg("__credential-helper-v1")
        .stdin(Stdio::null())
        .output()
        .expect("healthmd should launch");

    assert!(!output.status.success());
    assert!(output.stdout.is_empty());
    assert!(output.stderr.is_empty());
}

#[cfg(windows)]
#[test]
fn windows_compatibility_helper_rejects_direct_invocation() {
    let output = Command::new(env!("CARGO_BIN_EXE_healthmd-mcp"))
        .arg("__credential-helper-v1")
        .stdin(Stdio::null())
        .output()
        .expect("healthmd-mcp should launch");

    assert!(!output.status.success());
    assert!(output.stdout.is_empty());
    assert!(output.stderr.is_empty());
}
