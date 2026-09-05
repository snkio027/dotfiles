#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

// Sentinel: object-like macro (Meta = Dusty Pink)
// DX:SENTINEL c.buffer_capacity.macro
#define BUFFER_CAPACITY 4096

// DX:M2 c.binding.file_global
int c_global_counter = 1;

// DX:M2 c.binding.file_static
static int c_static_counter = 2;

struct BindingProbe {
    // DX:M2 c.binding.struct_member
    int member_value;
};

static int observe_binding_topology(
    // DX:M2 c.binding.parameter
    int parameter_value
) {
    // DX:M2 c.binding.local_variable
    int local_value = parameter_value + c_global_counter + c_static_counter;
    struct BindingProbe probe = { .member_value = local_value };
    return probe.member_value;
}

// Sentinel: struct type declaration (Type = Muted Teal)
// DX:SENTINEL c.buffer.struct
struct Buffer {
    // Sentinel: struct member field (Member = Periwinkle)
    // DX:SENTINEL c.size.member
    size_t size;
    // Sentinel: primitive typedef (Builtin = Steel Blue, authority = treesitter, LSP = type)
    // DX:SENTINEL c.uint8.builtin
    uint8_t data[BUFFER_CAPACITY];
};

// Sentinel: function definition (Callable = Muted Amber)
// DX:SENTINEL c.decode.fn
static int decode(
    // Sentinel: function parameter pointer (Parameter = Muted Violet-Gray)
    // DX:SENTINEL c.buffer.param
    struct Buffer *buffer
) {
    if (buffer == NULL || buffer->size == 0) {
        return -1;
    }

    // Sentinel: primitive scalar type (Builtin = Steel Blue)
    // DX:SENTINEL c.int.builtin
    int retry_count = 3;

    // Sentinel: control-flow goto label (Label = Neutral Slate)
    // DX:SENTINEL c.retry.label
retry:
    if (retry_count-- > 0) {
        buffer->data[0] = (uint8_t)(buffer->size & 0xFF);
        goto retry;
    }

    return (int)buffer->size;
}

int main(void) {
    struct Buffer buf = {
        .size = 64,
        .data = { 0 },
    };

    int result = decode(&buf) + observe_binding_topology(1);
    if (result > 0) {
        printf("Decoded size: %d\n", result);
    }
    return 0;
}
