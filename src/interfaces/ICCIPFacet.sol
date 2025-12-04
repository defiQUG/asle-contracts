// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICCIPFacet {
    enum MessageType {
        LiquiditySync,
        VaultRebalance,
        PriceDeviation,
        TokenBridge
    }

    struct CCIPMessage {
        MessageType messageType;
        uint256 sourceChainId;
        uint256 targetChainId;
        bytes payload;
        uint256 timestamp;
    }

    struct LiquiditySyncPayload {
        uint256 poolId;
        uint256 baseReserve;
        uint256 quoteReserve;
        uint256 virtualBaseReserve;
        uint256 virtualQuoteReserve;
    }

    struct VaultRebalancePayload {
        uint256 vaultId;
        uint256 targetChainId;
        uint256 amount;
        address asset;
    }

    struct PriceDeviationPayload {
        uint256 poolId;
        uint256 price;
        uint256 deviation;
        uint256 timestamp;
    }

    event CCIPMessageSent(
        bytes32 indexed messageId,
        uint256 indexed sourceChainId,
        uint256 indexed targetChainId,
        MessageType messageType
    );

    event CCIPMessageReceived(
        bytes32 indexed messageId,
        uint256 indexed sourceChainId,
        MessageType messageType
    );

    event LiquiditySynced(
        uint256 indexed poolId,
        uint256 indexed chainId,
        uint256 baseReserve,
        uint256 quoteReserve
    );

    event VaultRebalanced(
        uint256 indexed vaultId,
        uint256 indexed sourceChainId,
        uint256 indexed targetChainId,
        uint256 amount
    );

    function sendLiquiditySync(
        uint256 targetChainId,
        uint256 poolId
    ) external returns (bytes32 messageId);

    function sendVaultRebalance(
        uint256 targetChainId,
        uint256 vaultId,
        uint256 amount,
        address asset
    ) external returns (bytes32 messageId);

    function sendPriceDeviationWarning(
        uint256 targetChainId,
        uint256 poolId,
        uint256 deviation
    ) external returns (bytes32 messageId);

    function handleCCIPMessage(
        bytes32 messageId,
        uint256 sourceChainId,
        bytes calldata payload
    ) external;

    function setCCIPRouter(address router) external;

    function setSupportedChain(uint256 chainId, bool supported) external;

    function isChainSupported(uint256 chainId) external view returns (bool);

    function getMessageStatus(bytes32 messageId) external view returns (bool delivered, uint256 timestamp);
}

