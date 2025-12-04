// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGovernanceFacet} from "./IGovernanceFacet.sol";

interface IProposalTemplateFacet {
    struct ProposalTemplate {
        uint256 id;
        string name;
        string description;
        IGovernanceFacet.ProposalType proposalType;
        bytes templateData;
        bool active;
    }

    event TemplateCreated(uint256 indexed templateId, string name, IGovernanceFacet.ProposalType proposalType);
    event TemplateUpdated(uint256 indexed templateId, bool active);

    function createTemplate(
        string calldata name,
        string calldata description,
        IGovernanceFacet.ProposalType proposalType,
        bytes calldata templateData
    ) external returns (uint256 templateId);

    function getTemplate(uint256 templateId) external view returns (
        uint256 id,
        string memory name,
        string memory description,
        IGovernanceFacet.ProposalType proposalType,
        bytes memory templateData,
        bool active
    );

    function setTemplateActive(uint256 templateId, bool active) external;

    function createProposalFromTemplate(
        uint256 templateId,
        bytes calldata parameters,
        uint256 votingPeriod
    ) external returns (uint256 proposalId);
}

