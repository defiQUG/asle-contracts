// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISecurityFacet} from "../../interfaces/ISecurityFacet.sol";
import {LibDiamond} from "../../libraries/LibDiamond.sol";
import {LibAccessControl} from "../../libraries/LibAccessControl.sol";
import {ILiquidityFacet} from "../../interfaces/ILiquidityFacet.sol";

contract SecurityFacet is ISecurityFacet {
    struct SecurityStorage {
        bool paused;
        PauseReason pauseReason;
        address pausedBy;
        uint256 pauseTime;
        uint256 maxPauseDuration; // Maximum pause duration in seconds (0 = unlimited)
        mapping(uint256 => CircuitBreaker) circuitBreakers;
        mapping(string => uint256) lastAuditTime;
        mapping(uint256 => uint256) poolPriceHistory; // poolId => last price
        mapping(uint256 => uint256) maxPriceDeviation; // poolId => max deviation in basis points
    }

    bytes32 private constant SECURITY_STORAGE_POSITION = keccak256("asle.security.storage");

    function securityStorage() internal pure returns (SecurityStorage storage ss) {
        bytes32 position = SECURITY_STORAGE_POSITION;
        assembly {
            ss.slot := position
        }
    }

    modifier whenNotPaused() {
        require(!securityStorage().paused, "SecurityFacet: System is paused");
        _;
    }

    modifier onlyAuthorized() {
        require(
            LibAccessControl.hasRole(LibAccessControl.SECURITY_ADMIN_ROLE, msg.sender) ||
            LibAccessControl.hasRole(LibAccessControl.DEFAULT_ADMIN_ROLE, msg.sender),
            "SecurityFacet: Not authorized"
        );
        _;
    }

    function pauseSystem(PauseReason reason) external override onlyAuthorized {
        SecurityStorage storage ss = securityStorage();
        require(!ss.paused, "SecurityFacet: Already paused");
        
        ss.paused = true;
        ss.pauseReason = reason;
        ss.pausedBy = msg.sender;
        ss.pauseTime = block.timestamp;

        emit SystemPaused(reason, msg.sender);
    }

    function pauseSystemWithDuration(PauseReason reason, uint256 duration) external onlyAuthorized {
        SecurityStorage storage ss = securityStorage();
        require(!ss.paused, "SecurityFacet: Already paused");
        
        ss.paused = true;
        ss.pauseReason = reason;
        ss.pausedBy = msg.sender;
        ss.pauseTime = block.timestamp;
        ss.maxPauseDuration = duration;

        emit SystemPaused(reason, msg.sender);
    }

    function unpauseSystem() external override onlyAuthorized {
        SecurityStorage storage ss = securityStorage();
        require(ss.paused, "SecurityFacet: Not paused");
        
        // Check if pause has expired (if max duration is set)
        if (ss.maxPauseDuration > 0) {
            require(block.timestamp >= ss.pauseTime + ss.maxPauseDuration, "SecurityFacet: Pause duration not expired");
        }
        
        ss.paused = false;
        address unpauser = msg.sender;
        ss.maxPauseDuration = 0;

        emit SystemUnpaused(unpauser);
    }

    function isPaused() external view override returns (bool) {
        return securityStorage().paused;
    }

    function setCircuitBreaker(
        uint256 poolId,
        uint256 threshold,
        uint256 timeWindow
    ) external override onlyAuthorized {
        SecurityStorage storage ss = securityStorage();
        ss.circuitBreakers[poolId] = CircuitBreaker({
            threshold: threshold,
            timeWindow: timeWindow,
            currentValue: 0,
            windowStart: block.timestamp,
            triggered: false
        });
    }

    function checkCircuitBreaker(uint256 poolId, uint256 value) external override returns (bool) {
        SecurityStorage storage ss = securityStorage();
        CircuitBreaker storage cb = ss.circuitBreakers[poolId];
        
        if (cb.triggered) {
            return false; // Circuit breaker already triggered
        }

        // Reset window if expired
        if (block.timestamp > cb.windowStart + cb.timeWindow) {
            cb.windowStart = block.timestamp;
            cb.currentValue = 0;
        }

        cb.currentValue += value;

        if (cb.currentValue > cb.threshold) {
            cb.triggered = true;
            emit CircuitBreakerTriggered(poolId, cb.currentValue);
            
            // Automatically pause if circuit breaker triggers
            if (!ss.paused) {
                ss.paused = true;
                ss.pauseReason = PauseReason.CircuitBreaker;
                ss.pausedBy = address(this);
                ss.pauseTime = block.timestamp;
                emit SystemPaused(PauseReason.CircuitBreaker, address(this));
            }
            
            return false;
        }

        return true;
    }

    function resetCircuitBreaker(uint256 poolId) external onlyAuthorized {
        SecurityStorage storage ss = securityStorage();
        CircuitBreaker storage cb = ss.circuitBreakers[poolId];
        require(cb.triggered, "SecurityFacet: Circuit breaker not triggered");
        
        cb.triggered = false;
        cb.currentValue = 0;
        cb.windowStart = block.timestamp;
    }

    function triggerCircuitBreaker(uint256 poolId) external override {
        SecurityStorage storage ss = securityStorage();
        CircuitBreaker storage cb = ss.circuitBreakers[poolId];
        
        require(!cb.triggered, "SecurityFacet: Already triggered");
        
        cb.triggered = true;
        emit CircuitBreakerTriggered(poolId, cb.currentValue);
        
        // Optionally pause the system
        // Note: This would need to be called externally or through Diamond
        // pauseSystem(PauseReason.CircuitBreaker);
    }

    function recordSecurityAudit(string calldata auditType, bool passed) external override onlyAuthorized {
        SecurityStorage storage ss = securityStorage();
        ss.lastAuditTime[auditType] = block.timestamp;
        
        emit SecurityAudit(block.timestamp, auditType, passed);
        
        if (!passed && !ss.paused) {
            ss.paused = true;
            ss.pauseReason = PauseReason.ComplianceViolation;
            ss.pausedBy = msg.sender;
            ss.pauseTime = block.timestamp;
            emit SystemPaused(PauseReason.ComplianceViolation, msg.sender);
        }
    }

    function checkPriceDeviation(uint256 poolId, uint256 currentPrice) external returns (bool) {
        SecurityStorage storage ss = securityStorage();
        uint256 lastPrice = ss.poolPriceHistory[poolId];
        uint256 maxDeviation = ss.maxPriceDeviation[poolId];
        
        if (lastPrice == 0) {
            ss.poolPriceHistory[poolId] = currentPrice;
            return true;
        }
        
        if (maxDeviation == 0) {
            maxDeviation = 1000; // Default 10% deviation
        }
        
        uint256 deviation;
        if (currentPrice > lastPrice) {
            deviation = ((currentPrice - lastPrice) * 10000) / lastPrice;
        } else {
            deviation = ((lastPrice - currentPrice) * 10000) / lastPrice;
        }
        
        if (deviation > maxDeviation) {
            // Trigger circuit breaker or pause
            CircuitBreaker storage cb = ss.circuitBreakers[poolId];
            if (!cb.triggered) {
                cb.triggered = true;
                emit CircuitBreakerTriggered(poolId, deviation);
            }
            return false;
        }
        
        ss.poolPriceHistory[poolId] = currentPrice;
        return true;
    }

    function setMaxPriceDeviation(uint256 poolId, uint256 maxDeviation) external onlyAuthorized {
        securityStorage().maxPriceDeviation[poolId] = maxDeviation;
    }
}

