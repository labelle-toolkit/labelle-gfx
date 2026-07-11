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

/// Per-draw curated material seam (labelle-gfx#305). Re-exported from core
/// alongside `BlendMode` so `SpriteVisual.material` authors and callers can name
/// these without importing core directly. `Material.effect == .none` (the
/// default) is the batch-friendly fast path; a non-`none` effect rides the
/// optional `drawTextureProMaterial` backend decl and degrades where a backend
/// doesn't support it. See also the CPU-side `effects.TintPulse` (RFC §5).
pub const Material = core.backend_contract.Material;
pub const MaterialEffect = core.backend_contract.MaterialEffect;
pub const MaterialUniforms = core.backend_contract.MaterialUniforms;
pub const MaterialCapabilities = core.backend_contract.MaterialCapabilities;
pub const materialCapabilities = core.backend_contract.materialCapabilities;

/// Full-screen post-fx pass stack (labelle-gfx#305, RFC §2). Value types +
/// capability introspection re-exported from core; the ping-pong stack DRIVER is
/// `post_fx.PostFxDriver` in gfx. The optional `createRenderTarget`/…/
/// `applyPostPass`/`postPassSupported` decls live on `Backend(Impl)` and degrade
/// gracefully on backends without them.
pub const RenderTargetId = core.backend_contract.RenderTargetId;
pub const PostPass = core.backend_contract.PostPass;
pub const PostPassKind = core.backend_contract.PostPassKind;
pub const PostPassUniforms = core.backend_contract.PostPassUniforms;
pub const PostFxCapabilities = core.backend_contract.PostFxCapabilities;
pub const postFxCapabilities = core.backend_contract.postFxCapabilities;
pub const hasRenderTargetSubSurface = core.backend_contract.hasRenderTargetSubSurface;
