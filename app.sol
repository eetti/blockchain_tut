// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Package Delivery Tracker
/// @author You
/// @notice Minimal, dependency-free tracker for last-mile package delivery.
/// @dev Designed to be replaceable with OZ AccessControl if desired.
contract DeliveryTracker {
    // -------------------------
    // Roles & Ownership
    // -------------------------
    address public owner;
    mapping(address => bool) public operators;  // dispatch/admin staff
    mapping(address => bool) public couriers;   // delivery agents

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyOperator() {
        require(operators[msg.sender] || msg.sender == owner, "Not operator");
        _;
    }

    modifier onlyCourier() {
        require(couriers[msg.sender], "Not courier");
        _;
    }

    // -------------------------
    // Pausing
    // -------------------------
    bool public paused;

    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }

    function pause() external onlyOwner { paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { paused = false; emit Unpaused(msg.sender); }

    // -------------------------
    // Package Model
    // -------------------------
    enum Status {
        Created,
        InTransit,
        OutForDelivery,
        Delivered,
        Cancelled,
        Returned
    }

    struct Checkpoint {
        uint256 time;       // block.timestamp
        string location;    // e.g., "Halifax NS, Hub A" or a lat/long/geohash
        string note;        // free-form note ("Loaded on truck #42")
    }

    struct Package {
        uint256 id;             // tracking id
        address sender;         // who created it
        address recipient;      // delivery destination account
        address courier;        // assigned courier (optional until assigned)
        uint64  createdAt;      // unix seconds
        uint64  updatedAt;      // unix seconds
        Status  status;         // current status
        string  description;    // short description or SKU(s)
        string  pickup;         // pickup address or hint
        bool    exists;         // guard
    }

    // storage
    uint256 private _nextId = 1;
    mapping(uint256 => Package) private _packages;
    mapping(uint256 => Checkpoint[]) private _checkpoints;

    // -------------------------
    // Events
    // -------------------------
    event Paused(address by);
    event Unpaused(address by);

    event OperatorSet(address indexed account, bool allowed);
    event CourierSet(address indexed account, bool allowed);

    event PackageCreated(
        uint256 indexed id,
        address indexed sender,
        address indexed recipient,
        string description,
        string pickup
    );

    event CourierAssigned(uint256 indexed id, address indexed courier);
    event StatusUpdated(uint256 indexed id, Status indexed status, string reason);
    event CheckpointAdded(uint256 indexed id, string location, string note);
    event Delivered(uint256 indexed id, address indexed recipient, string proofHash);
    event Cancelled(uint256 indexed id, string reason);
    event Returned(uint256 indexed id, string reason);

    // -------------------------
    // Constructor
    // -------------------------
    constructor() {
        owner = msg.sender;
        operators[msg.sender] = true;
        emit OperatorSet(msg.sender, true);
    }

    // -------------------------
    // Admin: roles
    // -------------------------
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }

    function setOperator(address account, bool allowed) external onlyOwner {
        operators[account] = allowed;
        emit OperatorSet(account, allowed);
    }

    function setCourier(address account, bool allowed) external onlyOperator {
        couriers[account] = allowed;
        emit CourierSet(account, allowed);
    }

    // -------------------------
    // Core: create & assign
    // -------------------------
    /// @notice Create a package (sender can be any EOA/contract).
    function createPackage(
        address recipient,
        string calldata description,
        string calldata pickup
    ) external whenNotPaused returns (uint256 id) {
        require(recipient != address(0), "Recipient required");

        id = _nextId++;
        Package storage p = _packages[id];
        p.id = id;
        p.sender = msg.sender;
        p.recipient = recipient;
        p.createdAt = uint64(block.timestamp);
        p.updatedAt = uint64(block.timestamp);
        p.status = Status.Created;
        p.description = description;
        p.pickup = pickup;
        p.exists = true;

        emit PackageCreated(id, msg.sender, recipient, description, pickup);
    }

    /// @notice Assign a courier (operator-level). Can be reassigned before delivery.
    function assignCourier(uint256 id, address courierAddr) external onlyOperator whenNotPaused {
        Package storage p = _get(id);
        require(couriers[courierAddr], "Not whitelisted courier");
        require(p.status != Status.Delivered && p.status != Status.Cancelled && p.status != Status.Returned, "Finalized");
        p.courier = courierAddr;
        p.updatedAt = uint64(block.timestamp);
        emit CourierAssigned(id, courierAddr);
    }

    // -------------------------
    // Updates: status & checkpoints
    // -------------------------
    /// @notice Courier or operator can move the package along the route.
    function updateStatus(uint256 id, Status newStatus, string calldata reason)
        external
        whenNotPaused
    {
        Package storage p = _get(id);

        // Only operator until courier assigned; after assignment, only assigned courier or operator
        if (p.courier == address(0)) {
            require(operators[msg.sender] || msg.sender == owner, "Not authorized (no courier yet)");
        } else {
            require(
                msg.sender == p.courier || operators[msg.sender] || msg.sender == owner,
                "Not authorized"
            );
        }

        // Disallow invalid transitions after finalization
        require(p.status != Status.Delivered && p.status != Status.Cancelled && p.status != Status.Returned, "Finalized");

        // Prevent skipping straight to Delivered without explicit confirmation
        require(newStatus != Status.Delivered, "Use confirmDelivery");

        p.status = newStatus;
        p.updatedAt = uint64(block.timestamp);
        emit StatusUpdated(id, newStatus, reason);
    }

    /// @notice Add a tracking checkpoint (location + note). Courier or operator.
    function addCheckpoint(uint256 id, string calldata location, string calldata note)
        external
        whenNotPaused
    {
        Package storage p = _get(id);
        require(
            msg.sender == p.courier || operators[msg.sender] || msg.sender == owner,
            "Not authorized"
        );
        _checkpoints[id].push(Checkpoint({
            time: block.timestamp,
            location: location,
            note: note
        }));
        p.updatedAt = uint64(block.timestamp);
        emit CheckpointAdded(id, location, note);
    }

    /// @notice Recipient confirms delivery. Optional proof hash (e.g., photo/signature IPFS hash).
    function confirmDelivery(uint256 id, string calldata proofHash) external whenNotPaused {
        Package storage p = _get(id);
        require(msg.sender == p.recipient, "Only recipient");
        require(p.status != Status.Delivered && p.status != Status.Cancelled && p.status != Status.Returned, "Finalized");

        p.status = Status.Delivered;
        p.updatedAt = uint64(block.timestamp);
        emit Delivered(id, msg.sender, proofHash);
    }

    /// @notice Operator cancels (e.g., lost/damaged before delivery).
    function cancel(uint256 id, string calldata reason) external onlyOperator whenNotPaused {
        Package storage p = _get(id);
        require(p.status != Status.Delivered && p.status != Status.Cancelled && p.status != Status.Returned, "Finalized");
        p.status = Status.Cancelled;
        p.updatedAt = uint64(block.timestamp);
        emit Cancelled(id, reason);
    }

    /// @notice Operator marks returned to sender.
    function markReturned(uint256 id, string calldata reason) external onlyOperator whenNotPaused {
        Package storage p = _get(id);
        require(p.status != Status.Delivered && p.status != Status.Cancelled && p.status != Status.Returned, "Finalized");
        p.status = Status.Returned;
        p.updatedAt = uint64(block.timestamp);
        emit Returned(id, reason);
    }

    // -------------------------
    // Views
    // -------------------------
    function getPackage(uint256 id) external view returns (Package memory) {
        return _get(id);
    }

    function getCheckpoints(uint256 id) external view returns (Checkpoint[] memory) {
        require(_packages[id].exists, "Unknown id");
        return _checkpoints[id];
    }

    function nextId() external view returns (uint256) {
        return _nextId;
    }

    // -------------------------
    // Internal helpers
    // -------------------------
    function _get(uint256 id) internal view returns (Package storage p) {
        p = _packages[id];
        require(p.exists, "Unknown id");
    }
}
