# Document Level 1 Heading

A paragraph demonstrating the DX Semantic Color System markdown presentation.
This paragraph contains **bold emphasis**, *italic annotation*, and an inline `const MAX_SIZE = 1024` code token.

## Section Level 2 Heading

Here is an architectural link to the [Catppuccin Upstream Palette](https://github.com/catppuccin/catppuccin) repository.

### Subsection Level 3 Heading

> This is an editorial blockquote. It should render with a subtle Mauve marker
> and readable Subtext0 quote text, without turning into loud colored boxes.

#### Table of Metrics

| Semantic Component | Palette Color | Hierarchy Role |
| :--- | :--- | :--- |
| `DxCallable` | Warm Gold (Yellow) | Primary execution path landmark |
| `DxType` | Cool Teal | Structural domain data model |
| `DxBuiltin` | Sapphire | Native primitive / architecture types |
| `DxMember` | Lavender | Object field and property access |
| `DxVariable` | Text (Neutral) | Dense local body neutrality |

#### Lists

1. First ordered lifecycle step
2. Second ordered lifecycle step
   - Unordered child requirement
   - Another clean bullet

#### Admonitions

> [!NOTE]
> Information callout with sapphire theme.

> [!TIP]
> Helpful tip callout with cool teal accent.

> [!IMPORTANT]
> Key architectural requirement callout with mauve theme.

> [!WARNING]
> High priority warning callout with yellow state indicator.

> [!CAUTION]
> Critical danger callout with red scarcity indicator.

#### Code Block

```rust
pub fn calculate_digest(input: &[u8]) -> u64 {
    let mut hasher = DefaultHasher::new();
    hasher.write(input);
    hasher.finish()
}
```
