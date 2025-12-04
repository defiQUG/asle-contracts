// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibAccessControl} from "../libraries/LibAccessControl.sol";
import {LibReentrancyGuard} from "../libraries/LibReentrancyGuard.sol";

/**
 * @title DiamondInit
 * @notice Initialization contract for ASLE Diamond
 * @dev This contract is called once during Diamond deployment to initialize storage
 */
contract DiamondInit {
    /**
     * @notice Initialize Diamond with default settings
     * @param _initOwner Address to set as initial owner
     */
    function init(address _initOwner) external {
        // Initialize Diamond ownership
        require(!LibDiamond.isInitialized(), "DiamondInit: Already initialized");
        LibDiamond.setContractOwner(_initOwner);
        
        // Initialize access control
        LibAccessControl.initializeAccessControl(_initOwner);
        
        // Initialize reentrancy guard
        LibReentrancyGuard.initialize();
        
        // Set default timelock delay (7 days)
        LibAccessControl.setTimelockDelay(7 days);
        
        // Enable timelock by default
        LibAccessControl.setTimelockEnabled(true);
    }
}

