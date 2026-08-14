#pragma once
#include <optional>
#include <string>
#include <utility>
namespace ftnl {
class FtnlClient final {
 public:
  explicit FtnlClient(std::string base_url, std::optional<std::string> bearer_token = std::nullopt)
      : base_url_(std::move(base_url)), bearer_token_(std::move(bearer_token)) {}
  [[nodiscard]] bool health() const noexcept { return !base_url_.empty(); }
 private:
  std::string base_url_;
  std::optional<std::string> bearer_token_;
};
}
