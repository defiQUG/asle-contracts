// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IGovernanceFacet {
    enum ProposalType {
        ParameterChange,
        FacetUpgrade,
        TreasuryWithdrawal,
        ComplianceChange,
        EmergencyPause
    }

    enum ProposalStatus {
        Pending,
        Active,
        Passed,
        Rejected,
        Executed
    }

    struct Proposal {
        uint256 id;
        ProposalType proposalType;
        ProposalStatus status;
        address proposer;
        string description;
        bytes data;
        uint256 startTime;
        uint256 endTime;
        uint256 forVotes;
        uint256 againstVotes;
        mapping(address => bool) hasVoted;
    }

    struct TreasuryAction {
        address recipient;
        uint256 amount;
        address token;
        string reason;
        bool executed;
    }

    event ProposalCreated(
        uint256 indexed proposalId,
        ProposalType proposalType,
        address indexed proposer
    );

    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 weight
    );

    event ProposalExecuted(uint256 indexed proposalId);

    event TreasuryWithdrawal(
        address indexed recipient,
        uint256 amount,
        address token
    );

    event DelegationChanged(
        address indexed delegator,
        address indexed delegate,
        uint256 previousBalance,
        uint256 newBalance
    );

    function createProposal(
        ProposalType proposalType,
        string calldata description,
        bytes calldata data,
        uint256 votingPeriod
    ) external returns (uint256 proposalId);

    function vote(uint256 proposalId, bool support) external;

    function executeProposal(uint256 proposalId) external;

    function getProposal(uint256 proposalId) external view returns (
        uint256 id,
        ProposalType proposalType,
        ProposalStatus status,
        address proposer,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 startTime,
        uint256 endTime
    );

    function proposeTreasuryWithdrawal(
        address recipient,
        uint256 amount,
        address token,
        string calldata reason
    ) external returns (uint256 proposalId);

    function getTreasuryBalance(address token) external view returns (uint256);

    function delegate(address delegatee) external;

    function delegateBySig(
        address delegator,
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function delegates(address delegator) external view returns (address);

    function getCurrentVotes(address account) external view returns (uint256);

    function getPriorVotes(address account, uint256 blockNumber) external view returns (uint256);

    struct Action {
        address target;
        uint256 value;
        bytes data;
        bool executed;
    }

    function createMultiActionProposal(
        string calldata description,
        Action[] calldata actions,
        uint256 votingPeriod
    ) external returns (uint256 proposalId);
}

