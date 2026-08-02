#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SurfaceProfile {
    LocalDirect,
    RemoteReadOnly,
    Hosted,
}

impl SurfaceProfile {
    pub const fn exposes_local_exports(self) -> bool {
        matches!(self, Self::LocalDirect)
    }

    pub const fn is_remote(self) -> bool {
        matches!(self, Self::RemoteReadOnly | Self::Hosted)
    }

    pub const fn wire_name(self) -> &'static str {
        match self {
            Self::LocalDirect => "local_direct",
            Self::RemoteReadOnly => "remote_read_only",
            Self::Hosted => "hosted",
        }
    }
}
