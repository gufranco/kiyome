# kiyome

Guidance for anyone, human or agent, changing this repository. What kiyome is and how to use it lives in [README.md](README.md); this file covers how the code is built, tested and shipped.

## Family

kiyome is one of four tools that share a single command-line contract: [FAMILY.md](FAMILY.md). Help page, options, prompts, output, diagnostics and `doctor` follow it. A change to the contract goes into `FAMILY.md` in all four repositories at once: fusho, kakikomi, kiyome and yakitsuke.

kakikomi is the closest sibling. Both keep the same `disk_` function names in [`lib/`](lib), and a fix to a shared helper, such as the option parser in [`lib/cli.sh`](lib/cli.sh) or the drive fault handling in [`lib/io.sh`](lib/io.sh), lands in both repositories.

## Layout

| Path | Holds |
|:-----|:------|
| [`bin/kiyome`](bin/kiyome) | The entry point: usage, options and the wipe flow |
| [`lib/`](lib) | The modules it sources. [`lib/state.sh`](lib/state.sh) declares every global |
| [`man/kiyome.1`](man/kiyome.1) | The man page |
| [`completions/`](completions) | bash, zsh and fish completions |
| [`test/`](test) | The `bats` suite, its helpers, the golden transcripts and the Linux container script |
| [`scripts/`](scripts) | Coverage, the coverage gate, the name check and the release version stamp |

## Commands

| Command | Does |
|:--------|:-----|
| `make lint` | ShellCheck `-o all` on scripts, tests and the bash completion, mandoc on the man page, and the duplicate-function check |
| `make test` | Every `bats` test under the system `sh` |
| `make test-all` | The same tests under `sh`, `dash`, `bash`, `bash --posix` and `zsh` |
| `make test-linux` | The same tests in a privileged Ubuntu container |
| `make coverage` | bashcov on this Mac and in the container, merged, gated at 100% |
| `make install` | Installs the tool, man page and completions under `~/.local` |

`DISK_TEST_RECORD=1` rewrites the golden transcripts in [`test/golden/`](test/golden) from a fresh run; record on macOS and in the container, then read the diff.

## Rules

- POSIX `sh` only. Every function-scoped variable carries the function's prefix, because `sh` has no `local`.
- No comments in source. Tool directives and the `Arrange`, `Act`, `Assert` markers in tests are the only exceptions.
- Tests wipe real file-backed disks attached with `hdiutil` or `losetup`. Faults come only from small wrappers placed on `PATH`.
- A new option goes into the help page, the man page and all three completions in the same commit; a test fails otherwise.
- Conventional commits, pushed straight to `main`. No pull requests.

## Release and Homebrew

- Every push to `main` runs semantic-release. A `feat` or `fix` commit publishes a release, stamps `KIYOME_VERSION` in [`lib/core.sh`](lib/core.sh) and updates the CHANGELOG.
- The Homebrew formula is not in this repository. It lives in [gufranco/homebrew-tap](https://github.com/gufranco/homebrew-tap) as `Formula/kiyome.rb`, next to the formulas for the rest of the family and for other projects.
- After a release, [`.github/workflows/formula.yml`](.github/workflows/formula.yml) sends a `formula-bump` dispatch to the tap with the new tag. The tap rewrites the formula's `url` and `sha256` itself, so neither is edited by hand.
- The dispatch authenticates as a GitHub App through the `TAP_APP_ID` and `TAP_APP_PRIVATE_KEY` secrets of this repository.
- The formula's `install` block decides which files reach users. A new file that must be installed, or a new dependency, needs a matching change to `Formula/kiyome.rb` in the tap.
- On Linux, the dotfiles install kiyome from a clone with `make install`.
