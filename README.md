### How it works:
- Owner: The contract stores the address of the current owner.
- Constructor: When deployed, the owner is set to the address that deploys the contract, and an asset name is initialized.
- Transfer function: The owner can transfer ownership of the asset to another address.
- Events: An event is emitted every time an asset transfer happens for logging purposes.

## app.sol — DeliveryTracker contract

This folder contains `app.sol`, a minimal, dependency-free Solidity contract named `DeliveryTracker` which implements a simple last-mile package delivery tracking system.

Summary:
- Purpose: Track packages through creation, assignment, checkpoints, status updates, and final delivery or cancellation.
- Access control: Owner, operators (dispatch/admin staff), and couriers (delivery agents).
- Pausing: Owner can pause/unpause contract actions.

Key concepts and data structures:
- enum Status: Created, InTransit, OutForDelivery, Delivered, Cancelled, Returned.
- struct Package: Holds package metadata (id, sender, recipient, courier, timestamps, status, description, pickup, exists).
- struct Checkpoint: Timestamped location and note for tracking progress.

Important functions:
- constructor(): Sets deployer as `owner` and an initial operator.
- transferOwnership(newOwner): Owner-only transfer of contract ownership.
- setOperator(account, allowed): Owner-only toggle for operators.
- setCourier(account, allowed): Operator-only toggle for couriers.
- createPackage(recipient, description, pickup): Anyone can create a package; returns a tracking id.
- assignCourier(id, courierAddr): Operator assigns a whitelisted courier to a package.
- updateStatus(id, newStatus, reason): Operator or assigned courier updates package status (cannot set Delivered here).
- addCheckpoint(id, location, note): Add a tracking checkpoint (courier/operator).
- confirmDelivery(id, proofHash): Recipient confirms delivery (sets status to Delivered and emits Delivered event).
- cancel(id, reason) / markReturned(id, reason): Operator-only finalization actions.

Events to watch for off-chain:
- PackageCreated(id, sender, recipient, description, pickup)
- CourierAssigned(id, courier)
- StatusUpdated(id, status, reason)
- CheckpointAdded(id, location, note)
- Delivered(id, recipient, proofHash)
- Cancelled(id, reason)
- Returned(id, reason)
- OperatorSet(account, allowed) and CourierSet(account, allowed)
- Paused/Unpaused(by)

Usage / deployment notes:
- Solidity version: pragma ^0.8.20 — use a compiler compatible with 0.8.20.
- This contract intentionally uses a simple role model and can be swapped for OpenZeppelin's AccessControl for more advanced permissioning.
- Typical flow:
	1. Deployer becomes owner and operator.
	2. Owner/operator whitelists courier accounts via `setCourier`.
	3. Any account calls `createPackage` to register a package and receive an id.
	4. Operator assigns a courier with `assignCourier`.
	5. Courier/operator logs checkpoints with `addCheckpoint` and updates intermediate statuses with `updateStatus`.
	6. Recipient calls `confirmDelivery` with optional proof (e.g., IPFS hash) to finalize delivery.

Quick examples (Remix / Hardhat):
- Compile with Solidity 0.8.20.
- Deploy `DeliveryTracker` from your chosen account (becomes owner).
- Call `setCourier(courierAddr, true)` to whitelist courier.
- Call `createPackage(recipientAddr, "Box", "Warehouse A")` to create a package. Note the returned id.

Security notes / limitations:
- No escrow/payment logic — this is purely tracking metadata.
- Relies on trusted operators/couriers; consider integrating OpenZeppelin AccessControl for multi-role granularity and more robust admin patterns.
- Strings are stored on-chain; for larger proofs or images use off-chain storage (IPFS) and store hashes.

If you'd like, I can also add example scripts for Hardhat/Foundry to deploy and interact with `DeliveryTracker`.