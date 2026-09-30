# Final TODO

- [ ] Run a smoke test on the target CraftOS/Tom's Peripherals setup: cold boot, GPU resolution, keyboard/mouse input, window operations, settings persistence, and device removal. This workspace has no Minecraft/CraftOS runtime or target GPU.
- [ ] Reconcile the 60 fps specification with the timer API. `os.startTimer` rounds to 50 ms, so timer-driven rendering is capped at 20 fps at 20 TPS; the current runtime reports this cap instead of claiming 60 fps.
