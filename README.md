#  ClientSimulator - Server-Driven Visual Simulation for Roblox
Game link

https://www.roblox.com/games/72272989753542/Dust-Simulator

**ClientSimulator** is a performance-focused Roblox system designed to handle massive amounts of floating or ambient objects (like fireflies, particles, or bounce balls) — simulated entirely on the server and visualized on the client.

This architecture ensures tight control over gameplay logic while offloading rendering to the client for scalability and visual fidelity.

# Demo
---
[![Watch the video](https://img.youtube.com/vi/7XJ0WVjakzk/0.jpg)](https://www.youtube.com/watch?v=7XJ0WVjakzk)
---

##  What It Does

- Simulates thousands of particles or floating entities on the server
- Clients receive visual-only updates (spawn, move, destroy) via `RemoteEvent`
- Built-in support for effects like:
  - Rarity-based color sequences (`Firefly`)
  - Smooth floating movement (`BallManager`)
  - Expandable to any visual object (`VoxelDust`, etc.)

---

##  Core Features

###  Server-Authoritative Logic
- All spawn/move/destroy decisions are made on the server
- Prevents cheating and ensures synchronization across all players

###  Visual-Only Client Rendering
- Clients handle appearance only, making this system scalable for thousands of objects
- Uses `FloatEvent` to sync spawn, move, and destroy instructions

###  Modular Simulation Handlers
- `Firefly`: Emits glowing particles with randomized rarity and color palettes
- `BallManager`: Spawns and moves bouncing balls in floating simulations
- `VoxelDust`: Placeholder for voxel-style particles (extensible)

---

##  How It Works

```
[Server]
 ├── BallManager:FireAllClients("Spawn", data)
 ├── Firefly:chooseRarity() → chooseColorFromPool()
 └── VoxelDust:Simulate()

[Client]
 └── FloatEvent.OnClientEvent:
     ├── "Spawn" → create visual entity
     ├── "Move" → apply transform
     └── "Destroy" → cleanup
```

All updates are **batched and sent per Heartbeat or trigger**, ensuring smooth visual feedback with minimal lag.

---

##  Folder Structure

```
src/
├── server/
│   └── ClientSimulation/
│       ├── Firefly.luau
│       ├── BallManager.luau
│       └── VoxelDust.luau
├── client/
│   └── Simulations/ (receives visual data)
├── shared/
│   └── FloatEvent binding (optional)
```

---

##  Tech Stack

- Roblox Luau
- RemoteEvent for server-client communication
- Clean modular system (Rojo-ready)

---

##  Notes

> This system is designed for *internal simulation needs* where clients reflect what the server simulates.  
> While not plug-and-play, developers can reuse the architecture by plugging in their own data models and spawn logic.

---

## 👤 Author

Developed by Itipat Songsampansakul as part of a modular systems engineering showcase for performance-conscious game development on Roblox.
