// Isolated fixture for testing LSP/compiler diagnostic undercurl and state interaction.
// Verifies: diagnostic undercurl (Red/Yellow) does NOT destroy underlying token foreground.

pub struct MetricCounter {
    pub count: u64,
}

impl MetricCounter {
    pub fn increment(&mut self) -> u64 {
        // Warning: unused variable
        let unused_local = 42;

        // Intentional diagnostic check point: type mismatch error if uncommented:
        // "string_literal"

        self.count += 1;
        self.count
    }
}
