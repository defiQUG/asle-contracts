// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IVaultFacet {
    struct Vault {
        address asset; // ERC-20 asset for ERC-4626, or address(0) for ERC-1155
        uint256 totalAssets;
        uint256 totalSupply;
        bool isMultiAsset; // true for ERC-1155, false for ERC-4626
        bool active;
    }

    event VaultCreated(
        uint256 indexed vaultId,
        address indexed asset,
        bool isMultiAsset
    );

    event Deposit(
        uint256 indexed vaultId,
        address indexed depositor,
        uint256 assets,
        uint256 shares
    );

    event Withdraw(
        uint256 indexed vaultId,
        address indexed withdrawer,
        uint256 assets,
        uint256 shares
    );

    function createVault(
        address asset,
        bool isMultiAsset
    ) external returns (uint256 vaultId);

    function deposit(
        uint256 vaultId,
        uint256 assets,
        address receiver
    ) external returns (uint256 shares);

    function withdraw(
        uint256 vaultId,
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets);

    function getVault(uint256 vaultId) external view returns (Vault memory);

    function convertToShares(
        uint256 vaultId,
        uint256 assets
    ) external view returns (uint256);

    function convertToAssets(
        uint256 vaultId,
        uint256 shares
    ) external view returns (uint256);
}

