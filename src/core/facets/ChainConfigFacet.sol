// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IChainConfigFacet} from "../../interfaces/IChainConfigFacet.sol";
import {LibAccessControl} from "../../libraries/LibAccessControl.sol";

/**
 * @title ChainConfigFacet
 * @notice Manages chain-specific configurations for multi-chain operations
 */
contract ChainConfigFacet is IChainConfigFacet {
    struct ChainConfigStorage {
        mapping(uint256 => ChainConfig) chainConfigs;
        mapping(uint256 => bool) activeChains;
    }

    bytes32 private constant CHAIN_CONFIG_STORAGE_POSITION = keccak256("asle.chainconfig.storage");

    function chainConfigStorage() internal pure returns (ChainConfigStorage storage ccs) {
        bytes32 position = CHAIN_CONFIG_STORAGE_POSITION;
        assembly {
            ccs.slot := position
        }
    }

    modifier onlyAdmin() {
        LibAccessControl.requireRole(LibAccessControl.DEFAULT_ADMIN_ROLE, msg.sender);
        _;
    }

    function setChainConfig(
        uint256 chainId,
        string calldata name,
        address nativeToken,
        string calldata explorerUrl,
        uint256 gasLimit,
        uint256 messageTimeout
    ) external override onlyAdmin {
        ChainConfigStorage storage ccs = chainConfigStorage();
        
        ccs.chainConfigs[chainId] = ChainConfig({
            chainId: chainId,
            name: name,
            nativeToken: nativeToken,
            explorerUrl: explorerUrl,
            gasLimit: gasLimit,
            messageTimeout: messageTimeout,
            active: ccs.activeChains[chainId] // Preserve existing active status
        });

        emit ChainConfigUpdated(chainId, name, ccs.activeChains[chainId]);
    }

    function getChainConfig(uint256 chainId) external view override returns (ChainConfig memory) {
        ChainConfigStorage storage ccs = chainConfigStorage();
        ChainConfig memory config = ccs.chainConfigs[chainId];
        require(config.chainId != 0 || chainId == 0, "ChainConfigFacet: Chain not configured");
        return config;
    }

    function setChainActive(uint256 chainId, bool active) external override onlyAdmin {
        ChainConfigStorage storage ccs = chainConfigStorage();
        require(ccs.chainConfigs[chainId].chainId != 0 || chainId == 0, "ChainConfigFacet: Chain not configured");
        
        ccs.activeChains[chainId] = active;
        ccs.chainConfigs[chainId].active = active;
        
        emit ChainConfigUpdated(chainId, ccs.chainConfigs[chainId].name, active);
    }

    function setChainGasLimit(uint256 chainId, uint256 gasLimit) external override onlyAdmin {
        ChainConfigStorage storage ccs = chainConfigStorage();
        require(ccs.chainConfigs[chainId].chainId != 0 || chainId == 0, "ChainConfigFacet: Chain not configured");
        
        ccs.chainConfigs[chainId].gasLimit = gasLimit;
        emit ChainGasLimitUpdated(chainId, gasLimit);
    }

    function setChainTimeout(uint256 chainId, uint256 timeout) external override onlyAdmin {
        ChainConfigStorage storage ccs = chainConfigStorage();
        require(ccs.chainConfigs[chainId].chainId != 0 || chainId == 0, "ChainConfigFacet: Chain not configured");
        
        ccs.chainConfigs[chainId].messageTimeout = timeout;
        emit ChainTimeoutUpdated(chainId, timeout);
    }

    function isChainActive(uint256 chainId) external view override returns (bool) {
        ChainConfigStorage storage ccs = chainConfigStorage();
        return ccs.activeChains[chainId];
    }
}

