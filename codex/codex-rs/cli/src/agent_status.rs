use std::env;
use std::io::IsTerminal;
use std::path::Path;
use std::path::PathBuf;
use std::process::Stdio;
use std::time::Duration;

use serde_json::Value;
use tokio::process::Command;
use tokio::time::timeout;

const UNAVAILABLE: &str = "authentication status unavailable";

#[derive(Clone, Copy, Debug, clap::ValueEnum)]
pub(crate) enum ConnectProvider {
    Claude,
    Antigravity,
    Kimi,
    Mimo,
    Copilot,
}

impl ConnectProvider {
    fn executable(self) -> &'static str {
        match self {
            Self::Claude => "claude",
            Self::Antigravity => "agy",
            Self::Kimi => "kimi",
            Self::Mimo => "mimo",
            Self::Copilot => "copilot",
        }
    }

    fn login_args(self) -> &'static [&'static str] {
        match self {
            Self::Claude => &["auth", "login"],
            Self::Antigravity => &["acp", "--login"],
            Self::Kimi | Self::Copilot => &["login"],
            Self::Mimo => &["auth", "login"],
        }
    }

    pub(crate) async fn connect(self) -> anyhow::Result<()> {
        anyhow::ensure!(
            std::io::stdin().is_terminal(),
            "agent sign-in requires a terminal"
        );
        let home = env::home_dir().ok_or_else(|| anyhow::anyhow!("home directory unavailable"))?;
        let binary = match find_binary(&home, self) {
            Some(binary) => binary,
            None => {
                self.install(&home).await?;
                find_binary(&home, self).ok_or_else(|| {
                    anyhow::anyhow!(
                        "official installer did not make {} available",
                        self.executable()
                    )
                })?
            }
        };
        if matches!(self, Self::Mimo) {
            eprintln!("Choose Token Plan in MiMo's authorization screen to use your subscription.");
        }
        let status = Command::new(binary)
            .args(self.login_args())
            .current_dir(home)
            .kill_on_drop(true)
            .status()
            .await?;
        anyhow::ensure!(
            status.success(),
            "official agent sign-in exited with {status}"
        );
        Ok(())
    }

    async fn install(self, home: &Path) -> anyhow::Result<()> {
        anyhow::ensure!(
            cfg!(any(target_os = "macos", target_os = "linux")),
            "automatic installation is available on macOS and Linux; install the official CLI first"
        );
        let (url, args): (&str, &[&str]) = match self {
            Self::Claude => ("https://claude.ai/install.sh", &["stable"]),
            Self::Antigravity => ("https://antigravity.google/cli/install.sh", &[]),
            Self::Kimi => ("https://code.kimi.com/kimi-code/install.sh", &[]),
            Self::Mimo => ("https://mimo.xiaomi.com/install", &["--no-modify-path"]),
            Self::Copilot => ("https://gh.io/copilot-install", &[]),
        };
        let script = tempfile::NamedTempFile::new()?;
        eprintln!(
            "Installing {} from its official distribution channel",
            self.executable()
        );
        let status = Command::new("/usr/bin/curl")
            .args([
                "-q",
                "--proto",
                "=https",
                "--proto-redir",
                "=https",
                "--fail",
                "--silent",
                "--show-error",
                "--location",
                "--max-time",
                "60",
                "--output",
            ])
            .arg(script.path())
            .arg(url)
            .current_dir(home)
            .kill_on_drop(true)
            .status()
            .await?;
        anyhow::ensure!(
            status.success(),
            "official installer download failed with {status}"
        );
        let mut installer = Command::new("/bin/bash");
        if matches!(self, Self::Kimi) {
            installer
                .env("KIMI_INSTALL_DIR", home.join(".kimi-code"))
                .env("KIMI_NO_MODIFY_PATH", "1");
        }
        if matches!(self, Self::Copilot) {
            installer.env("PREFIX", home.join(".local"));
        }
        let status = installer
            .arg(script.path())
            .args(args)
            .current_dir(home)
            .kill_on_drop(true)
            .status()
            .await?;
        anyhow::ensure!(status.success(), "official installer exited with {status}");
        Ok(())
    }
}

pub(crate) fn find_binary(home: &Path, provider: ConnectProvider) -> Option<PathBuf> {
    let executable = provider.executable();
    let directory = match provider {
        ConnectProvider::Kimi => ".kimi-code/bin",
        ConnectProvider::Mimo => ".mimocode/bin",
        _ => ".local/bin",
    };
    let native = home.join(directory).join(executable);
    if cfg!(unix) && native.is_file() {
        return Some(native);
    }
    let path = env::var_os("PATH")?;
    let path = env::join_paths(env::split_paths(&path).filter(|entry| entry.is_absolute())).ok()?;
    if path.is_empty() {
        return None;
    }
    which::which_in_global(executable, Some(&path)).ok()?.next()
}

pub(crate) async fn claude_status() -> &'static str {
    let Some(home) = env::home_dir() else {
        return UNAVAILABLE;
    };
    let Some(binary) = find_binary(&home, ConnectProvider::Claude) else {
        return "CLI not found";
    };

    // Probe from outside the project so its Claude configuration is not loaded.
    // Keep provider output private, including diagnostics and account metadata.
    let mut command = Command::new(binary);
    command
        .args(["auth", "status"])
        .current_dir(home)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .kill_on_drop(true);
    match timeout(Duration::from_secs(5), command.output()).await {
        Ok(Ok(output)) => classify(output.status.code(), &output.stdout),
        _ => UNAVAILABLE,
    }
}

fn classify(exit_code: Option<i32>, stdout: &[u8]) -> &'static str {
    let Ok(status) = serde_json::from_slice::<Value>(stdout) else {
        return UNAVAILABLE;
    };
    match (exit_code, status["authMethod"].as_str()) {
        (Some(0), Some("claude.ai")) => "Claude account login detected",
        (Some(1), Some("none")) => "signed out",
        (Some(0), Some("oauth_token" | "api_key" | "api_key_helper" | "third_party")) => {
            "alternate authentication detected"
        }
        _ => UNAVAILABLE,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reports_only_known_authentication_states() {
        assert_eq!(
            classify(
                Some(0),
                br#"{"authMethod":"claude.ai","email":"private@example.com"}"#
            ),
            "Claude account login detected"
        );
        assert_eq!(classify(Some(1), br#"{"authMethod":"none"}"#), "signed out");
        for method in ["oauth_token", "api_key", "api_key_helper", "third_party"] {
            let response = serde_json::json!({"authMethod": method}).to_string();
            assert_eq!(
                classify(Some(0), response.as_bytes()),
                "alternate authentication detected"
            );
        }
    }

    #[test]
    fn ambiguous_or_failed_probes_do_not_claim_login() {
        for (code, output) in [
            (Some(0), "invalid JSON"),
            (Some(0), r#"{"authMethod":"future"}"#),
            (Some(1), r#"{"authMethod":"claude.ai"}"#),
            (Some(0), r#"{"authMethod":"none"}"#),
            (None, r#"{"authMethod":"claude.ai"}"#),
        ] {
            assert_eq!(classify(code, output.as_bytes()), UNAVAILABLE);
        }
    }
}
