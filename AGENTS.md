# kiyome

Guidance for anyone, human or agent, changing kiyome. What kiyome is and how to use it lives in [README.md](README.md).

[FAMILY.md](FAMILY.md) holds everything kiyome shares with the rest of the kodougu family, and it is the same in every member. This file holds only what is exclusive to kiyome, under the same headings as the agent guide of every member. Read both before changing anything; a rule that would serve the other members goes into `FAMILY.md` instead of here.

## Layout

| Path | Holds |
|:-----|:------|
| [`bin/kiyome`](bin/kiyome) | The entry point: usage, options and the wipe flow |
| [`lib/`](lib) | The modules. [`lib/state.sh`](lib/state.sh) declares every global |
| [`man/kiyome.1`](man/kiyome.1) | The man page |
| [`completions/`](completions) | bash, zsh and fish completions |
| [`test/`](test) | The `bats` suite, its helpers, the golden transcripts, the fake `sudo` and the Linux container script |
| [`scripts/`](scripts) | Coverage, the coverage gate, the Linux coverage run, the name check, the toolset helper and the release version stamp |

## Names

- Globals carry `DISK_`; function-scoped variables carry a per-function `disk_` prefix. kakikomi uses the same names, see Domain rules.
- Settings come from `KIYOME_<NAME>`, such as `KIYOME_PASSES`; test switches are `KIYOME_TERMINAL`, `KIYOME_TEST_SHELLS` and `KIYOME_TEST_RECORD`.
- Output goes through `disk_info`, `disk_say`, `disk_error` and `disk_warning`.

## Behaviour

- kiyome has one job, so a bare `kiyome` on a terminal asks for the disk and the number of passes directly.

## Domain rules

- kakikomi is the closest sibling. Both keep the same `disk_` function names in [`lib/`](lib), and a fix to a shared helper, such as the option parser in [`lib/cli.sh`](lib/cli.sh) or the drive fault handling in [`lib/io.sh`](lib/io.sh), lands in both repositories.
- Tests wipe real file-backed disks attached with `hdiutil` or `losetup`; the container runs privileged to reach loop devices.

## Release

- `KIYOME_VERSION` lives in [`lib/core.sh`](lib/core.sh).

## Gaps against FAMILY.md

As of 2026-10-29, closed in the change that removes each line:

- No `--json` for a wipe's result.
