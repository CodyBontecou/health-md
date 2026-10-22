//! Canonical signed completion bytes are evidence, never new execution authority.
use super::*;

pub(crate) struct CompletionEvidence {
    dir: cap_std::fs::Dir,
    name: String,
    bytes: Option<Vec<u8>>,
}
impl CompletionEvidence {
    pub fn is_present(&self) -> bool {
        self.bytes.is_some()
    }
    pub(super) fn bytes(&self) -> Option<&[u8]> {
        self.bytes.as_deref()
    }
    pub fn verify(&self) -> Result<(), ClientError> {
        match &self.bytes {
            Some(expected)
                if private::read_private(&self.dir, &self.name, MAX_OUTPUT_BYTES)? == *expected =>
            {
                Ok(())
            }
            None => match self.dir.symlink_metadata(&self.name) {
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
                _ => Err(Error::BindingChanged.into()),
            },
            _ => Err(Error::BindingChanged.into()),
        }
    }
}

impl OutputTransaction {
    pub(super) fn signed_document<T: Serialize>(
        &self,
        domain: &[u8],
        data: &T,
    ) -> Result<Vec<u8>, ClientError> {
        #[derive(Serialize)]
        struct Signed<'a, T> {
            journal: &'a T,
            mac: Digest,
        }
        let mut signer = Hmac::<Sha256>::new_from_slice(self.key.expose_secret())
            .map_err(private::unavailable)?;
        signer.update(domain);
        signer.update(self.journal.binding.request.job_id.0.as_bytes());
        signer.update(&private_json::encode(data)?);
        let mac = Digest(format!("{:x}", signer.finalize().into_bytes()));
        private_json::encode(&Signed { journal: data, mac })
    }

    pub fn completion_evidence<T: Serialize>(
        &self,
        data: &T,
        required: Option<&Digest>,
    ) -> Result<CompletionEvidence, ClientError> {
        self.require_current()?;
        let name = format!("completion-{}.json", self.journal.binding.request.job_id.0);
        let expected =
            self.signed_document(b"HealthMd.AgentBridge.HostCompletionJournal.v1\0", data)?;
        let bytes = match self.dir.symlink_metadata(&name) {
            Ok(_) => {
                let bytes = private::read_private(&self.dir, &name, MAX_OUTPUT_BYTES)?;
                if bytes != expected {
                    return Err(Error::BindingChanged.into());
                }
                Some(bytes)
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound && required.is_none() => {
                None
            }
            _ => return Err(Error::BindingChanged.into()),
        };
        if let Some(required) = required {
            required.validate_shape()?;
            if bytes
                .as_ref()
                .map(|value| healthmd_protocol::transfer::sha256_hex(value))
                .as_deref()
                != Some(&required.0)
            {
                return Err(Error::BindingChanged.into());
            }
        }
        let evidence = CompletionEvidence {
            dir: self.dir.try_clone().map_err(private::unavailable)?,
            name,
            bytes,
        };
        evidence.verify()?;
        self.require_current()?;
        Ok(evidence)
    }
}
