# Physical-device benchmark protocol

Synthetic fixtures only validate the benchmark gates. Release performance claims require named physical devices and fixed media fixtures.

Each run should include 30 cold starts, 30 warm starts, 100 feed transitions, a 20-minute adaptive stream, seek bursts, background/foreground transitions, and a constrained-network pass. Capture native FastCore snapshots, device model/OS, source fixture hash, thermal state, power mode, network profile, and competitor/library version.

The resulting JSON is checked with `node benchmarks/device-gate.mjs <result.json>`. Never publish the sample fixture as a measured result.
