// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IOracle
 * @notice Interface for price oracles (compatible with Chainlink)
 */
interface IOracle {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 price,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}
