//! The render backend contract relocated to **labelle-core**
//! (labelle-assembler#387, RFC §Q#2). This file is now a thin re-export so
//! existing `@import("labelle-gfx").Backend` and value-type references compile
//! unchanged — gfx no longer *owns* the contract, it aliases core's.
//!
//! Because the value types (`Glyph`, `DecodedImage`, …) are now ONE nominal
//! type shared by core/gfx/engine, the codegen marshal boundary's `@ptrCast`
//! reinterpret hack collapses to identity (see labelle-engine#647).

const core = @import("labelle-core");

pub const Backend = core.backend_contract.Backend;
pub const assertBackend = core.backend_contract.assertBackend;
pub const missingBackendDecls = core.backend_contract.missingBackendDecls;

pub const DecodedImage = core.backend_contract.DecodedImage;
pub const DecodedFont = core.backend_contract.DecodedFont;
pub const FontBakeParams = core.backend_contract.FontBakeParams;
pub const CodepointRange = core.backend_contract.CodepointRange;
pub const Glyph = core.backend_contract.Glyph;
pub const CodepointEntry = core.backend_contract.CodepointEntry;
pub const KernPair = core.backend_contract.KernPair;

/// Blend mode for the optional `drawMesh` textured-mesh primitive
/// (labelle-gfx#290). Re-exported from core so the engine-facing draw API
/// (`RetainedEngineWith.drawMesh`) and callers can name it without importing
/// core directly.
pub const BlendMode = core.backend_contract.BlendMode;
