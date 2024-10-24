// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract AssetTransfer {
    // Declare the owner of the asset
    address public owner;

    // Asset details (can be customized)
    string public assetName;

    // Event to log the asset transfer
    event AssetTransferred(address indexed from, address indexed to, string assetName);

    // Constructor to initialize the asset and owner
    constructor(string memory _assetName) {
        owner = msg.sender; // The deployer of the contract is the owner
        assetName = _assetName;
    }

    // Function to transfer ownership to a new owner
    function transferAsset(address _newOwner) public {
        require(msg.sender == owner, "Only the owner can transfer the asset.");
        require(_newOwner != address(0), "New owner address cannot be zero.");

        address oldOwner = owner;
        owner = _newOwner;

        // Emit the transfer event
        emit AssetTransferred(oldOwner, _newOwner, assetName);
    }

    // Function to get the current owner
    function getOwner() public view returns (address) {
        return owner;
    }
}
