//! The mock/reference backend relocated to **labelle-core**
//! (labelle-assembler#387). Thin re-export so existing
//! `@import("labelle-gfx").MockBackend` references compile unchanged.

pub const MockBackend = @import("labelle-core").mock_backend.MockBackend;
