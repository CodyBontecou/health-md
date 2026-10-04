#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SurfaceProfile {
    LocalDirect,
    LocalReadOnly,
    RemoteReadOnly,
    DataReadOnly,
}

impl SurfaceProfile {
    pub const fn exposes_local_exports(self) -> bool {
        matches!(self, Self::LocalDirect)
    }

    pub const fn is_read_only(self) -> bool {
        matches!(
            self,
            Self::LocalReadOnly | Self::RemoteReadOnly | Self::DataReadOnly
        )
    }

    pub const fn is_remote(self) -> bool {
        matches!(self, Self::RemoteReadOnly)
    }

    pub const fn is_data(self) -> bool {
        matches!(self, Self::DataReadOnly)
    }

    pub const fn wire_name(self) -> &'static str {
        match self {
            Self::LocalDirect => "local_direct",
            Self::LocalReadOnly => "local_read_only",
            Self::RemoteReadOnly => "remote_read_only",
            Self::DataReadOnly => "data_read_only",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn local_read_only_is_restricted_without_becoming_remote() {
        assert!(SurfaceProfile::LocalReadOnly.is_read_only());
        assert!(!SurfaceProfile::LocalReadOnly.is_remote());
        assert!(!SurfaceProfile::LocalReadOnly.exposes_local_exports());
        assert_eq!(SurfaceProfile::LocalReadOnly.wire_name(), "local_read_only");
    }

    #[test]
    fn data_surface_is_independent_and_read_only() {
        assert!(SurfaceProfile::DataReadOnly.is_read_only());
        assert!(SurfaceProfile::DataReadOnly.is_data());
        assert!(!SurfaceProfile::DataReadOnly.is_remote());
        assert!(!SurfaceProfile::DataReadOnly.exposes_local_exports());
        assert_eq!(SurfaceProfile::DataReadOnly.wire_name(), "data_read_only");
    }
}
