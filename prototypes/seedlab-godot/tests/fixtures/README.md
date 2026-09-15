# Camera observations

`camera-observations.json` was captured from this game's actual Godot 4.5.1
renderer using `--vision-check`, on 2026-09-15. Each camera has nine target
states and 144 spatial colour values. Fixtures contain no pre-trained weights.

The target field belongs to the test environment for computing rewards and
evaluation. It is never copied into the policy's observation. These fixtures
test learning on this fixed workbench, not generalization to novel layouts.

Regeneration and test commands are documented in the project README.
