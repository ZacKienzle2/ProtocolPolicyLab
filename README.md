# Protocol Policy Lab

Central version control for policy research output produced by The Protocol. Houses the standardised LaTeX preamble, master bibliography database, and build scripts that enforce formatting consistency across all publications.

[![CI](https://github.com/ZacKienzle2/ProtocolPolicyLab/actions/workflows/ci.yml/badge.svg)](https://github.com/ZacKienzle2/ProtocolPolicyLab/actions/workflows/ci.yml)
[![LaTeX build](https://github.com/ZacKienzle2/ProtocolPolicyLab/actions/workflows/latex.yml/badge.svg)](https://github.com/ZacKienzle2/ProtocolPolicyLab/actions/workflows/latex.yml)
[![CodeQL](https://github.com/ZacKienzle2/ProtocolPolicyLab/actions/workflows/codeql.yml/badge.svg)](https://github.com/ZacKienzle2/ProtocolPolicyLab/actions/workflows/codeql.yml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/ZacKienzle2/ProtocolPolicyLab/badge)](https://securityscorecards.dev/viewer/?uri=github.com/ZacKienzle2/ProtocolPolicyLab)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-fe5196.svg)](https://www.conventionalcommits.org/en/v1.0.0/)
[![SemVer](https://img.shields.io/badge/SemVer-2.0.0-blue.svg)](https://semver.org/spec/v2.0.0.html)
[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit)](https://github.com/pre-commit/pre-commit)
[![Code style: ruff](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/astral-sh/ruff/main/assets/badge/v2.json)](https://github.com/astral-sh/ruff)

## Contents

- `ResearchManual.tex` - Protocol Policy Lab research manual root.
- `StylesAndSettings/LaTexPackages.tex` - shared preamble (packages, colours, fonts, headers, theorems, listings, macros).
- `References/References.bib` - master bibliography.
- `inquiries/_template/` - skeleton for a new inquiry response. Copy into `inquiries/<slug>/` and overwrite the metadata.
- `inquiries/pawc-data-centres/` - PAWC inquiry into data centres: `response.tex`, `metadata.yml`, chapters, preliminary pages, appendix, and source documents under `sources/`.
- `inquiries/education-attainment/` - HoR Standing Committee on Education inquiry into the factors driving educational attainment: same layout.
- `.latexmkrc` - build configuration for `latexmk` (biber backend, clean-up extensions).
- `scripts/` - Python helpers for bibliography curation, figure generation, and release tooling.

Compile any inquiry response from the repository root with `latexmk -cd -pdf inquiries/<slug>/response.tex`.

## Prerequisites

| Tool             | Windows                      | macOS                            | Linux                                                  |
| ---------------- | ---------------------------- | -------------------------------- | ------------------------------------------------------ |
| Git >= 2.30      | Git for Windows              | Xcode Command Line Tools         | distro package                                         |
| TeX distribution | MiKTeX or TeX Live           | MacTeX                           | TeX Live                                               |
| Python 3.12      | installed via `uv`           | installed via `uv`               | installed via `uv`                                     |
| `uv` >= 0.5      | `winget install astral-sh.uv` | `brew install uv`                | `curl -LsSf https://astral.sh/uv/install.sh \| sh`     |

Editor: VS Code with the LaTeX Workshop extension is recommended.

## Quickstart

```bash
git clone https://github.com/ZacKienzle2/ProtocolPolicyLab.git
cd ProtocolPolicyLab
uv sync --frozen --all-extras
pre-commit install --install-hooks
latexmk -pdf ResearchManual.tex
latexmk -cd -pdf inquiries/pawc-data-centres/response.tex
latexmk -cd -pdf inquiries/education-attainment/response.tex
```

## Branching

`main` is protected and always deployable. Feature branches: `feat/<slug>`, `fix/<slug>`, `docs/<slug>`, `ci/<slug>`, `build/<slug>`, `chore/<slug>`, `refactor/<slug>`, `perf/<slug>`, `test/<slug>`, `style/<slug>`. Open a PR, wait for green CI, squash-merge.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Conventional Commits 1.0.0 and DCO sign-off required.

## Maintainers

See [CODEOWNERS](.github/CODEOWNERS).

## License

[MIT](LICENSE).

## Related

[SECURITY](SECURITY.md) | [SUPPORT](SUPPORT.md) | [GOVERNANCE](GOVERNANCE.md) | [CHANGELOG](CHANGELOG.md) | [ROADMAP](ROADMAP.md) | [CITATION](CITATION.cff)
