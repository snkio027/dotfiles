/**
 * @file main.cpp
 * @brief C++23 stress fixture for DX color contract validation.
 */

#include <concepts>
#include <cstdint>
#include <iostream>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace dx::network {

// Constant definition
inline constexpr std::size_t kDefaultBufferSize = 8192;

// Enum class
enum class ConnectionState : std::uint8_t {
    Disconnected = 0,
    Connecting = 1,
    Connected = 2,
    Failed = 3
};

// C++20/23 Concept
template <typename T>
concept Printable = requires(T val) {
    { std::cout << val } -> std::same_as<std::ostream&>;
};

// Type alias
using ByteVector = std::vector<std::uint8_t>;

// Data struct
struct Header {
    std::string key;
    std::string value;
};

// Class definition
class PacketDecoder {
public:
    explicit PacketDecoder(std::size_t max_payload)
        : max_payload_(max_payload), state_(ConnectionState::Disconnected) {}

    [[nodiscard]] constexpr std::size_t max_payload() const noexcept {
        return max_payload_;
    }

    [[nodiscard]] std::optional<Header> decode(std::string_view raw_header) {
        if (raw_header.empty()) {
            return std::nullopt;
        }
        // Member access: state_ is Member (Lavender)
        state_ = ConnectionState::Connected;
        return Header{
            .key = std::string(raw_header),
            .value = "application/json"
        };
    }

private:
    std::size_t max_payload_;
    ConnectionState state_;
};

// Template function with concept constraint and type parameter
template <Printable T>
void log_diagnostic(const T& message, std::uint32_t severity) {
    // Local variable (Neutral text)
    const double timestamp = 123.456;
    std::cout << "[" << timestamp << "] (" << severity << "): " << message << "\n";
}

} // namespace dx::network

int main() {
    using namespace dx::network;

    // Local variables
    const std::string sample_data = "Authorization: Bearer xyz";
    PacketDecoder decoder{kDefaultBufferSize};

    // Method call: decoder.decode() -> Yellow
    auto header = decoder.decode(sample_data);
    if (header.has_value()) {
        log_diagnostic(header->key, 1);
    }

    return 0;
}
