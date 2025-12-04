// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGovernanceFacet} from "../../interfaces/IGovernanceFacet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LibDiamond} from "../../libraries/LibDiamond.sol";
import {LibAccessControl} from "../../libraries/LibAccessControl.sol";
import {IDiamondCut} from "../../interfaces/IDiamondCut.sol";
import {ISecurityFacet} from "../../interfaces/ISecurityFacet.sol";

contract GovernanceFacet is IGovernanceFacet {
    using SafeERC20 for IERC20;

    struct GovernanceStorage {
        mapping(uint256 => Proposal) proposals;
        mapping(uint256 => Action[]) proposalActions; // proposalId => actions array
        uint256 proposalCount;
        address governanceToken; // ERC-20 token for voting
        uint256 quorumThreshold; // Minimum votes required
        uint256 votingPeriod; // Default voting period in seconds
        uint256 timelockDelay; // Delay before execution
        mapping(uint256 => uint256) proposalTimelocks; // proposalId => execution time
        mapping(address => uint256) treasuryBalances; // token => balance
        uint256 minProposalThreshold; // Minimum tokens required to create proposal
        mapping(address => address) delegations; // delegator => delegatee
        mapping(address => uint256) checkpoints; // account => voting power checkpoint
    }

    bytes32 private constant GOVERNANCE_STORAGE_POSITION = keccak256("asle.governance.storage");

    function governanceStorage() internal pure returns (GovernanceStorage storage gs) {
        bytes32 position = GOVERNANCE_STORAGE_POSITION;
        assembly {
            gs.slot := position
        }
    }

    modifier onlyProposer() {
        GovernanceStorage storage gs = governanceStorage();
        if (gs.governanceToken != address(0)) {
            uint256 balance = IERC20(gs.governanceToken).balanceOf(msg.sender);
            require(balance >= gs.minProposalThreshold, "GovernanceFacet: Insufficient tokens to propose");
        }
        _;
    }

    function createProposal(
        ProposalType proposalType,
        string calldata description,
        bytes calldata data,
        uint256 votingPeriod
    ) external override onlyProposer returns (uint256 proposalId) {
        GovernanceStorage storage gs = governanceStorage();
        proposalId = gs.proposalCount;
        gs.proposalCount++;

        Proposal storage proposal = gs.proposals[proposalId];
        proposal.id = proposalId;
        proposal.proposalType = proposalType;
        proposal.status = ProposalStatus.Pending;
        proposal.proposer = msg.sender;
        proposal.description = description;
        proposal.data = data;
        proposal.startTime = block.timestamp;
        proposal.endTime = block.timestamp + (votingPeriod > 0 ? votingPeriod : gs.votingPeriod);
        proposal.forVotes = 0;
        proposal.againstVotes = 0;

        // Auto-activate if voting period is immediate
        if (votingPeriod == 0) {
            proposal.status = ProposalStatus.Active;
        }

        emit ProposalCreated(proposalId, proposalType, msg.sender);
    }

    function vote(uint256 proposalId, bool support) external override {
        GovernanceStorage storage gs = governanceStorage();
        Proposal storage proposal = gs.proposals[proposalId];
        
        require(proposal.status == ProposalStatus.Active, "GovernanceFacet: Proposal not active");
        require(block.timestamp <= proposal.endTime, "GovernanceFacet: Voting period ended");
        require(!proposal.hasVoted[msg.sender], "GovernanceFacet: Already voted");

        address voter = msg.sender;
        address delegatee = gs.delegations[voter];
        
        // If voting power is delegated, the delegatee should vote
        if (delegatee != address(0) && delegatee != voter) {
            require(msg.sender == delegatee, "GovernanceFacet: Only delegatee can vote");
            voter = delegatee;
        }
        
        uint256 votingPower = _getVotingPower(voter);
        require(votingPower > 0, "GovernanceFacet: No voting power");

        proposal.hasVoted[msg.sender] = true;

        if (support) {
            proposal.forVotes += votingPower;
        } else {
            proposal.againstVotes += votingPower;
        }

        emit VoteCast(proposalId, msg.sender, support, votingPower);

        // Check if proposal can be passed
        _checkProposalStatus(proposalId);
    }

    function executeProposal(uint256 proposalId) external override {
        GovernanceStorage storage gs = governanceStorage();
        Proposal storage proposal = gs.proposals[proposalId];
        
        require(proposal.status == ProposalStatus.Passed, "GovernanceFacet: Proposal not passed");
        require(block.timestamp > proposal.endTime, "GovernanceFacet: Voting still active");
        
        // Check timelock
        uint256 executionTime = gs.proposalTimelocks[proposalId];
        if (executionTime > 0) {
            require(block.timestamp >= executionTime, "GovernanceFacet: Timelock not expired");
        }

        proposal.status = ProposalStatus.Executed;

        // Execute actions if multi-action proposal
        Action[] storage actions = gs.proposalActions[proposalId];
        if (actions.length > 0) {
            for (uint256 i = 0; i < actions.length; i++) {
                Action storage action = actions[i];
                require(!action.executed, "GovernanceFacet: Action already executed");
                
                (bool success, ) = action.target.call{value: action.value}(action.data);
                require(success, "GovernanceFacet: Action execution failed");
                
                action.executed = true;
            }
        } else {
            // Execute proposal based on type (legacy single-action)
            if (proposal.proposalType == ProposalType.TreasuryWithdrawal) {
                _executeTreasuryWithdrawal(proposal.data);
            } else if (proposal.proposalType == ProposalType.FacetUpgrade) {
                _executeFacetUpgrade(proposal.data);
            } else if (proposal.proposalType == ProposalType.EmergencyPause) {
                _executeEmergencyPause(proposal.data);
            } else if (proposal.proposalType == ProposalType.ComplianceChange) {
                _executeComplianceChange(proposal.data);
            } else if (proposal.proposalType == ProposalType.ParameterChange) {
                _executeParameterChange(proposal.data);
            }
        }

        emit ProposalExecuted(proposalId);
    }

    /**
     * Create multi-action proposal
     */
    function createMultiActionProposal(
        string calldata description,
        Action[] calldata actions,
        uint256 votingPeriod
    ) external onlyProposer returns (uint256 proposalId) {
        GovernanceStorage storage gs = governanceStorage();
        proposalId = gs.proposalCount;
        gs.proposalCount++;

        Proposal storage proposal = gs.proposals[proposalId];
        proposal.id = proposalId;
        proposal.proposalType = ProposalType.ParameterChange; // Default type for multi-action
        proposal.status = ProposalStatus.Pending;
        proposal.proposer = msg.sender;
        proposal.description = description;
        proposal.startTime = block.timestamp;
        proposal.endTime = block.timestamp + (votingPeriod > 0 ? votingPeriod : gs.votingPeriod);
        proposal.forVotes = 0;
        proposal.againstVotes = 0;

        // Store actions
        for (uint256 i = 0; i < actions.length; i++) {
            gs.proposalActions[proposalId].push(actions[i]);
        }

        if (votingPeriod == 0) {
            proposal.status = ProposalStatus.Active;
        }

        emit ProposalCreated(proposalId, proposal.proposalType, msg.sender);
    }

    function cancelProposal(uint256 proposalId) external {
        GovernanceStorage storage gs = governanceStorage();
        Proposal storage proposal = gs.proposals[proposalId];
        
        require(proposal.proposer == msg.sender || LibAccessControl.hasRole(LibAccessControl.DEFAULT_ADMIN_ROLE, msg.sender), 
                "GovernanceFacet: Not authorized");
        require(proposal.status == ProposalStatus.Active || proposal.status == ProposalStatus.Pending,
                "GovernanceFacet: Cannot cancel");
        
        proposal.status = ProposalStatus.Rejected;
    }

    function proposeTreasuryWithdrawal(
        address recipient,
        uint256 amount,
        address token,
        string calldata reason
    ) external override returns (uint256 proposalId) {
        bytes memory data = abi.encode(recipient, amount, token, reason);
        return this.createProposal(ProposalType.TreasuryWithdrawal, reason, data, 0);
    }

    function getProposal(uint256 proposalId) external view override returns (
        uint256 id,
        ProposalType proposalType,
        ProposalStatus status,
        address proposer,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 startTime,
        uint256 endTime
    ) {
        Proposal storage proposal = governanceStorage().proposals[proposalId];
        return (
            proposal.id,
            proposal.proposalType,
            proposal.status,
            proposal.proposer,
            proposal.forVotes,
            proposal.againstVotes,
            proposal.startTime,
            proposal.endTime
        );
    }

    function getTreasuryBalance(address token) external view override returns (uint256) {
        return governanceStorage().treasuryBalances[token];
    }

    function _checkProposalStatus(uint256 proposalId) internal {
        GovernanceStorage storage gs = governanceStorage();
        Proposal storage proposal = gs.proposals[proposalId];
        
        uint256 totalVotes = proposal.forVotes + proposal.againstVotes;
        
        if (totalVotes >= gs.quorumThreshold) {
            if (proposal.forVotes > proposal.againstVotes) {
                proposal.status = ProposalStatus.Passed;
                // Set timelock
                if (gs.timelockDelay > 0) {
                    gs.proposalTimelocks[proposalId] = block.timestamp + gs.timelockDelay;
                }
            } else {
                proposal.status = ProposalStatus.Rejected;
            }
        }
    }

    function _getVotingPower(address voter) internal view returns (uint256) {
        GovernanceStorage storage gs = governanceStorage();
        address delegatee = gs.delegations[voter];
        address account = delegatee != address(0) ? delegatee : voter;
        
        if (gs.governanceToken != address(0)) {
            return IERC20(gs.governanceToken).balanceOf(account);
        }
        return 1; // Default: 1 vote per address
    }

    // ============ Delegation Functions ============

    function delegate(address delegatee) external override {
        GovernanceStorage storage gs = governanceStorage();
        uint256 previousBalance = _getVotingPower(msg.sender);
        
        gs.delegations[msg.sender] = delegatee;
        
        uint256 newBalance = _getVotingPower(msg.sender);
        emit DelegationChanged(msg.sender, delegatee, previousBalance, newBalance);
    }

    function delegateBySig(
        address delegator,
        address delegatee,
        uint256,
        uint256 expiry,
        uint8,
        bytes32,
        bytes32
    ) external override {
        // EIP-712 signature verification would go here
        // For now, simplified implementation
        require(block.timestamp <= expiry, "GovernanceFacet: Signature expired");
        
        GovernanceStorage storage gs = governanceStorage();
        uint256 previousBalance = _getVotingPower(delegator);
        
        gs.delegations[delegator] = delegatee;
        
        uint256 newBalance = _getVotingPower(delegator);
        emit DelegationChanged(delegator, delegatee, previousBalance, newBalance);
    }

    function delegates(address delegator) external view override returns (address) {
        GovernanceStorage storage gs = governanceStorage();
        address delegatee = gs.delegations[delegator];
        return delegatee != address(0) ? delegatee : delegator;
    }

    function getCurrentVotes(address account) external view override returns (uint256) {
        return _getVotingPower(account);
    }

    function getPriorVotes(address account, uint256) external view override returns (uint256) {
        // Simplified: return current votes (full implementation would use checkpoints)
        return _getVotingPower(account);
    }

    function _executeFacetUpgrade(bytes memory data) internal {
        (IDiamondCut.FacetCut[] memory cuts, address init, bytes memory initData) = 
            abi.decode(data, (IDiamondCut.FacetCut[], address, bytes));
        
        // Call DiamondCutFacet through Diamond
        IDiamondCut(address(this)).diamondCut(cuts, init, initData);
    }

    function _executeEmergencyPause(bytes memory data) internal {
        ISecurityFacet.PauseReason reason = abi.decode(data, (ISecurityFacet.PauseReason));
        ISecurityFacet(address(this)).pauseSystem(reason);
    }

    function _executeComplianceChange(bytes memory data) internal {
        // Compliance changes would be executed here
        // This is a placeholder for compliance-related actions
    }

    function _executeParameterChange(bytes memory data) internal {
        // Parameter changes would be executed here
        // This is a placeholder for parameter updates
    }

    function _executeTreasuryWithdrawal(bytes memory data) internal {
        (address recipient, uint256 amount, address token, ) = abi.decode(data, (address, uint256, address, string));
        
        GovernanceStorage storage gs = governanceStorage();
        require(gs.treasuryBalances[token] >= amount, "GovernanceFacet: Insufficient treasury balance");

        gs.treasuryBalances[token] -= amount;

        if (token == address(0)) {
            (bool success, ) = payable(recipient).call{value: amount}("");
            require(success, "GovernanceFacet: ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(recipient, amount);
        }
        
        // Sync treasury balance
        _syncTreasuryBalance(token);

        emit TreasuryWithdrawal(recipient, amount, token);
    }

    function _syncTreasuryBalance(address token) internal {
        GovernanceStorage storage gs = governanceStorage();
        if (token == address(0)) {
            gs.treasuryBalances[token] = address(this).balance;
        } else {
            gs.treasuryBalances[token] = IERC20(token).balanceOf(address(this));
        }
    }

    // ============ Admin Functions ============

    function setGovernanceToken(address token) external {
        LibAccessControl.requireRole(LibAccessControl.GOVERNANCE_ADMIN_ROLE, msg.sender);
        governanceStorage().governanceToken = token;
    }

    function setQuorumThreshold(uint256 threshold) external {
        LibAccessControl.requireRole(LibAccessControl.GOVERNANCE_ADMIN_ROLE, msg.sender);
        governanceStorage().quorumThreshold = threshold;
    }

    function setTimelockDelay(uint256 delay) external {
        LibAccessControl.requireRole(LibAccessControl.GOVERNANCE_ADMIN_ROLE, msg.sender);
        governanceStorage().timelockDelay = delay;
    }

    function syncTreasuryBalance(address token) external {
        _syncTreasuryBalance(token);
    }
}

