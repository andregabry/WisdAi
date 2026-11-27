use std::collections::BTreeMap;
use std::fs;
use std::io::IsTerminal;
use std::io::Read;
use std::io::Write;
use std::path::Component;
use std::path::Path;
use std::path::PathBuf;
use std::process::Command;
use std::process::Stdio;

use anyhow::Context;
use codex_core::config::ConfigBuilder;
use codex_core::config::ConfigOverrides;
use codex_mcp::SandboxState;
use codex_protocol::models::PermissionProfile;
use codex_protocol::permissions::FileSystemAccessMode;
use codex_protocol::permissions::FileSystemPath;
use codex_protocol::permissions::FileSystemSandboxEntry;
use codex_protocol::permissions::NetworkSandboxPolicy;
use codex_utils_absolute_path::AbsolutePathBuf;
use codex_utils_cli::CliConfigOverrides;
use codex_utils_path_uri::PathUri;
use serde::Deserialize;
use serde::Serialize;
use sha2::Digest;
use sha2::Sha256;

const VERSION: u32 = 1;
const MAX_CONTEXT_BYTES: u64 = 256 * 1024;

#[derive(Debug, clap::Subcommand)]
pub(crate) enum Action {
    /// Save reviewed task context and the current Git state to a new file.
    Save {
        #[arg(long)]
        context: PathBuf,
        #[arg(long)]
        output: PathBuf,
    },
    /// Confirm that the current project still matches a saved checkpoint.
    Verify { checkpoint: PathBuf },
    /// Export reviewed task context for an external agent after verifying the project.
    Export { checkpoint: PathBuf },
    /// Copy the verified working files to a new private staging directory.
    Stage {
        checkpoint: PathBuf,
        /// Existing parent directory outside the source repository.
        #[arg(long)]
        parent: PathBuf,
    },
    /// Open a verified checkpoint in the official Antigravity CLI on macOS.
    Handoff {
        checkpoint: PathBuf,
        /// Existing parent directory outside the source repository.
        #[arg(long)]
        parent: PathBuf,
    },
    /// Inspect changes made inside a staging directory relative to a verified checkpoint.
    ReviewStaged {
        checkpoint: PathBuf,
        /// Existing staging directory outside the source repository.
        #[arg(long)]
        staging: PathBuf,
    },
    /// Apply reviewed staging changes back to the source repository under Codex policy and explicit approval.
    Promote {
        checkpoint: PathBuf,
        /// Existing staging directory outside the source repository.
        #[arg(long)]
        staging: PathBuf,
        /// Exact staging digest printed by `review-staged` to confirm non-interactive approval.
        #[arg(long)]
        approve_digest: Option<String>,
        /// Optional path outside the repository to save an updated checkpoint after promotion.
        #[arg(long)]
        output: Option<PathBuf>,
    },
    /// Verify a checkpoint and run a local check without an inference call.
    Validate {
        checkpoint: PathBuf,
        /// Write a new checkpoint containing the successful validation receipt.
        #[arg(long)]
        output: PathBuf,
        /// Explicit test program and arguments after '--'.
        #[arg(last = true, required = true, num_args = 1..)]
        command: Vec<String>,
    },
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct TaskContext {
    objective: String,
    conversation_summary: String,
    completed: Vec<String>,
    pending: Vec<String>,
    test_results: Vec<String>,
}

#[derive(Deserialize, Serialize)]
struct Checkpoint {
    version: u32,
    repository: RepositoryState,
    task: TaskContext,
}

#[derive(Debug, Deserialize, Eq, PartialEq, Serialize)]
struct RepositoryState {
    root: PathBuf,
    head: String,
    branch: String,
    status: String,
    digest: String,
}

impl Action {
    pub(crate) async fn run(self, overrides: &CliConfigOverrides) -> anyhow::Result<()> {
        let cwd = std::env::current_dir()?;
        match self {
            Self::Save { context, output } => {
                let task: TaskContext = serde_json::from_slice(&read_document(&context)?)
                    .context("invalid checkpoint task context")?;
                anyhow::ensure!(!task.objective.trim().is_empty(), "task objective is empty");
                let repository = RepositoryState::capture(&cwd)?;
                Checkpoint {
                    version: VERSION,
                    repository,
                    task,
                }
                .save(&output)?;
                println!("Agent checkpoint saved.");
            }
            Self::Verify { checkpoint } => {
                Checkpoint::load_verified(&checkpoint, &cwd)?;
                println!("Agent checkpoint matches the current repository.");
            }
            Self::Export { checkpoint } => {
                let checkpoint = Checkpoint::load_verified(&checkpoint, &cwd)?;
                serde_json::to_writer_pretty(std::io::stdout().lock(), &checkpoint.task)?;
                println!();
            }
            Self::Stage { checkpoint, parent } => {
                let checkpoint = Checkpoint::load_verified(&checkpoint, &cwd)?;
                let staged = checkpoint.repository.stage(&parent)?;
                println!("{}", staged.display());
            }
            Self::Handoff { checkpoint, parent } => {
                let checkpoint = Checkpoint::load_verified(&checkpoint, &cwd)?;
                checkpoint.handoff(&parent).await?;
            }
            Self::ReviewStaged { checkpoint, staging } => {
                let checkpoint = Checkpoint::load_verified(&checkpoint, &cwd)?;
                let staging_root = validate_staging_root(&checkpoint.repository.root, &staging)?;
                let plan = StagingPatchPlan::build(&checkpoint.repository.root, &staging_root)?;
                print_staging_review(&checkpoint.repository.root, &staging_root, &plan)?;
            }
            Self::Promote {
                checkpoint: checkpoint_path,
                staging,
                approve_digest,
                output,
            } => {
                let mut checkpoint = Checkpoint::load_verified(&checkpoint_path, &cwd)?;
                let staging_root = validate_staging_root(&checkpoint.repository.root, &staging)?;
                let plan = StagingPatchPlan::build(&checkpoint.repository.root, &staging_root)?;
                let output_parent = match output.as_deref() {
                    Some(path) => {
                        let parent = checkpoint.output_parent(path)?;
                        anyhow::ensure!(!path.exists(), "promotion checkpoint output already exists");
                        Some(parent)
                    }
                    None => None,
                };
                checkpoint
                    .promote(
                        &checkpoint_path,
                        &cwd,
                        &staging_root,
                        &plan,
                        approve_digest.as_deref(),
                        overrides,
                    )
                    .await?;
                if let (Some(path), Some(parent)) = (output.as_deref(), output_parent.as_deref()) {
                    checkpoint.repository = RepositoryState::capture(&checkpoint.repository.root)?;
                    checkpoint.task.completed.push(format!(
                        "Promoted reviewed staging changes (staging digest: {}).",
                        plan.digest
                    ));
                    checkpoint.write(path, parent)?;
                    println!(
                        "Promoted staged changes and saved updated checkpoint to {}.",
                        path.display()
                    );
                } else {
                    println!("Promoted staged changes to {}.", checkpoint.repository.root.display());
                }
            }
            Self::Validate {
                checkpoint,
                output,
                command,
            } => {
                let mut checkpoint = Checkpoint::load_verified(&checkpoint, &cwd)?;
                let parent = checkpoint.output_parent(&output)?;
                anyhow::ensure!(!output.exists(), "validation output already exists");
                checkpoint.validate(&command, overrides).await?;
                checkpoint.write(&output, &parent)?;
                println!("Local validation passed and a new checkpoint was saved.");
            }
        }
        Ok(())
    }
}

impl Checkpoint {
    fn load_verified(path: &Path, cwd: &Path) -> anyhow::Result<Self> {
        let checkpoint: Self =
            serde_json::from_slice(&read_document(path)?).context("invalid agent checkpoint")?;
        anyhow::ensure!(
            checkpoint.version == VERSION,
            "unsupported checkpoint version"
        );
        anyhow::ensure!(
            checkpoint.repository == RepositoryState::capture(cwd)?,
            "repository state differs from the checkpoint"
        );
        Ok(checkpoint)
    }

    fn output_parent(&self, output: &Path) -> anyhow::Result<PathBuf> {
        let parent = output
            .parent()
            .filter(|path| !path.as_os_str().is_empty())
            .unwrap_or(Path::new("."))
            .canonicalize()?;
        anyhow::ensure!(
            !parent.starts_with(&self.repository.root),
            "write the checkpoint outside the repository"
        );
        Ok(parent)
    }

    fn save(&self, output: &Path) -> anyhow::Result<()> {
        self.write(output, &self.output_parent(output)?)
    }

    fn write(&self, output: &Path, parent: &Path) -> anyhow::Result<()> {
        let payload = serde_json::to_vec_pretty(self)?;
        anyhow::ensure!(
            payload.len() as u64 <= MAX_CONTEXT_BYTES,
            "checkpoint is too large"
        );
        let mut file = tempfile::NamedTempFile::new_in(parent)?;
        file.write_all(&payload)?;
        file.as_file().sync_all()?;
        file.persist_noclobber(output)?;
        Ok(())
    }

    async fn handoff(&self, parent: &Path) -> anyhow::Result<()> {
        anyhow::ensure!(
            cfg!(target_os = "macos"),
            "experimental handoff requires macOS"
        );
        anyhow::ensure!(
            std::io::stdin().is_terminal() && std::io::stdout().is_terminal(),
            "Antigravity handoff requires an interactive terminal"
        );
        let home = std::env::home_dir().context("home directory unavailable")?;
        let binary = crate::agent_status::find_binary(
            &home,
            crate::agent_status::ConnectProvider::Antigravity,
        )
        .context("Antigravity CLI unavailable; run codex agent-connect antigravity")?;
        let staging = self.repository.stage(parent)?;
        eprintln!("Antigravity staging directory: {}", staging.display());
        let context = staging.join(".wisdcode-task.json");
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(context)?;
        serde_json::to_writer_pretty(&mut file, &self.task)?;
        drop(file);
        let root = AbsolutePathBuf::from_absolute_path(&staging)?;
        let source = AbsolutePathBuf::from_absolute_path(&self.repository.root)?;
        let network = NetworkSandboxPolicy::Enabled;
        let mut filesystem = PermissionProfile::workspace_write_with(
            std::slice::from_ref(&root),
            network,
            /*exclude_tmpdir_env_var*/ true,
            /*exclude_slash_tmp*/ true,
        )
        .file_system_sandbox_policy();
        filesystem.entries.push(FileSystemSandboxEntry::new(
            FileSystemPath::Path {
                path: PathUri::from_abs_path(&source),
            },
            FileSystemAccessMode::Deny,
        ));
        // The native client persists its session outside the project. Grant
        // only its operational directories, keeping settings and auth read-only.
        let data = home.canonicalize()?.join(".gemini/antigravity-cli");
        for directory in [
            "log",
            "crashes",
            "cache",
            "conversations",
            "brain",
            "presence",
            "annotations",
        ] {
            let path = data.join(directory);
            fs::create_dir_all(&path)?;
            anyhow::ensure!(
                path.canonicalize()? == path
                    && !path.starts_with(&self.repository.root)
                    && !self.repository.root.starts_with(&path),
                "Antigravity runtime directory overlaps protected paths or contains a symlink"
            );
            let path = AbsolutePathBuf::from_absolute_path(path)?;
            filesystem.entries.push(FileSystemSandboxEntry::new(
                FileSystemPath::Path {
                    path: PathUri::from_abs_path(&path),
                },
                FileSystemAccessMode::Write,
            ));
        }
        let state = SandboxState {
            permission_profile: PermissionProfile::from_runtime_permissions(&filesystem, network),
            codex_linux_sandbox_exe: None,
            sandbox_cwd: PathUri::from_abs_path(&root),
            use_legacy_landlock: false,
            use_mxc: false,
        };
        let status = tokio::process::Command::new(std::env::current_exe()?)
            .args(["sandbox", "--sandbox-state-json"])
            .arg(serde_json::to_string(&state)?)
            .arg("--")
            .arg(binary)
            .args([
                "--sandbox",
                "--mode=accept-edits",
                "--prompt-interactive",
                "Read .wisdcode-task.json for the reviewed task context. Continue pending work in this staging directory and preserve completed work.",
            ])
            .env_remove("GEMINI_API_KEY")
            .env_remove("GOOGLE_API_KEY")
            .env_remove("AGY_ADC_AUTH")
            .current_dir(&staging)
            .kill_on_drop(true)
            .status()
            .await?;
        anyhow::ensure!(status.success(), "Antigravity exited with {status}");
        anyhow::ensure!(
            self.repository == RepositoryState::capture(&self.repository.root)?,
            "source project changed during handoff; changes remain in staging"
        );
        println!("Antigravity exited. Review the staged changes before applying them.");
        Ok(())
    }

    async fn validate(
        &mut self,
        command: &[String],
        overrides: &CliConfigOverrides,
    ) -> anyhow::Result<()> {
        anyhow::ensure!(cfg!(unix), "checkpoint validation requires a Unix sandbox");
        let config = ConfigBuilder::default()
            .cli_overrides(overrides.parse_overrides().map_err(anyhow::Error::msg)?)
            .harness_overrides(ConfigOverrides {
                cwd: Some(self.repository.root.clone()),
                ..Default::default()
            })
            .build()
            .await?;
        let permission_profile = config
            .permissions
            .effective_permission_profile()
            .intersect_with_read_only()
            .context("the active sandbox policy cannot be enforced by local validation")?;
        let root = AbsolutePathBuf::from_absolute_path(&self.repository.root)?;
        let state = SandboxState {
            permission_profile,
            codex_linux_sandbox_exe: None,
            sandbox_cwd: PathUri::from_abs_path(&root),
            use_legacy_landlock: config.features.use_legacy_landlock(),
            use_mxc: false,
        };
        let mut launcher = tokio::process::Command::new(std::env::current_exe()?);
        for setting in &overrides.raw_overrides {
            launcher.arg("-c").arg(setting);
        }
        let status = launcher
            .args(["sandbox", "--sandbox-state-json"])
            .arg(serde_json::to_string(&state)?)
            .args(["--sandbox-state-disable-network", "--"])
            .args(command)
            .current_dir(&self.repository.root)
            .stdin(Stdio::null())
            .kill_on_drop(true)
            .status()
            .await?;
        anyhow::ensure!(status.success(), "local validation failed with {status}");
        anyhow::ensure!(
            self.repository == RepositoryState::capture(&self.repository.root)?,
            "repository changed during validation"
        );
        let mut digest = Sha256::new();
        for arg in command {
            hash_field(&mut digest, arg.as_bytes());
        }
        self.task.test_results.push(format!(
            "Sandboxed local validation passed (command digest: {:x}).",
            digest.finalize()
        ));
        Ok(())
    }

    async fn promote(
        &self,
        checkpoint_path: &Path,
        cwd: &Path,
        staging_root: &Path,
        plan: &StagingPatchPlan,
        approve_digest: Option<&str>,
        overrides: &CliConfigOverrides,
    ) -> anyhow::Result<()> {
        self.promote_with_confirm(
            checkpoint_path,
            cwd,
            staging_root,
            plan,
            approve_digest,
            overrides,
            || prompt_promotion_approval(&self.repository.root, plan),
        )
        .await
    }

    async fn promote_with_confirm(
        &self,
        checkpoint_path: &Path,
        cwd: &Path,
        staging_root: &Path,
        plan: &StagingPatchPlan,
        approve_digest: Option<&str>,
        overrides: &CliConfigOverrides,
        confirm: impl FnOnce() -> anyhow::Result<bool>,
    ) -> anyhow::Result<()> {
        check_promotion_policy(&self.repository.root, plan, overrides).await?;
        if let Some(expected) = approve_digest {
            anyhow::ensure!(
                expected.eq_ignore_ascii_case(&plan.digest),
                "staging digest mismatch; review staged changes again before promoting"
            );
        } else {
            anyhow::ensure!(
                confirm()?,
                "promotion cancelled; source repository unchanged"
            );
        }
        if plan.changes.is_empty() {
            return Ok(());
        }
        let rechecked = Self::load_verified(checkpoint_path, cwd)?;
        anyhow::ensure!(
            rechecked.repository == self.repository,
            "repository state changed before promotion; aborted"
        );
        let rechecked_plan = StagingPatchPlan::build(&self.repository.root, staging_root)?;
        anyhow::ensure!(
            rechecked_plan.digest == plan.digest,
            "staging directory changed after approval; promotion aborted"
        );
        apply_staging_plan(&self.repository.root, staging_root, &rechecked_plan)
    }
}

impl RepositoryState {
    fn stage(&self, parent: &Path) -> anyhow::Result<PathBuf> {
        let parent = parent.canonicalize()?;
        anyhow::ensure!(
            !parent.starts_with(&self.root),
            "stage the checkpoint outside the repository"
        );
        let directory = tempfile::Builder::new()
            .prefix("wisdcode-stage-")
            .tempdir_in(parent)?;
        let files = git(
            &self.root,
            &[
                "ls-files",
                "-z",
                "--cached",
                "--others",
                "--exclude-standard",
                "--deduplicate",
            ],
        )?;
        for name in files
            .split(|byte| *byte == 0)
            .filter(|name| !name.is_empty())
        {
            let path = Path::new(std::str::from_utf8(name).context("non-UTF-8 staging path")?);
            anyhow::ensure!(
                path.components().all(|part| {
                    matches!(part, Component::Normal(name) if !name.to_string_lossy().eq_ignore_ascii_case(".git"))
                }),
                "unsupported staging path"
            );
            let source = self.root.join(path);
            let metadata = match source.symlink_metadata() {
                Ok(metadata) => metadata,
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
                Err(error) => return Err(error.into()),
            };
            anyhow::ensure!(
                metadata.is_file() && source.canonicalize()? == source,
                "staging only supports regular files without symlinks"
            );
            let destination = directory.path().join(path);
            fs::create_dir_all(destination.parent().context("staging path has no parent")?)?;
            fs::copy(source, destination)?;
        }
        anyhow::ensure!(
            self == &Self::capture(&self.root)?,
            "repository changed while staging the checkpoint"
        );
        Ok(directory.keep())
    }

    fn capture(cwd: &Path) -> anyhow::Result<Self> {
        let root =
            PathBuf::from(git_text(cwd, &["rev-parse", "--show-toplevel"])?).canonicalize()?;
        let head = git_text(&root, &["rev-parse", "--verify", "HEAD"])?;
        let branch = git_text(&root, &["rev-parse", "--abbrev-ref", "HEAD"])?;
        let status_args = ["status", "--porcelain=v1", "-z", "--untracked-files=all"];
        let status = git(&root, &status_args)?;
        let mut digest = Sha256::new();
        for args in [
            &[
                "diff",
                "--no-ext-diff",
                "--no-textconv",
                "--binary",
                "--no-color",
                "--",
            ][..],
            &[
                "diff",
                "--cached",
                "--no-ext-diff",
                "--no-textconv",
                "--binary",
                "--no-color",
                "--",
            ][..],
        ] {
            hash_field(&mut digest, &git(&root, args)?);
        }
        let untracked = git(&root, &["ls-files", "-z", "--others", "--exclude-standard"])?;
        for name in untracked
            .split(|byte| *byte == 0)
            .filter(|name| !name.is_empty())
        {
            let relative =
                Path::new(std::str::from_utf8(name).context("non-UTF-8 untracked path")?);
            let path = root.join(relative);
            let metadata = path.symlink_metadata()?;
            let parent = path
                .parent()
                .context("untracked path has no parent")?
                .canonicalize()?;
            anyhow::ensure!(
                relative.is_relative() && parent.starts_with(&root),
                "untracked path escapes repository"
            );
            hash_field(&mut digest, name);
            if metadata.is_symlink() {
                hash_field(&mut digest, b"symlink");
                hash_field(
                    &mut digest,
                    path.read_link()?.as_os_str().as_encoded_bytes(),
                );
            } else {
                anyhow::ensure!(metadata.is_file(), "unsupported untracked file type");
                hash_field(&mut digest, b"file");
                let mut file_hash = Sha256::new();
                std::io::copy(&mut fs::File::open(path)?, &mut file_hash)?;
                hash_field(&mut digest, &file_hash.finalize());
            }
        }
        anyhow::ensure!(
            status == git(&root, &status_args)?
                && head == git_text(&root, &["rev-parse", "--verify", "HEAD"])?
                && branch == git_text(&root, &["rev-parse", "--abbrev-ref", "HEAD"])?,
            "repository changed while capturing the checkpoint"
        );
        Ok(Self {
            root,
            head,
            branch,
            status: String::from_utf8(status)?,
            digest: format!("{digest:x}", digest = digest.finalize()),
        })
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum StagedChangeKind {
    Added,
    Modified,
    Deleted,
}

impl StagedChangeKind {
    fn tag(self) -> &'static [u8] {
        match self {
            Self::Added => b"add",
            Self::Modified => b"modify",
            Self::Deleted => b"delete",
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::Added => "added",
            Self::Modified => "modified",
            Self::Deleted => "deleted",
        }
    }
}

#[derive(Debug, Eq, PartialEq)]
struct StagedChange {
    path: PathBuf,
    kind: StagedChangeKind,
}

#[derive(Debug)]
struct StagingPatchPlan {
    changes: Vec<StagedChange>,
    digest: String,
}

impl StagingPatchPlan {
    fn build(source_root: &Path, staging_root: &Path) -> anyhow::Result<Self> {
        let source_files = collect_source_files(source_root)?;
        let staging_files = collect_staging_files(staging_root, &source_files)?;
        let mut changes = Vec::new();
        let mut digest = Sha256::new();

        for (path, staged_hash) in &staging_files {
            match source_files.get(path) {
                None => {
                    changes.push(StagedChange {
                        path: path.clone(),
                        kind: StagedChangeKind::Added,
                    });
                    hash_field(&mut digest, StagedChangeKind::Added.tag());
                    hash_field(&mut digest, path.as_os_str().as_encoded_bytes());
                    hash_field(&mut digest, staged_hash);
                }
                Some(source_hash) if source_hash != staged_hash => {
                    changes.push(StagedChange {
                        path: path.clone(),
                        kind: StagedChangeKind::Modified,
                    });
                    hash_field(&mut digest, StagedChangeKind::Modified.tag());
                    hash_field(&mut digest, path.as_os_str().as_encoded_bytes());
                    hash_field(&mut digest, source_hash);
                    hash_field(&mut digest, staged_hash);
                }
                Some(_) => {}
            }
        }

        for (path, source_hash) in &source_files {
            if !staging_files.contains_key(path) {
                changes.push(StagedChange {
                    path: path.clone(),
                    kind: StagedChangeKind::Deleted,
                });
                hash_field(&mut digest, StagedChangeKind::Deleted.tag());
                hash_field(&mut digest, path.as_os_str().as_encoded_bytes());
                hash_field(&mut digest, source_hash);
            }
        }

        Ok(Self {
            changes,
            digest: format!("{digest:x}", digest = digest.finalize()),
        })
    }
}

fn validate_staging_root(source_root: &Path, staging: &Path) -> anyhow::Result<PathBuf> {
    let metadata = fs::symlink_metadata(staging).context("staging directory unavailable")?;
    anyhow::ensure!(
        !metadata.is_symlink() && metadata.is_dir(),
        "staging path must be a non-symlink directory"
    );
    let canonical = staging.canonicalize()?;
    anyhow::ensure!(
        !canonical.starts_with(source_root) && !source_root.starts_with(&canonical),
        "staging directory must stay outside the source repository"
    );
    Ok(canonical)
}

fn validate_relative_path(relative: &Path) -> anyhow::Result<()> {
    anyhow::ensure!(!relative.as_os_str().is_empty(), "empty relative path");
    anyhow::ensure!(
        relative.components().all(|part| {
            matches!(part, Component::Normal(name) if !name.to_string_lossy().eq_ignore_ascii_case(".git"))
        }),
        "unsupported or protected path component"
    );
    Ok(())
}

fn sha256_file(path: &Path) -> anyhow::Result<[u8; 32]> {
    let mut digest = Sha256::new();
    std::io::copy(&mut fs::File::open(path)?, &mut digest)?;
    Ok(digest.finalize().into())
}

fn collect_source_files(root: &Path) -> anyhow::Result<BTreeMap<PathBuf, [u8; 32]>> {
    let files = git(
        root,
        &[
            "ls-files",
            "-z",
            "--cached",
            "--others",
            "--exclude-standard",
            "--deduplicate",
        ],
    )?;
    let mut map = BTreeMap::new();
    for name in files
        .split(|byte| *byte == 0)
        .filter(|name| !name.is_empty())
    {
        let path = Path::new(std::str::from_utf8(name).context("non-UTF-8 source path")?);
        validate_relative_path(path)?;
        let source = root.join(path);
        let metadata = match source.symlink_metadata() {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
            Err(error) => return Err(error.into()),
        };
        anyhow::ensure!(
            metadata.is_file() && source.canonicalize()? == source,
            "source snapshot only supports regular files without symlinks"
        );
        map.insert(path.to_path_buf(), sha256_file(&source)?);
    }
    Ok(map)
}

fn collect_staging_files(
    staging_root: &Path,
    source_files: &BTreeMap<PathBuf, [u8; 32]>,
) -> anyhow::Result<BTreeMap<PathBuf, [u8; 32]>> {
    let mut map = BTreeMap::new();
    let mut stack = vec![staging_root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let mut entries = fs::read_dir(&dir)?
            .collect::<std::io::Result<Vec<_>>>()?;
        entries.sort_by_key(|entry| entry.file_name());
        for entry in entries {
            let path = entry.path();
            let metadata = fs::symlink_metadata(&path)?;
            anyhow::ensure!(
                !metadata.is_symlink(),
                "staging contains an unsupported symlink: {}",
                path.display()
            );
            let relative = path
                .strip_prefix(staging_root)
                .context("staging entry escaped staging root")?;
            let relative_str = relative.to_str().context("non-UTF-8 staging path")?;
            validate_relative_path(Path::new(relative_str))?;
            if metadata.is_dir() {
                stack.push(path);
            } else {
                anyhow::ensure!(
                    metadata.is_file(),
                    "staging contains an unsupported file type: {}",
                    path.display()
                );
                if relative == Path::new(".wisdcode-task.json")
                    && !source_files.contains_key(relative)
                {
                    continue;
                }
                map.insert(relative.to_path_buf(), sha256_file(&path)?);
            }
        }
    }
    Ok(map)
}

async fn check_promotion_policy(
    source_root: &Path,
    plan: &StagingPatchPlan,
    overrides: &CliConfigOverrides,
) -> anyhow::Result<()> {
    let config = ConfigBuilder::default()
        .cli_overrides(overrides.parse_overrides().map_err(anyhow::Error::msg)?)
        .harness_overrides(ConfigOverrides {
            cwd: Some(source_root.to_path_buf()),
            ..Default::default()
        })
        .build()
        .await?;
    let fs_policy = config.permissions.file_system_sandbox_policy();
    if plan.changes.is_empty() {
        anyhow::ensure!(
            fs_policy.can_write_local_path_with_cwd(source_root, source_root),
            "active Codex sandbox policy is read-only"
        );
        return Ok(());
    }
    for change in &plan.changes {
        let target = source_root.join(&change.path);
        anyhow::ensure!(
            fs_policy.can_write_local_path_with_cwd(&target, source_root),
            "active Codex sandbox policy denies writing {}",
            change.path.display()
        );
    }
    Ok(())
}

fn verify_destination_no_symlinks(root: &Path, relative: &Path) -> anyhow::Result<()> {
    validate_relative_path(relative)?;
    let mut cursor = root.to_path_buf();
    let components: Vec<_> = relative.components().collect();
    for (index, component) in components.iter().enumerate() {
        cursor.push(component.as_os_str());
        let is_last = index + 1 == components.len();
        match fs::symlink_metadata(&cursor) {
            Ok(metadata) => {
                anyhow::ensure!(
                    !metadata.is_symlink(),
                    "destination path crosses a symlink: {}",
                    cursor.display()
                );
                if is_last {
                    anyhow::ensure!(
                        metadata.is_file(),
                        "destination is not a regular file: {}",
                        cursor.display()
                    );
                } else {
                    anyhow::ensure!(
                        metadata.is_dir(),
                        "destination parent is not a directory: {}",
                        cursor.display()
                    );
                }
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
            Err(error) => return Err(error.into()),
        }
    }
    Ok(())
}

fn apply_staging_plan(
    source_root: &Path,
    staging_root: &Path,
    plan: &StagingPatchPlan,
) -> anyhow::Result<()> {
    for change in &plan.changes {
        verify_destination_no_symlinks(source_root, &change.path)?;
    }
    for change in &plan.changes {
        let dest = source_root.join(&change.path);
        match change.kind {
            StagedChangeKind::Added | StagedChangeKind::Modified => {
                let staged = staging_root.join(&change.path);
                let parent = dest.parent().context("destination path has no parent")?;
                fs::create_dir_all(parent)?;
                let canonical_parent = parent.canonicalize()?;
                anyhow::ensure!(
                    canonical_parent == parent && canonical_parent.starts_with(source_root),
                    "destination parent escaped repository"
                );
                let mut temp = tempfile::NamedTempFile::new_in(parent)?;
                let mut src_file = fs::File::open(&staged)?;
                std::io::copy(&mut src_file, &mut temp)?;
                temp.as_file().sync_all()?;
                temp.persist(&dest).map_err(|err| err.error)?;
            }
            StagedChangeKind::Deleted => {
                fs::remove_file(&dest)?;
            }
        }
    }
    Ok(())
}

fn prompt_promotion_approval(root: &Path, plan: &StagingPatchPlan) -> anyhow::Result<bool> {
    anyhow::ensure!(
        std::io::stdin().is_terminal() && std::io::stdout().is_terminal(),
        "explicit approval (--approve-digest) or an interactive terminal is required to promote staged changes"
    );
    print_staging_summary(plan);
    print!(
        "Apply {} staged change(s) to {}? [y/N] ",
        plan.changes.len(),
        root.display()
    );
    std::io::stdout().flush()?;
    let mut answer = String::new();
    std::io::stdin().read_line(&mut answer)?;
    let trimmed = answer.trim();
    Ok(trimmed.eq_ignore_ascii_case("y") || trimmed.eq_ignore_ascii_case("yes"))
}

fn print_staging_summary(plan: &StagingPatchPlan) {
    if plan.changes.is_empty() {
        println!("No differences between staging and checkpoint.");
    } else {
        for change in &plan.changes {
            println!("  {}: {}", change.kind.label(), change.path.display());
        }
    }
    println!("Staging digest: {}", plan.digest);
}

fn print_staging_review(
    source_root: &Path,
    staging_root: &Path,
    plan: &StagingPatchPlan,
) -> anyhow::Result<()> {
    print_staging_summary(plan);
    for change in &plan.changes {
        let old = match change.kind {
            StagedChangeKind::Added => PathBuf::from("/dev/null"),
            StagedChangeKind::Modified | StagedChangeKind::Deleted => source_root.join(&change.path),
        };
        let new = match change.kind {
            StagedChangeKind::Deleted => PathBuf::from("/dev/null"),
            StagedChangeKind::Added | StagedChangeKind::Modified => staging_root.join(&change.path),
        };
        let output = Command::new("git")
            .args([
                "-c",
                "core.fsmonitor=false",
                "-c",
                "core.hooksPath=/dev/null",
                "diff",
                "--no-index",
                "--no-ext-diff",
                "--no-textconv",
                "--color=never",
                "--",
            ])
            .arg(&old)
            .arg(&new)
            .stdin(Stdio::null())
            .output()?;
        if !output.stdout.is_empty() {
            std::io::stdout().write_all(&output.stdout)?;
        }
    }
    Ok(())
}

fn hash_field(digest: &mut Sha256, value: &[u8]) {
    digest.update((value.len() as u64).to_be_bytes());
    digest.update(value);
}

fn read_document(path: &Path) -> anyhow::Result<Vec<u8>> {
    let mut bytes = Vec::new();
    let file = fs::File::open(path)?;
    anyhow::ensure!(
        file.metadata()?.is_file(),
        "checkpoint input must be a file"
    );
    file.take(MAX_CONTEXT_BYTES + 1).read_to_end(&mut bytes)?;
    anyhow::ensure!(
        bytes.len() as u64 <= MAX_CONTEXT_BYTES,
        "checkpoint input is too large"
    );
    Ok(bytes)
}

fn git_text(cwd: &Path, args: &[&str]) -> anyhow::Result<String> {
    Ok(String::from_utf8(git(cwd, args)?)?
        .trim_end_matches(['\r', '\n'])
        .to_owned())
}

fn git(cwd: &Path, args: &[&str]) -> anyhow::Result<Vec<u8>> {
    let output = Command::new("git")
        .args([
            "-c",
            "core.fsmonitor=false",
            "-c",
            "core.hooksPath=/dev/null",
        ])
        .args(args)
        .env("GIT_OPTIONAL_LOCKS", "0")
        .current_dir(cwd)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()?;
    anyhow::ensure!(output.status.success(), "Git {} failed", args[0]);
    Ok(output.stdout)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stage_copies_working_files_without_git_metadata_or_ignored_files() -> anyhow::Result<()> {
        let scratch = tempfile::tempdir()?;
        let root = scratch.path().join("source");
        fs::create_dir(&root)?;
        git(&root, &["init", "--quiet"])?;
        fs::write(root.join(".gitignore"), "ignored.txt\n")?;
        fs::write(root.join("tracked.txt"), "base")?;
        git(&root, &["add", "."])?;
        git(
            &root,
            &[
                "-c",
                "user.name=Test",
                "-c",
                "user.email=test@example.com",
                "-c",
                "commit.gpgsign=false",
                "commit",
                "--quiet",
                "-m",
                "initial",
            ],
        )?;
        fs::write(root.join("tracked.txt"), "modified")?;
        fs::write(root.join("untracked.txt"), "pending")?;
        fs::write(root.join("ignored.txt"), "excluded")?;

        let baseline = RepositoryState::capture(&root)?;
        assert!(baseline.stage(&root).is_err());
        let stage = baseline.stage(scratch.path())?;
        assert_eq!(fs::read_to_string(stage.join("tracked.txt"))?, "modified");
        assert_eq!(fs::read_to_string(stage.join("untracked.txt"))?, "pending");
        assert!(!stage.join("ignored.txt").exists());
        assert!(!stage.join(".git").exists());
        fs::write(stage.join("tracked.txt"), "agent edit")?;
        assert_eq!(RepositoryState::capture(&root)?, baseline);
        Ok(())
    }

    #[test]
    fn checkpoint_detects_edits_that_leave_git_status_unchanged() -> anyhow::Result<()> {
        let repository = tempfile::tempdir()?;
        let root = repository.path();
        git(root, &["init", "--quiet"])?;
        let tracked = root.join("tracked.txt");
        let untracked = root.join("untracked.txt");
        fs::write(&tracked, "original")?;
        git(root, &["add", "tracked.txt"])?;
        git(
            root,
            &[
                "-c",
                "user.name=Test",
                "-c",
                "user.email=test@example.com",
                "-c",
                "commit.gpgsign=false",
                "commit",
                "--quiet",
                "-m",
                "initial",
            ],
        )?;
        fs::write(&tracked, "first edit")?;
        fs::write(&untracked, "first draft")?;
        let initial = RepositoryState::capture(root)?;

        fs::write(&tracked, "other edit")?;
        let changed_tracked = RepositoryState::capture(root)?;
        assert_eq!(changed_tracked.status, initial.status);
        assert_ne!(changed_tracked.digest, initial.digest);

        fs::write(&untracked, "other draft")?;
        let changed_untracked = RepositoryState::capture(root)?;
        assert_eq!(changed_untracked.status, changed_tracked.status);
        assert_ne!(changed_untracked.digest, changed_tracked.digest);
        Ok(())
    }

    fn init_repo_for_promotion(root: &Path) -> anyhow::Result<()> {
        fs::create_dir(root)?;
        git(root, &["init", "--quiet"])?;
        fs::write(root.join(".gitignore"), "ignored.txt\n")?;
        fs::write(root.join("tracked.txt"), "base\n")?;
        fs::write(root.join("obsolete.txt"), "remove me\n")?;
        git(root, &["add", "."])?;
        git(
            root,
            &[
                "-c",
                "user.name=Test",
                "-c",
                "user.email=test@example.com",
                "-c",
                "commit.gpgsign=false",
                "commit",
                "--quiet",
                "-m",
                "initial",
            ],
        )?;
        fs::write(root.join("ignored.txt"), "keep local secret\n")?;
        Ok(())
    }

    #[tokio::test]
    async fn promote_applies_staged_changes_and_enforces_policy_and_revalidation()
    -> anyhow::Result<()> {
        let scratch = tempfile::tempdir()?;
        let root = scratch.path().join("source");
        init_repo_for_promotion(&root)?;

        let checkpoint_path = scratch.path().join("cp.json");
        let checkpoint = Checkpoint {
            version: VERSION,
            repository: RepositoryState::capture(&root)?,
            task: TaskContext {
                objective: "Update tracked and add test".into(),
                conversation_summary: "Initial summary".into(),
                completed: vec!["Initial setup".into()],
                pending: vec!["Apply staged updates".into()],
                test_results: vec![],
            },
        };
        checkpoint.save(&checkpoint_path)?;

        let stage = checkpoint.repository.stage(scratch.path())?;
        fs::write(stage.join(".wisdcode-task.json"), "{}")?;
        fs::write(stage.join("tracked.txt"), "updated\n")?;
        fs::remove_file(stage.join("obsolete.txt"))?;
        fs::create_dir_all(stage.join("nested"))?;
        fs::write(stage.join("nested/added.txt"), "new file\n")?;

        let plan = StagingPatchPlan::build(&checkpoint.repository.root, &stage)?;
        assert_eq!(
            plan.changes,
            vec![
                StagedChange {
                    path: PathBuf::from("nested/added.txt"),
                    kind: StagedChangeKind::Added,
                },
                StagedChange {
                    path: PathBuf::from("tracked.txt"),
                    kind: StagedChangeKind::Modified,
                },
                StagedChange {
                    path: PathBuf::from("obsolete.txt"),
                    kind: StagedChangeKind::Deleted,
                },
            ]
        );

        let read_only = CliConfigOverrides {
            raw_overrides: vec!["sandbox_mode=\"read-only\"".to_string()],
        };
        assert!(
            checkpoint
                .promote(
                    &checkpoint_path,
                    &root,
                    &stage,
                    &plan,
                    Some(&plan.digest),
                    &read_only,
                )
                .await
                .is_err()
        );
        assert_eq!(fs::read_to_string(root.join("tracked.txt"))?, "base\n");

        let writable = CliConfigOverrides {
            raw_overrides: vec!["sandbox_mode=\"workspace-write\"".to_string()],
        };
        assert!(
            checkpoint
                .promote(
                    &checkpoint_path,
                    &root,
                    &stage,
                    &plan,
                    Some("0000000000000000000000000000000000000000000000000000000000000000"),
                    &writable,
                )
                .await
                .is_err()
        );
        // Approval denied -> rejected with zero writes.
        assert!(
            checkpoint
                .promote_with_confirm(
                    &checkpoint_path,
                    &root,
                    &stage,
                    &plan,
                    None,
                    &writable,
                    || Ok(false),
                )
                .await
                .is_err()
        );
        assert_eq!(fs::read_to_string(root.join("tracked.txt"))?, "base\n");

        // Tamper with source between review and application -> rejected.
        assert!(
            checkpoint
                .promote_with_confirm(
                    &checkpoint_path,
                    &root,
                    &stage,
                    &plan,
                    None,
                    &writable,
                    || {
                        fs::write(root.join("tracked.txt"), "concurrent edit\n")?;
                        Ok(true)
                    },
                )
                .await
                .is_err()
        );
        assert_eq!(
            fs::read_to_string(root.join("tracked.txt"))?,
            "concurrent edit\n"
        );
        fs::write(root.join("tracked.txt"), "base\n")?;

        checkpoint
            .promote(
                &checkpoint_path,
                &root,
                &stage,
                &plan,
                Some(&plan.digest),
                &writable,
            )
            .await?;
        assert_eq!(fs::read_to_string(root.join("tracked.txt"))?, "updated\n");
        assert_eq!(
            fs::read_to_string(root.join("nested/added.txt"))?,
            "new file\n"
        );
        assert!(!root.join("obsolete.txt").exists());
        assert!(!root.join(".wisdcode-task.json").exists());
        assert_eq!(
            fs::read_to_string(root.join("ignored.txt"))?,
            "keep local secret\n"
        );
        Ok(())
    }

    #[cfg(unix)]
    #[test]
    fn staging_plan_rejects_git_internals_symlinks_and_overlapping_dirs() -> anyhow::Result<()> {
        let scratch = tempfile::tempdir()?;
        let root = scratch.path().join("source");
        init_repo_for_promotion(&root)?;
        let baseline = RepositoryState::capture(&root)?;

        assert!(validate_staging_root(&baseline.root, &root).is_err());

        let stage_git = baseline.stage(scratch.path())?;
        fs::create_dir(stage_git.join(".git"))?;
        fs::write(stage_git.join(".git/config"), "[core]\n")?;
        assert!(StagingPatchPlan::build(&baseline.root, &stage_git).is_err());

        let stage_symlink = baseline.stage(scratch.path())?;
        std::os::unix::fs::symlink("/etc/passwd", stage_symlink.join("leak.txt"))?;
        assert!(StagingPatchPlan::build(&baseline.root, &stage_symlink).is_err());

        let stage_escape = baseline.stage(scratch.path())?;
        fs::create_dir_all(stage_escape.join("escape"))?;
        fs::write(stage_escape.join("escape/pwn.txt"), "x")?;
        let plan = StagingPatchPlan::build(&baseline.root, &stage_escape)?;
        let escape_target = scratch.path().join("outside");
        fs::create_dir(&escape_target)?;
        std::os::unix::fs::symlink(&escape_target, root.join("escape"))?;
        assert!(StagingPatchPlan::build(&baseline.root, &stage_escape).is_err());
        assert!(apply_staging_plan(&baseline.root, &stage_escape, &plan).is_err());
        assert!(!escape_target.join("pwn.txt").exists());
        Ok(())
    }
}
