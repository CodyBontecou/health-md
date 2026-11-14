//! Original private binding recovery; all metadata and keys are synthetic.
use super::*;
use crate::agent_retained_test_support::{native_binding, request, uuid};

async fn fixture() -> (
    tempfile::TempDir,
    HostAuthorityStore,
    NativeBinding,
    Vec<u8>,
) {
    let (temporary, store, output, request) = request().await;
    let binding = native_binding(request);
    let mut transaction =
        OutputTransaction::open(&store, &binding, || async { Ok(output.clone()) })
            .await
            .unwrap();
    transaction
        .save(|| async { Ok(output.clone()) })
        .await
        .unwrap();
    let bytes = private::read_private(transaction.directory(), &transaction.name, MAX_OUTPUT_BYTES)
        .unwrap();
    drop(transaction);
    (temporary, store, binding, bytes)
}

#[tokio::test]
async fn retained_output_loads_original_binding_without_caller_facts() {
    let (_temporary, store, binding, original) = Box::pin(fixture()).await;
    let dir = store.directory().unwrap();
    let lock = lock_outputs(&dir).unwrap();
    let key = SecretBox::new(Box::new([41; 32]));
    let (loaded, bytes) =
        read_retained_output(&dir, &store.host, &binding.request.job_id, &key).unwrap();
    assert!(loaded.binding == binding);
    assert!(loaded.plans.is_empty());
    assert_eq!(bytes, original);
    assert_eq!(
        private::read_private(
            &dir,
            &format!("output-{}.json", binding.request.job_id.0),
            MAX_OUTPUT_BYTES
        )
        .unwrap(),
        original
    );
    drop(lock);
}

fn changed_document(original: &[u8], case: usize) -> Vec<u8> {
    let mut document: serde_json::Value = serde_json::from_slice(original).unwrap();
    match case {
        0 => document["mac"] = serde_json::json!("f".repeat(64)),
        1 => document["journal"]["host"] = serde_json::json!(uuid(999)),
        2 => document["journal"]["version"] = serde_json::json!(2),
        3 => document["journal"]["binding"]["request"]["job_id"] = serde_json::json!(uuid(999)),
        4 => document["journal"]["binding"]["accepted"]["job_id"] = serde_json::json!(uuid(999)),
        5 => document["journal"]["binding"]["manifest"]["job_id"] = serde_json::json!(uuid(999)),
        6 => {
            document["journal"]["binding"]["request"]["caller_permission"] =
                serde_json::json!(true);
        }
        7 => document["journal"]["caller_frontier"] = serde_json::json!(0),
        8 => document["journal"]["plans"] = serde_json::json!([{}]),
        _ => (),
    }
    if (1..=8).contains(&case) {
        let mut mac = Hmac::<Sha256>::new_from_slice(&[41; 32]).unwrap();
        mac.update(OUTPUT_MAC_DOMAIN);
        mac.update(&private_json::encode(&document["journal"]).unwrap());
        document["mac"] = serde_json::json!(format!("{:x}", mac.finalize().into_bytes()));
    }
    let mut bytes = private_json::encode(&document).unwrap();
    if case == 9 {
        bytes.push(b'\n');
    }
    if case == 10 {
        bytes = String::from_utf8(bytes)
            .unwrap()
            .replacen("\"version\":1", "\"version\":1,\"version\":1", 1)
            .into_bytes();
        assert_ne!(bytes, original);
    }
    bytes
}

#[tokio::test]
async fn retained_output_rejects_signed_context_substitution_without_repair() {
    let (_temporary, store, binding, original) = Box::pin(fixture()).await;
    let dir = store.directory().unwrap();
    let _lock = lock_outputs(&dir).unwrap();
    let key = SecretBox::new(Box::new([41; 32]));
    let path = store
        .path
        .join(format!("output-{}.json", binding.request.job_id.0));
    for case in 0..11 {
        let changed = changed_document(&original, case);
        std::fs::write(&path, &changed).unwrap();
        assert!(
            read_retained_output(&dir, &store.host, &binding.request.job_id, &key).is_err(),
            "accepted substitution case {case}"
        );
        assert_eq!(
            std::fs::read(&path).unwrap(),
            changed,
            "repaired rejected evidence case {case}"
        );
    }
    std::fs::write(&path, &original).unwrap();
    assert!(
        read_retained_output(
            &dir,
            &store.host,
            &binding.request.job_id,
            &SecretBox::new(Box::new([42; 32]))
        )
        .is_err()
    );
    assert_eq!(std::fs::read(&path).unwrap(), original);
    assert!(read_retained_output(&dir, &store.host, &binding.request.job_id, &key).is_ok());
}

#[tokio::test]
async fn retained_output_missing_or_invalid_job_does_not_create_or_recover() {
    let (_temporary, store, binding, original) = Box::pin(fixture()).await;
    let dir = store.directory().unwrap();
    let _lock = lock_outputs(&dir).unwrap();
    let key = SecretBox::new(Box::new([41; 32]));
    let before = std::fs::read_dir(&store.path).unwrap().count();
    for job in [uuid(999), ControlUuid("../issuer".into())] {
        assert!(read_retained_output(&dir, &store.host, &job, &key).is_err());
    }
    assert_eq!(std::fs::read_dir(&store.path).unwrap().count(), before);
    assert_eq!(
        private::read_private(
            &dir,
            &format!("output-{}.json", binding.request.job_id.0),
            MAX_OUTPUT_BYTES
        )
        .unwrap(),
        original
    );
}
