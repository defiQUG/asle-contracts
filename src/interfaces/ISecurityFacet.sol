// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ISecurityFacet {
    enum PauseReason {
        Emergency,
        CircuitBreaker,
        OracleDeviation,
        ComplianceViolation,
        GovernanceDecision
    }

    struct CircuitBreaker {
        uint256 threshold;
        uint256 timeWindow;
        uint256 currentValue;
        uint256 windowStart;
        bool triggered;
    }

    event SystemPaused(PauseReason reason, address indexed pausedBy);
    event SystemUnpaused(address indexed unpausedBy);
    event CircuitBreakerTriggered(uint256 indexed poolId, uint256 deviation);
    event SecurityAudit(uint256 timestamp, string auditType, bool passed);

    function pauseSystem(PauseReason reason) external;

    function unpauseSystem() external;

    function isPaused() external view returns (bool);

    function setCircuitBreaker(
        uint256 poolId,
        uint256 threshold,
        uint256 timeWindow
    ) external;

    function checkCircuitBreaker(uint256 poolId, uint256 value) external returns (bool);

    function triggerCircuitBreaker(uint256 poolId) external;

    function recordSecurityAudit(string calldata auditType, bool passed) external;
}

