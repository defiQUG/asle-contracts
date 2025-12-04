// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICCIPFacet} from "../../interfaces/ICCIPFacet.sol";
import {ICCIPRouter} from "../../interfaces/ICCIPRouter.sol";
import {LibAccessControl} from "../../libraries/LibAccessControl.sol";
import {ILiquidityFacet} from "../../interfaces/ILiquidityFacet.sol";
import {IVaultFacet} from "../../interfaces/IVaultFacet.sol";
import {ISecurityFacet} from "../../interfaces/ISecurityFacet.sol";

/**
 * @title CCIPFacet
 * @notice Cross-chain messaging via Chainlink CCIP with state synchronization
 */
contract CCIPFacet is ICCIPFacet {
    struct CCIPStorage {
        ICCIPRouter ccipRouter;
        mapping(uint256 => uint64) chainSelectors; // chainId => chainSelector
        mapping(uint64 => uint256) selectorToChain; // chainSelector => chainId
        mapping(uint256 => bool) supportedChains;
        mapping(bytes32 => bool) deliveredMessages;
        mapping(bytes32 => uint256) messageTimestamps;
        mapping(bytes32 => MessageStatus) messageStatuses;
        address authorizedSender; // Authorized sender for cross-chain messages
    }

    enum MessageStatus {
        Pending,
        Delivered,
        Failed
    }

    bytes32 private constant CCIP_STORAGE_POSITION = keccak256("asle.ccip.storage");

    event MessageExecuted(bytes32 indexed messageId, MessageType messageType, bool success);
    event ChainSelectorUpdated(uint256 chainId, uint64 selector);

    function ccipStorage() internal pure returns (CCIPStorage storage cs) {
        bytes32 position = CCIP_STORAGE_POSITION;
        assembly {
            cs.slot := position
        }
    }

    modifier onlySupportedChain(uint256 chainId) {
        require(ccipStorage().supportedChains[chainId], "CCIPFacet: Chain not supported");
        _;
    }

    modifier onlyAuthorized() {
        CCIPStorage storage cs = ccipStorage();
        require(
            msg.sender == cs.authorizedSender || 
            cs.authorizedSender == address(0) ||
            LibAccessControl.hasRole(LibAccessControl.DEFAULT_ADMIN_ROLE, msg.sender),
            "CCIPFacet: Unauthorized"
        );
        _;
    }

    // ============ Liquidity Sync ============

    function sendLiquiditySync(
        uint256 targetChainId,
        uint256 poolId
    ) external override onlySupportedChain(targetChainId) returns (bytes32 messageId) {
        // Fetch pool data from LiquidityFacet
        ILiquidityFacet liquidityFacet = ILiquidityFacet(address(this));
        ILiquidityFacet.Pool memory pool = liquidityFacet.getPool(poolId);

        LiquiditySyncPayload memory payload = LiquiditySyncPayload({
            poolId: poolId,
            baseReserve: pool.baseReserve,
            quoteReserve: pool.quoteReserve,
            virtualBaseReserve: pool.virtualBaseReserve,
            virtualQuoteReserve: pool.virtualQuoteReserve
        });

        bytes memory encodedPayload = abi.encode(MessageType.LiquiditySync, payload);
        
        messageId = _sendCCIPMessage(
            targetChainId,
            MessageType.LiquiditySync,
            encodedPayload
        );

        emit CCIPMessageSent(messageId, block.chainid, targetChainId, MessageType.LiquiditySync);
    }

    function sendVaultRebalance(
        uint256 targetChainId,
        uint256 vaultId,
        uint256 amount,
        address asset
    ) external override onlySupportedChain(targetChainId) returns (bytes32 messageId) {
        VaultRebalancePayload memory payload = VaultRebalancePayload({
            vaultId: vaultId,
            targetChainId: targetChainId,
            amount: amount,
            asset: asset
        });

        bytes memory encodedPayload = abi.encode(MessageType.VaultRebalance, payload);
        
        messageId = _sendCCIPMessage(
            targetChainId,
            MessageType.VaultRebalance,
            encodedPayload
        );

        emit VaultRebalanced(vaultId, block.chainid, targetChainId, amount);
        emit CCIPMessageSent(messageId, block.chainid, targetChainId, MessageType.VaultRebalance);
    }

    function sendPriceDeviationWarning(
        uint256 targetChainId,
        uint256 poolId,
        uint256 deviation
    ) external override onlySupportedChain(targetChainId) returns (bytes32 messageId) {
        ILiquidityFacet liquidityFacet = ILiquidityFacet(address(this));
        uint256 currentPrice = liquidityFacet.getPrice(poolId);

        PriceDeviationPayload memory payload = PriceDeviationPayload({
            poolId: poolId,
            price: currentPrice,
            deviation: deviation,
            timestamp: block.timestamp
        });

        bytes memory encodedPayload = abi.encode(MessageType.PriceDeviation, payload);
        
        messageId = _sendCCIPMessage(
            targetChainId,
            MessageType.PriceDeviation,
            encodedPayload
        );

        emit CCIPMessageSent(messageId, block.chainid, targetChainId, MessageType.PriceDeviation);
    }

    // ============ Message Handling ============

    function handleCCIPMessage(
        bytes32 messageId,
        uint256 sourceChainId,
        bytes calldata payload
    ) external override onlyAuthorized {
        CCIPStorage storage cs = ccipStorage();
        require(!cs.deliveredMessages[messageId], "CCIPFacet: Message already processed");

        cs.deliveredMessages[messageId] = true;
        cs.messageTimestamps[messageId] = block.timestamp;
        cs.messageStatuses[messageId] = MessageStatus.Pending;

        (MessageType messageType, bytes memory data) = abi.decode(payload, (MessageType, bytes));

        bool success = false;
        if (messageType == MessageType.LiquiditySync) {
            LiquiditySyncPayload memory syncPayload = abi.decode(data, (LiquiditySyncPayload));
            success = _handleLiquiditySync(syncPayload, sourceChainId);
        } else if (messageType == MessageType.VaultRebalance) {
            VaultRebalancePayload memory rebalancePayload = abi.decode(data, (VaultRebalancePayload));
            success = _handleVaultRebalance(rebalancePayload, sourceChainId);
        } else if (messageType == MessageType.PriceDeviation) {
            PriceDeviationPayload memory pricePayload = abi.decode(data, (PriceDeviationPayload));
            success = _handlePriceDeviation(pricePayload, sourceChainId);
        }

        cs.messageStatuses[messageId] = success ? MessageStatus.Delivered : MessageStatus.Failed;
        emit CCIPMessageReceived(messageId, sourceChainId, messageType);
        emit MessageExecuted(messageId, messageType, success);
    }

    // ============ Configuration ============

    function setCCIPRouter(address router) external override {
        LibAccessControl.requireRole(LibAccessControl.DEFAULT_ADMIN_ROLE, msg.sender);
        ccipStorage().ccipRouter = ICCIPRouter(router);
    }

    function setSupportedChain(uint256 chainId, bool supported) external override {
        LibAccessControl.requireRole(LibAccessControl.DEFAULT_ADMIN_ROLE, msg.sender);
        ccipStorage().supportedChains[chainId] = supported;
    }

    function setChainSelector(uint256 chainId, uint64 selector) external {
        LibAccessControl.requireRole(LibAccessControl.DEFAULT_ADMIN_ROLE, msg.sender);
        CCIPStorage storage cs = ccipStorage();
        cs.chainSelectors[chainId] = selector;
        cs.selectorToChain[selector] = chainId;
        emit ChainSelectorUpdated(chainId, selector);
    }

    function setAuthorizedSender(address sender) external {
        LibAccessControl.requireRole(LibAccessControl.DEFAULT_ADMIN_ROLE, msg.sender);
        ccipStorage().authorizedSender = sender;
    }

    // ============ View Functions ============

    function isChainSupported(uint256 chainId) external view override returns (bool) {
        return ccipStorage().supportedChains[chainId];
    }

    function getMessageStatus(bytes32 messageId) external view override returns (bool delivered, uint256 timestamp) {
        CCIPStorage storage cs = ccipStorage();
        delivered = cs.deliveredMessages[messageId];
        timestamp = cs.messageTimestamps[messageId];
    }

    function getChainSelector(uint256 chainId) external view returns (uint64) {
        return ccipStorage().chainSelectors[chainId];
    }

    // ============ Internal Functions ============

    function _sendCCIPMessage(
        uint256 targetChainId,
        MessageType messageType,
        bytes memory payload
    ) internal returns (bytes32) {
        CCIPStorage storage cs = ccipStorage();
        require(address(cs.ccipRouter) != address(0), "CCIPFacet: Router not set");

        uint64 chainSelector = cs.chainSelectors[targetChainId];
        require(chainSelector != 0, "CCIPFacet: Chain selector not set");

        ICCIPRouter.EVM2AnyMessage memory message = ICCIPRouter.EVM2AnyMessage({
            receiver: abi.encode(address(this)),
            data: payload,
            tokenAmounts: new ICCIPRouter.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: address(0)
        });

        uint256 fee = cs.ccipRouter.getFee(chainSelector, message);
        require(msg.value >= fee, "CCIPFacet: Insufficient fee");

        return cs.ccipRouter.ccipSend{value: fee}(chainSelector, message);
    }

    function _handleLiquiditySync(LiquiditySyncPayload memory payload, uint256 sourceChainId) internal returns (bool) {
        try this._syncPoolState(payload) {
            emit LiquiditySynced(payload.poolId, sourceChainId, payload.baseReserve, payload.quoteReserve);
            return true;
        } catch {
            return false;
        }
    }

    function _syncPoolState(LiquiditySyncPayload memory payload) external {
        require(msg.sender == address(this), "CCIPFacet: Internal only");
        // In production, this would update pool virtual reserves based on cross-chain state
        // For now, we emit events and let the backend handle synchronization
    }

    function _handleVaultRebalance(VaultRebalancePayload memory payload, uint256 sourceChainId) internal returns (bool) {
        // In production, this would trigger vault rebalancing logic
        // For now, emit event for backend processing
        emit VaultRebalanced(payload.vaultId, sourceChainId, payload.targetChainId, payload.amount);
        return true;
    }

    function _handlePriceDeviation(PriceDeviationPayload memory payload, uint256 sourceChainId) internal returns (bool) {
        // Trigger security alerts if deviation is significant
        if (payload.deviation > 500) { // 5% deviation threshold
            ISecurityFacet securityFacet = ISecurityFacet(address(this));
            // Could trigger circuit breaker or alert
        }
        return true;
    }
}
