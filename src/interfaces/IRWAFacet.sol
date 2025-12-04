// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRWAFacet {
    struct RWA {
        uint256 tokenId;
        address assetContract;
        string assetType; // "real_estate", "commodity", "security", etc.
        uint256 totalValue;
        uint256 fractionalizedAmount;
        bool active;
        mapping(address => bool) verifiedHolders;
    }

    event RWATokenized(
        uint256 indexed tokenId,
        address indexed assetContract,
        string assetType,
        uint256 totalValue
    );

    event RWAFractionalized(
        uint256 indexed tokenId,
        address indexed holder,
        uint256 amount
    );

    function tokenizeRWA(
        address assetContract,
        string calldata assetType,
        uint256 totalValue,
        bytes calldata complianceData
    ) external returns (uint256 tokenId);

    function fractionalizeRWA(
        uint256 tokenId,
        uint256 amount,
        address recipient
    ) external returns (uint256 shares);

    function getRWA(uint256 tokenId) external view returns (
        address assetContract,
        string memory assetType,
        uint256 totalValue,
        uint256 fractionalizedAmount,
        bool active
    );

    function verifyHolder(uint256 tokenId, address holder) external view returns (bool);
}

