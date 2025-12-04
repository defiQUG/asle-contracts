// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDiamondCut} from "../interfaces/IDiamondCut.sol";

library LibDiamond {
    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");
    bytes32 constant DIAMOND_OWNER_STORAGE_POSITION = keccak256("diamond.standard.owner.storage");

    struct FacetAddressAndPosition {
        address facetAddress;
        uint16 functionSelectorPosition;
    }

    struct FacetFunctionSelectors {
        bytes4[] functionSelectors;
        uint16 facetAddressPosition;
    }

    struct DiamondStorage {
        mapping(bytes4 => FacetAddressAndPosition) selectorToFacetAndPosition;
        mapping(address => FacetFunctionSelectors) facetFunctionSelectors;
        address[] facetAddresses;
        mapping(bytes4 => bool) supportedInterfaces;
    }

    struct DiamondOwnerStorage {
        address contractOwner;
        bool initialized;
    }

    struct TimelockStorage {
        mapping(bytes32 => uint256) scheduledCuts; // cutHash => executionTime
        uint256 defaultDelay; // Default timelock delay in seconds
        bool timelockEnabled;
    }

    bytes32 constant DIAMOND_TIMELOCK_STORAGE_POSITION = keccak256("diamond.standard.timelock.storage");

    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function diamondOwnerStorage() internal pure returns (DiamondOwnerStorage storage dos) {
        bytes32 position = DIAMOND_OWNER_STORAGE_POSITION;
        assembly {
            dos.slot := position
        }
    }

    function diamondTimelockStorage() internal pure returns (TimelockStorage storage ts) {
        bytes32 position = DIAMOND_TIMELOCK_STORAGE_POSITION;
        assembly {
            ts.slot := position
        }
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event DiamondCutScheduled(bytes32 indexed cutHash, uint256 executionTime);
    event DiamondCutExecuted(bytes32 indexed cutHash);

    function setContractOwner(address _newOwner) internal {
        DiamondOwnerStorage storage dos = diamondOwnerStorage();
        address oldOwner = dos.contractOwner;
        dos.contractOwner = _newOwner;
        if (!dos.initialized) {
            dos.initialized = true;
        }
        emit OwnershipTransferred(oldOwner, _newOwner);
    }

    function isInitialized() internal view returns (bool) {
        return diamondOwnerStorage().initialized;
    }

    function contractOwner() internal view returns (address contractOwner_) {
        contractOwner_ = diamondOwnerStorage().contractOwner;
    }

    function enforceIsContractOwner() internal view {
        require(msg.sender == contractOwner(), "LibDiamond: Must be contract owner");
    }

    function diamondCut(
        IDiamondCut.FacetCut[] memory _diamondCut,
        address _init,
        bytes memory _calldata
    ) internal {
        LibDiamondCut.diamondCut(_diamondCut, _init, _calldata);
    }
}

library LibDiamondCut {
    event DiamondCut(IDiamondCut.FacetCut[] _diamondCut, address _init, bytes _calldata);

    function diamondCut(
        IDiamondCut.FacetCut[] memory _diamondCut,
        address _init,
        bytes memory _calldata
    ) internal {
        for (uint256 facetIndex; facetIndex < _diamondCut.length; facetIndex++) {
            IDiamondCut.FacetCutAction action = _diamondCut[facetIndex].action;
            if (action == IDiamondCut.FacetCutAction.Add) {
                addFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);
            } else if (action == IDiamondCut.FacetCutAction.Replace) {
                replaceFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);
            } else if (action == IDiamondCut.FacetCutAction.Remove) {
                removeFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);
            } else {
                revert("LibDiamondCut: Incorrect FacetCutAction");
            }
        }
        emit DiamondCut(_diamondCut, _init, _calldata);
        initializeDiamondCut(_init, _calldata);
    }

    function addFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        require(_facetAddress != address(0), "LibDiamondCut: Add facet can't be address(0)");
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint16 selectorPosition = uint16(ds.facetFunctionSelectors[_facetAddress].functionSelectors.length);
        if (selectorPosition == 0) {
            enforceHasContractCode(_facetAddress, "LibDiamondCut: New facet has no code");
            ds.facetFunctionSelectors[_facetAddress].facetAddressPosition = uint16(ds.facetAddresses.length);
            ds.facetAddresses.push(_facetAddress);
        }
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            require(oldFacetAddress == address(0), "LibDiamondCut: Can't add function that already exists");
            ds.selectorToFacetAndPosition[selector] = LibDiamond.FacetAddressAndPosition(_facetAddress, selectorPosition);
            ds.facetFunctionSelectors[_facetAddress].functionSelectors.push(selector);
            selectorPosition++;
        }
    }

    function replaceFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        require(_facetAddress != address(0), "LibDiamondCut: Replace facet can't be address(0)");
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint16 selectorPosition = uint16(ds.facetFunctionSelectors[_facetAddress].functionSelectors.length);
        if (selectorPosition == 0) {
            enforceHasContractCode(_facetAddress, "LibDiamondCut: New facet has no code");
            ds.facetFunctionSelectors[_facetAddress].facetAddressPosition = uint16(ds.facetAddresses.length);
            ds.facetAddresses.push(_facetAddress);
        }
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            require(oldFacetAddress != _facetAddress, "LibDiamondCut: Can't replace function with same function");
            removeFunction(oldFacetAddress, selector);
            addFunction(_facetAddress, selector, selectorPosition);
            selectorPosition++;
        }
    }

    function removeFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        require(_facetAddress == address(0), "LibDiamondCut: Remove facet address must be address(0)");
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            removeFunction(oldFacetAddress, selector);
        }
    }

    function addFunction(address _facetAddress, bytes4 _selector, uint16 _selectorPosition) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.selectorToFacetAndPosition[_selector].functionSelectorPosition = _selectorPosition;
        ds.facetFunctionSelectors[_facetAddress].functionSelectors.push(_selector);
        ds.selectorToFacetAndPosition[_selector].facetAddress = _facetAddress;
    }

    function removeFunction(address _facetAddress, bytes4 _selector) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(_facetAddress != address(0), "LibDiamondCut: Can't remove function that doesn't exist");
        require(_facetAddress != address(this), "LibDiamondCut: Can't remove immutable function");
        uint256 selectorPosition = ds.selectorToFacetAndPosition[_selector].functionSelectorPosition;
        uint256 lastSelectorPosition = ds.facetFunctionSelectors[_facetAddress].functionSelectors.length - 1;
        if (selectorPosition != lastSelectorPosition) {
            bytes4 lastSelector = ds.facetFunctionSelectors[_facetAddress].functionSelectors[lastSelectorPosition];
            ds.facetFunctionSelectors[_facetAddress].functionSelectors[selectorPosition] = lastSelector;
            ds.selectorToFacetAndPosition[lastSelector].functionSelectorPosition = uint16(selectorPosition);
        }
        ds.facetFunctionSelectors[_facetAddress].functionSelectors.pop();
        delete ds.selectorToFacetAndPosition[_selector];
        if (lastSelectorPosition == 0) {
            uint256 lastFacetAddressPosition = ds.facetAddresses.length - 1;
            uint256 facetAddressPosition = ds.facetFunctionSelectors[_facetAddress].facetAddressPosition;
            if (facetAddressPosition != lastFacetAddressPosition) {
                address lastFacetAddress = ds.facetAddresses[lastFacetAddressPosition];
                ds.facetAddresses[facetAddressPosition] = lastFacetAddress;
                ds.facetFunctionSelectors[lastFacetAddress].facetAddressPosition = uint16(facetAddressPosition);
            }
            ds.facetAddresses.pop();
            delete ds.facetFunctionSelectors[_facetAddress].facetAddressPosition;
        }
    }

    function initializeDiamondCut(address _init, bytes memory _calldata) internal {
        if (_init == address(0)) {
            require(_calldata.length == 0, "LibDiamondCut: _init is address(0) but _calldata is not empty");
        } else {
            require(_calldata.length > 0, "LibDiamondCut: _calldata is empty but _init is not address(0)");
            if (_init != address(this)) {
                enforceHasContractCode(_init, "LibDiamondCut: _init has no code");
            }
            (bool success, bytes memory error) = _init.delegatecall(_calldata);
            if (!success) {
                if (error.length > 0) {
                    revert(string(error));
                } else {
                    revert("LibDiamondCut: _init function reverted");
                }
            }
        }
    }

    function enforceHasContractCode(address _contract, string memory _errorMessage) internal view {
        uint256 contractSize;
        assembly {
            contractSize := extcodesize(_contract)
        }
        require(contractSize > 0, _errorMessage);
    }
}

