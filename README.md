# SEEDLAB — Button Garden

A 3D incremental game about raising a real neural network, built for the OpenAI × Tokyo AI 100-Hour Game Challenge. Team: **qqpann**.

Teach a robot to read handwritten MNIST digits, earn G, and press physical upgrade buttons to improve its neurons, memory, learning and arm. A tabletop monitor continuously shows the actual camera image, 12×12 neural input and predictions. Automation is unlocked through upgrades. Eventually, an OpenAI coach chooses improvements and the same robot arm presses the upgrade board.

## Play

Requires Godot 4.5+ and Node.js 22.12+.

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

MNIST by Yann LeCun, Corinna Cortes and Christopher J. C. Burges: an 800-image subset obtained through https://github.com/cvdfoundation/mnist . The CVDF mirror does not state a separate license; https://huggingface.co/datasets/ylecun/mnist lists MIT. The original split, source indices and checksums are recorded in `prototypes/seedlab-godot/data/mnist/manifest.json`. System fonts are used from the operating system and are not bundled.

This repository contains the latest MNIST game and its required server helper, prepared for submission on September 15, 2026.
