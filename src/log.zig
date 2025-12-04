//! Logging infrastructure for labelle
//!
//! Provides scoped logging using Zig's standard library logging facilities.
//! Users can configure log levels at compile-time via std.options or
//! use the default log level.
//!
//! Example usage:
//! ```zig
//! // In your build.zig or root file, override the log level:
//! pub const std_options: std.Options = .{
//!     .log_level = .debug,
//!     .log_scope_levels = &.{
//!         .{ .scope = .labelle_engine, .level = .info },
//!         .{ .scope = .labelle_renderer, .level = .warn },
//!     },
//! };
//! ```

const std = @import("std");

/// Engine logger - for engine initialization, frame updates, entity management
pub const engine = std.log.scoped(.labelle_engine);

/// Renderer logger - for sprite drawing, texture loading, camera operations
pub const renderer = std.log.scoped(.labelle_renderer);

/// Animation logger - for animation state changes, frame updates
pub const animation = std.log.scoped(.labelle_animation);

/// Visual engine logger - for the self-contained visual engine
pub const visual = std.log.scoped(.labelle_visual);
