// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IChainConfigFacet {
    struct ChainConfig {
        uint256 chainId;
        string name;
        address nativeToken; // Address(0) for native ETH
        string explorerUrl;
        uint256 gasLimit;
        uint256 messageTimeout;
        bool active;
    }

    event ChainConfigUpdated(uint256 indexed chainId, string name, bool active);
    event ChainGasLimitUpdated(uint256 indexed chainId, uint256 gasLimit);
    event ChainTimeoutUpdated(uint256 indexed chainId, uint256 timeout);

    function setChainConfig(
        uint256 chainId,
        string calldata name,
        address nativeToken,
        string calldata explorerUrl,
        uint256 gasLimit,
        uint256 messageTimeout
    ) external;

    function getChainConfig(uint256 chainId) external view returns (ChainConfig memory);

    function setChainActive(uint256 chainId, bool active) external;

    function setChainGasLimit(uint256 chainId, uint256 gasLimit) external;

    function setChainTimeout(uint256 chainId, uint256 timeout) external;

    function isChainActive(uint256 chainId) external view returns (bool);
}

