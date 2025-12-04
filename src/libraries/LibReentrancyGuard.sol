// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title LibReentrancyGuard
 * @notice Diamond-compatible reentrancy guard using Diamond storage pattern
 * @dev Provides reentrancy protection for Diamond facets
 */
library LibReentrancyGuard {
    bytes32 constant REENTRANCY_GUARD_STORAGE_POSITION = keccak256("asle.reentrancyguard.storage");

    struct ReentrancyGuardStorage {
        uint256 status; // 1 = locked, 2 = unlocked
    }

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    function reentrancyGuardStorage() internal pure returns (ReentrancyGuardStorage storage rgs) {
        bytes32 position = REENTRANCY_GUARD_STORAGE_POSITION;
        assembly {
            rgs.slot := position
        }
    }

    /**
     * @notice Initialize reentrancy guard
     */
    function initialize() internal {
        ReentrancyGuardStorage storage rgs = reentrancyGuardStorage();
        require(rgs.status == 0, "LibReentrancyGuard: already initialized");
        rgs.status = _NOT_ENTERED;
    }

    /**
     * @notice Enter a non-reentrant function
     */
    function enter() internal {
        ReentrancyGuardStorage storage rgs = reentrancyGuardStorage();
        
        // Initialize if not already done
        if (rgs.status == 0) {
            rgs.status = _NOT_ENTERED;
        }
        
        require(rgs.status != _ENTERED, "LibReentrancyGuard: reentrant call");
        rgs.status = _ENTERED;
    }

    /**
     * @notice Exit a non-reentrant function
     */
    function exit() internal {
        ReentrancyGuardStorage storage rgs = reentrancyGuardStorage();
        rgs.status = _NOT_ENTERED;
    }
}

