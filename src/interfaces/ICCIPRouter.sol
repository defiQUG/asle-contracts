// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ICCIPRouter
 * @notice Interface for Chainlink CCIP Router (compatible with official CCIP interface)
 */
interface ICCIPRouter {
    struct EVM2AnyMessage {
        bytes receiver;
        bytes data;
        EVMTokenAmount[] tokenAmounts;
        bytes extraArgs;
        address feeToken;
    }

    struct EVMTokenAmount {
        address token;
        uint256 amount;
    }

    function ccipSend(
        uint64 destinationChainSelector,
        EVM2AnyMessage memory message
    ) external payable returns (bytes32 messageId);

    function getFee(
        uint64 destinationChainSelector,
        EVM2AnyMessage memory message
    ) external view returns (uint256 fee);
}

