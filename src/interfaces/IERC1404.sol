// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ERC-1404: Simple Restricted Token Standard
interface IERC1404 {
    function detectTransferRestriction(address from, address to, uint256 amount) external view returns (uint8);
    function messageForTransferRestriction(uint8 restrictionCode) external view returns (string memory);
}

