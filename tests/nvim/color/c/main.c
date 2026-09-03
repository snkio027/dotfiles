#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

// Sentinel: object-like macro (Meta = Dusty Pink)
// DX:SENTINEL c.buffer_capacity.macro
#define BUFFER_CAPACITY 4096

// Sentinel: struct type declaration (Type = Muted Teal)
// DX:SENTINEL c.buffer.struct
struct Buffer {
    // Sentinel: struct member field (Member = Periwinkle)
    // DX:SENTINEL c.size.member
    size_t size;
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

    // Sentinel: primitive system type (Builtin = Steel Blue, type + defaultLibrary)
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

    int result = decode(&buf);
    if (result > 0) {
        printf("Decoded size: %d\n", result);
    }
    return 0;
}
