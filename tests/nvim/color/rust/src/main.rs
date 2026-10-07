use std::collections::HashMap;
use std::time::Duration;

mod alias_source {
    pub struct Payload;
    impl Payload {
        pub const SIZE: usize = 1;
    }
}
// DX:E3 rust.alias.module_declaration
use alias_source as route;
// DX:E3 rust.alias.imported_type_declaration
use alias_source::Payload as ImportedPayload;
// DX:E3 rust.alias.type_declaration
type AliasPayload = alias_source::Payload;

pub fn observe_alias_identity() -> usize {
    // DX:E3 rust.alias.module_reference
    // DX:E3 rust.alias.qualified_terminal_type
    let value: route::Payload = alias_source::Payload;
    // DX:E3 rust.alias.type_reference
    let direct: AliasPayload = value;
    // DX:E3 rust.alias.imported_type_reference
    let imported: ImportedPayload = direct;
    // DX:E3 rust.alias.type_qualifier
    AliasPayload::SIZE + std::mem::size_of_val(&imported)
}

// DX:M2 rust.binding.static_item
pub static MODULE_COUNTER: u32 = 7;

/// Constant limit value for buffer allocation.
// DX:M2 rust.binding.const_item
pub const MAX_CAPACITY: usize = 65536;

pub struct BindingProbe {
    // DX:M2 rust.binding.struct_field
    pub field_value: u32,
}

pub fn observe_binding_topology(
    // DX:M2 rust.binding.parameter
    parameter_value: u32,
) -> u32 {
    // DX:M2 rust.binding.local_let
    // DX:E3 rust.value.static_reference
    let local_value = parameter_value + MODULE_COUNTER;
    // DX:M2 rust.binding.local_let_mut
    // DX:E3 rust.value.let_reference
    let mut mutable_value = local_value;
    mutable_value += 1;
    let probe = BindingProbe { field_value: 2 };
    // DX:E3 rust.value.let_mut_reference
    mutable_value + probe.field_value
}

/// An operational state classification.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    Ready,
    Running,
    Finished(u32),
}

/// A pipeline consumer trait for streaming data.
pub trait StreamConsumer<T> {
    fn process(&mut self, item: T) -> Result<usize, String>;
}

/// A verified download summary data model.
// DX:SENTINEL rust.download_summary.type
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DownloadSummary {
    pub size: u64,
    // Sentinel: standard library type (Type = Cyan, defaultLibrary)
    // DX:SENTINEL rust.duration.type
    pub latency: Duration,
    pub status: Status,
    pub metadata: HashMap<String, String>,
}

impl DownloadSummary {
    // Sentinel: method definition (Callable = Muted Amber)
    // DX:SENTINEL rust.size.method
    // Sentinel: function declaration keyword (DxFunctionKeyword = Sky Blue)
    // DX:SENTINEL rust.fn.keyword
    // Sentinel: standard attribute (Meta = Dusty Pink)
    // DX:SENTINEL rust.must_use.attribute
    #[must_use]
    pub fn size(&self) -> u64 {
        // Sentinel: field access (self = Neutral Body, .size = Periwinkle)
        // DX:SENTINEL rust.size.field
        self.size
    }

    pub fn with_capacity<V>(initial: V) -> Self
    where
        V: Into<u64>,
    {
        Self {
            size: initial.into(),
            latency: Duration::from_millis(15),
            status: Status::Ready,
            metadata: HashMap::new(),
        }
    }
}

/// Sentinel: static lifetime specifier (Lifetime = Cyan)
// DX:SENTINEL rust.lifetime.static
pub const DEFAULT_TAG: &'static str = "stream_decoder";

/// Sentinel: lifetime generic parameter (Lifetime = Cyan)
// DX:SENTINEL rust.lifetime.param
pub struct FrameReader<'a> {
    pub buffer: &'a [u8],
}

impl<'a> FrameReader<'a> {
    pub fn read_len(&self) -> usize {
        self.buffer.len()
    }
}

/// Sentinel: async free function (Callable = Muted Amber, Parameters = Muted Violet-Gray)
// DX:SENTINEL rust.fetch_stream.fn
pub async fn fetch_stream<'a>(uri: &'a str, retries: u32) -> Result<DownloadSummary, String> {
    // DX:E3 rust.value.const_reference
    let initial_size: u64 = MAX_CAPACITY as u64;
    let mut summary = DownloadSummary::with_capacity(initial_size);

    println!("Starting fetch from {}", uri);

    let mut attempts = 0u32;
    // Sentinel: loop control-flow label (Label = Neutral Slate)
    // DX:SENTINEL rust.dispatch.label
    'dispatch: loop {
        attempts += 1;
        if attempts >= retries {
            break 'dispatch;
        }
    }

    let active_status = match retries {
        0 => Status::Ready,
        1..=5 => Status::Running,
        code => Status::Finished(code),
    };

    summary.status = active_status;
    Ok(summary)
}

fn main() {
    let target_uri = "https://example.com/stream";
    let count: u32 = 3;

    println!("Default tag: {}", DEFAULT_TAG);
    let sample = [1u8, 2, 3];
    let reader = FrameReader { buffer: &sample };
    println!("Reader len: {}", reader.read_len());

    let _future = fetch_stream(target_uri, count);
    let summary = DownloadSummary::with_capacity(1024u64);
    let binding_total = observe_binding_topology(count);
    println!("Initial summary size: {}, binding total: {}", summary.size(), binding_total);
}
