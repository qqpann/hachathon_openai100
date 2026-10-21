# SEEDLAB — Button Garden

A 3D incremental game about raising a real neural network, built for the OpenAI × Tokyo AI 100-Hour Game Challenge. Team: **qqpann**.

Teach a robot to read handwritten MNIST digits, earn G, and press physical upgrade buttons to improve its neurons, memory, learning and arm. A tabletop monitor continuously shows the actual camera image, 12×12 neural input and predictions. Automation is unlocked through upgrades. Eventually, an OpenAI coach chooses improvements and the same robot arm presses the upgrade board.

## Play

Download a native build from **[GitHub Releases](https://github.com/qqpann/hachathon_openai100/releases)**:

- **macOS:** one Universal app for Apple Silicon and Intel.
- **Windows:** x64 ZIP; keep the `seedlab` folder beside the executable.
- **Linux:** x64 tar.gz; keep the `seedlab` folder beside the executable.

Extract the entire archive. Godot, Node.js and Japanese fonts are bundled. The game interface is Japanese. The local neural learner, upgrades and certification exams work offline.

For optional OpenAI coaching, use the bottom-right **APIキーを設定・解除** button to enter your own OpenAI API key. The masked input passes the key to a private, authenticated loopback server. It is kept in memory for this launch only, never saved with the game. Clear it in the same dialog or quit the game to discard it. Usage is billed to your OpenAI API account. Unlock Learning level 3 and complete 24 practice trials before pressing R to delegate.

macOS builds are ad-hoc signed, without Developer ID signing or notarization. Windows builds are unsigned. See the included README for OS launch instructions.

### Run from source

Requires Godot 4.5+ and Node.js 22.23.4+ (22.x), 24.22.1+ (24.x), or 26.12.1+ (26.x).

```sh
./prototypes/seedlab-godot/run.command
```

On macOS, the launcher finds Godot in Applications. Elsewhere set `GODOT_BIN` to your Godot executable, or open `prototypes/seedlab-godot/project.godot` with Godot. The game itself can run offline. For the OpenAI coach, copy `.env.example` to `.env.local` in this repository root and set your own `OPENAI_API_KEY`. Credentials stay on the local server.

- Click the matching 0–9 button to teach; earn G from each attempt.
- Click the physical upgrade matrix on the left to purchase upgrades.
- Unlock Space (one NN action), A (automatic practice), and R (OpenAI coaching).
- T: ten-question certification exam. V: fixed/wrist camera. F: return to the workbench view.

[Full game guide](prototypes/seedlab-godot/README.md) · [Validation record](prototypes/seedlab-godot/VALIDATION.md)

## Implementation

The local learner is a real 144 → 8–32 → 10 neural network with backpropagation and replay. It reads rendered camera images; labels are supplied only after grading. Training and exams use separate MNIST splits. OpenAI GPT-5.4 nano via the Responses API manages upgrade choices, with structured outputs, server-side validation and bounded usage.

```sh
npm test
```

## Third-party components

Godot: MIT and bundled notices, https://godotengine.org/license/ . Node.js: MIT and bundled notices. Blender (GPL-2.0-or-later) and Blender MCP (MIT) were authoring tools for the original models. OpenAI API and Codex are services under their applicable terms. The API usage-policy helper was reused from our hackathon workspace.

MNIST by Yann LeCun, Corinna Cortes and Christopher J. C. Burges: an 800-image subset obtained through https://github.com/cvdfoundation/mnist . The CVDF mirror does not state a separate license; https://huggingface.co/datasets/ylecun/mnist lists MIT. The original split, source indices and checksums are recorded in `prototypes/seedlab-godot/data/mnist/manifest.json`. Packaged builds include unmodified Noto Sans CJK JP Regular under SIL OFL 1.1; its license is in `prototypes/seedlab-godot/assets/fonts/OFL.txt`. Editor builds use installed system fonts.

## Build and submission history

On macOS, install Godot 4.5.1 with matching export templates and run:

```sh
python3 prototypes/seedlab-godot/tools/package_desktop.py
```

This creates three archives and SHA-256 checksums in `prototypes/seedlab-godot/build/desktop/releases/`. The bundled Node.js 22.23.4 executables come from official downloads and are verified against pinned checksums.

The original September 15, 2026 submission is preserved at **[submission-2026-09-15](https://github.com/qqpann/hachathon_openai100/tree/submission-2026-09-15)** (`833e4dd`). Native packaging, the BYOT settings dialog and bundled fonts were added after the submission deadline.
