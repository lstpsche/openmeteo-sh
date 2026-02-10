# Homebrew formula for openmeteo-sh
# Package: openmeteo-sh  |  Binary: openmeteo
# Tap repo: lstpsche/homebrew-tap  →  brew tap lstpsche/tap
class OpenmeteoSh < Formula
  desc "Fast, lightweight CLI for the entire Open-Meteo API suite"
  homepage "https://github.com/lstpsche/openmeteo-sh"
  url "https://github.com/lstpsche/openmeteo-sh/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "ff17157410c9fbaaa544b8b1283c837449bd5a35db179112b3a494c87eaad9ce"
  license "MIT"
  head "https://github.com/lstpsche/openmeteo-sh.git", branch: "main"

  depends_on "jq"

  def install
    libexec.install "openmeteo"
    libexec.install "lib"
    libexec.install "commands"

    bin.install_symlink libexec/"openmeteo"

    bash_completion.install "completions/openmeteo.bash" => "openmeteo"
    zsh_completion.install  "completions/openmeteo.zsh"  => "_openmeteo"
  end

  test do
    assert_match "openmeteo #{version}", shell_output("#{bin}/openmeteo --version")
  end
end
