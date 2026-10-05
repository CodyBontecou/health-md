//! Bounded serialization preflight. `serde_json` otherwise converts NaN/infinity to null.
use serde::ser::{
    SerializeMap, SerializeSeq, SerializeStruct, SerializeStructVariant, SerializeTuple,
    SerializeTupleStruct, SerializeTupleVariant,
};
use serde::{Serialize, Serializer};

use super::codec::{MAX_DEPTH, MAX_NODES, MAX_STRING_SCALARS};
use super::{Error, shape};

impl serde::ser::Error for Error {
    fn custom<T: std::fmt::Display>(_: T) -> Self {
        Self::InvalidRequest
    }
}

pub(crate) fn check<T: Serialize + ?Sized>(value: &T) -> Result<(), Error> {
    value.serialize(IntegersOnly {
        depth: 0,
        nodes: &mut 0,
    })
}

struct IntegersOnly<'a> {
    depth: usize,
    nodes: &'a mut usize,
}
impl IntegersOnly<'_> {
    fn node(&mut self) -> Result<(), Error> {
        *self.nodes += 1;
        shape(self.depth <= MAX_DEPTH && *self.nodes <= MAX_NODES)
    }
    fn child(&mut self) -> IntegersOnly<'_> {
        IntegersOnly {
            depth: self.depth,
            nodes: self.nodes,
        }
    }
    fn collection(mut self, layers: usize) -> Result<Self, Error> {
        self.node()?;
        self.depth += layers;
        Ok(self)
    }
}
macro_rules! leaf {
    ($name:ident, $type:ty) => {
        fn $name(mut self, _: $type) -> Result<(), Error> {
            self.node()
        }
    };
}
impl Serializer for IntegersOnly<'_> {
    type Ok = ();
    type Error = Error;
    type SerializeSeq = Self;
    type SerializeTuple = Self;
    type SerializeTupleStruct = Self;
    type SerializeTupleVariant = Self;
    type SerializeMap = Self;
    type SerializeStruct = Self;
    type SerializeStructVariant = Self;

    leaf!(serialize_bool, bool);
    leaf!(serialize_i8, i8);
    leaf!(serialize_i16, i16);
    leaf!(serialize_i32, i32);
    leaf!(serialize_i64, i64);
    leaf!(serialize_u8, u8);
    leaf!(serialize_u16, u16);
    leaf!(serialize_u32, u32);
    leaf!(serialize_u64, u64);
    leaf!(serialize_char, char);
    fn serialize_f32(self, _: f32) -> Result<(), Error> {
        Err(Error::InvalidRequest)
    }
    fn serialize_f64(self, _: f64) -> Result<(), Error> {
        Err(Error::InvalidRequest)
    }
    fn serialize_str(mut self, value: &str) -> Result<(), Error> {
        self.node()?;
        shape(value.chars().count() <= MAX_STRING_SCALARS)
    }
    fn serialize_bytes(mut self, value: &[u8]) -> Result<(), Error> {
        self.node()?;
        shape(value.len() <= 4096)
    }
    fn serialize_none(mut self) -> Result<(), Error> {
        self.node()
    }
    fn serialize_some<T: Serialize + ?Sized>(self, value: &T) -> Result<(), Error> {
        value.serialize(self)
    }
    fn serialize_unit(mut self) -> Result<(), Error> {
        self.node()
    }
    fn serialize_unit_struct(mut self, _: &'static str) -> Result<(), Error> {
        self.node()
    }
    fn serialize_unit_variant(
        self,
        _: &'static str,
        _: u32,
        variant: &'static str,
    ) -> Result<(), Error> {
        self.serialize_str(variant)
    }
    fn serialize_newtype_struct<T: Serialize + ?Sized>(
        self,
        _: &'static str,
        value: &T,
    ) -> Result<(), Error> {
        value.serialize(self)
    }
    fn serialize_newtype_variant<T: Serialize + ?Sized>(
        self,
        _: &'static str,
        _: u32,
        _: &'static str,
        value: &T,
    ) -> Result<(), Error> {
        value.serialize(self.collection(1)?)
    }
    fn serialize_seq(self, len: Option<usize>) -> Result<Self, Error> {
        shape(len.is_none_or(|n| n <= 4096))?;
        self.collection(1)
    }
    fn serialize_tuple(self, len: usize) -> Result<Self, Error> {
        shape(len <= 4096)?;
        self.collection(1)
    }
    fn serialize_tuple_struct(self, _: &'static str, len: usize) -> Result<Self, Error> {
        self.serialize_tuple(len)
    }
    fn serialize_tuple_variant(
        self,
        _: &'static str,
        _: u32,
        _: &'static str,
        len: usize,
    ) -> Result<Self, Error> {
        shape(len <= 4096)?;
        self.collection(2)
    }
    fn serialize_map(self, len: Option<usize>) -> Result<Self, Error> {
        shape(len.is_none_or(|n| n <= 512))?;
        self.collection(1)
    }
    fn serialize_struct(self, _: &'static str, len: usize) -> Result<Self, Error> {
        self.serialize_map(Some(len))
    }
    fn serialize_struct_variant(
        self,
        _: &'static str,
        _: u32,
        _: &'static str,
        len: usize,
    ) -> Result<Self, Error> {
        shape(len <= 512)?;
        self.collection(2)
    }
}
macro_rules! sequence {
    ($trait:ident, $method:ident) => {
        impl $trait for IntegersOnly<'_> {
            type Ok = ();
            type Error = Error;
            fn $method<T: Serialize + ?Sized>(&mut self, value: &T) -> Result<(), Error> {
                value.serialize(self.child())
            }
            fn end(self) -> Result<(), Error> {
                Ok(())
            }
        }
    };
}
sequence!(SerializeSeq, serialize_element);
sequence!(SerializeTuple, serialize_element);
sequence!(SerializeTupleStruct, serialize_field);
sequence!(SerializeTupleVariant, serialize_field);
impl SerializeMap for IntegersOnly<'_> {
    type Ok = ();
    type Error = Error;
    fn serialize_key<T: Serialize + ?Sized>(&mut self, value: &T) -> Result<(), Error> {
        value.serialize(self.child())
    }
    fn serialize_value<T: Serialize + ?Sized>(&mut self, value: &T) -> Result<(), Error> {
        value.serialize(self.child())
    }
    fn end(self) -> Result<(), Error> {
        Ok(())
    }
}
macro_rules! structure {
    ($trait:ident) => {
        impl $trait for IntegersOnly<'_> {
            type Ok = ();
            type Error = Error;
            fn serialize_field<T: Serialize + ?Sized>(
                &mut self,
                key: &'static str,
                value: &T,
            ) -> Result<(), Error> {
                key.serialize(self.child())?;
                value.serialize(self.child())
            }
            fn end(self) -> Result<(), Error> {
                Ok(())
            }
        }
    };
}
structure!(SerializeStruct);
structure!(SerializeStructVariant);
