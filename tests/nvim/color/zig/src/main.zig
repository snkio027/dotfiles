//! Zig color stress fixture for DX semantic highlight validation.

const std = @import("std");

// DX:M2 zig.binding.top_level_const
pub const module_limit: usize = 64;

// DX:M2 zig.binding.top_level_var
pub var module_counter: usize = 1;

pub const BindingProbe = struct {
    // DX:M2 zig.binding.struct_field
    field_value: usize,
};

pub fn observeBindings(
    // DX:M2 zig.binding.parameter
    parameter_value: usize,
) usize {
    // DX:M2 zig.binding.local_const
    const local_offset = parameter_value + module_limit;
    // DX:M2 zig.binding.local_var
    var local_total = module_counter;
    local_total += local_offset;
    const sample = BindingProbe{ .field_value = 1 };
    return local_total + sample.field_value;
}

/// Protocol connection state.
pub const ProtocolState = enum(u8) {
    idle = 0,
    active = 1,
    terminated = 2,
};

/// Tagged union for message payloads.
pub const Payload = union(enum) {
    ping: u32,
    data: []const u8,
    close: void,
};

/// System errors.
pub const FrameError = error{
    BufferOverflow,
    InvalidMagic,
    Timeout,
};

/// Network buffer wrapper with allocator tracking.
// DX:SENTINEL zig.network_buffer.type
pub const NetworkBuffer = struct {
    allocator: std.mem.Allocator,
    // Sentinel: primitive scalar type (Builtin = Steel Blue, authority = treesitter, LSP = type)
    // DX:SENTINEL zig.u8.builtin
    // DX:SENTINEL zig.bytes.member
    bytes: []u8,
    length: usize,
    // Sentinel: enum type reference (Type = Cyan, enum token)
    // DX:SENTINEL zig.protocol_state.type
    state: ProtocolState,

    pub fn init(allocator: std.mem.Allocator, initial_capacity: usize) !NetworkBuffer {
        const memory = try allocator.alloc(u8, initial_capacity);
        return NetworkBuffer{
            .allocator = allocator,
            .bytes = memory,
            .length = 0,
            .state = .idle,
        };
    }

    pub fn deinit(self: *NetworkBuffer) void {
        self.allocator.free(self.bytes);
        self.state = .terminated;
    }

    // DX:SENTINEL zig.pub.keyword
    // DX:SENTINEL zig.fn.keyword
    // DX:SENTINEL zig.append.method
    pub fn append(self: *NetworkBuffer, slice: []const u8) FrameError!usize {
        if (self.length + slice.len > self.bytes.len) {
            return FrameError.BufferOverflow;
        }
        @memcpy(self.bytes[self.length .. self.length + slice.len], slice);
        self.length += slice.len;
        self.state = .active;
        return self.length;
    }
};

/// Process frames with comptime validation.
pub fn processMessage(comptime T: type, item: T) !usize {
    // DX:SENTINEL zig.sizeof.builtin
    const item_size = @sizeOf(T);
    _ = item;
    return item_size;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var buffer = try NetworkBuffer.init(allocator, 1024);
    defer buffer.deinit();

    const sample = "Zig DX Semantic Highlights";
    const written = buffer.append(sample) catch |err| {
        std.debug.print("Error writing: {s}\n", .{@errorName(err)});
        return err;
    };

    var counter: usize = 0;
    // Sentinel: labeled while loop (Label = Neutral Slate)
    // DX:SENTINEL zig.drain.label
    drain: while (true) {
        counter += 1;
        if (counter >= 3) {
            break :drain;
        }
    }

    const size = try processMessage(u64, 42);
    const binding_total = observeBindings(counter);
    std.debug.print("Bytes: {d}, Item size: {d}, Counter: {d}, Binding: {d}\n", .{ written, size, counter, binding_total });
}
