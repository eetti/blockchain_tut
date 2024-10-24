### How it works:
- Owner: The contract stores the address of the current owner.
- Constructor: When deployed, the owner is set to the address that deploys the contract, and an asset name is initialized.
- Transfer function: The owner can transfer ownership of the asset to another address.
- Events: An event is emitted every time an asset transfer happens for logging purposes.