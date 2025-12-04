// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IProposalTemplateFacet} from "../../interfaces/IProposalTemplateFacet.sol";
import {IGovernanceFacet} from "../../interfaces/IGovernanceFacet.sol";
import {LibAccessControl} from "../../libraries/LibAccessControl.sol";

contract ProposalTemplateFacet is IProposalTemplateFacet {
    struct TemplateStorage {
        mapping(uint256 => ProposalTemplate) templates;
        uint256 templateCount;
    }

    bytes32 private constant TEMPLATE_STORAGE_POSITION = keccak256("asle.proposaltemplate.storage");

    function templateStorage() internal pure returns (TemplateStorage storage ts) {
        bytes32 position = TEMPLATE_STORAGE_POSITION;
        assembly {
            ts.slot := position
        }
    }

    modifier onlyAdmin() {
        LibAccessControl.requireRole(LibAccessControl.DEFAULT_ADMIN_ROLE, msg.sender);
        _;
    }

    function createTemplate(
        string calldata name,
        string calldata description,
        IGovernanceFacet.ProposalType proposalType,
        bytes calldata templateData
    ) external override onlyAdmin returns (uint256 templateId) {
        TemplateStorage storage ts = templateStorage();
        templateId = ts.templateCount;
        ts.templateCount++;

        ts.templates[templateId] = ProposalTemplate({
            id: templateId,
            name: name,
            description: description,
            proposalType: proposalType,
            templateData: templateData,
            active: true
        });

        emit TemplateCreated(templateId, name, proposalType);
    }

    function getTemplate(uint256 templateId) external view override returns (
        uint256 id,
        string memory name,
        string memory description,
        IGovernanceFacet.ProposalType proposalType,
        bytes memory templateData,
        bool active
    ) {
        TemplateStorage storage ts = templateStorage();
        ProposalTemplate storage template = ts.templates[templateId];
        require(template.id != 0 || templateId == 0, "ProposalTemplateFacet: Template not found");
        
        return (
            template.id,
            template.name,
            template.description,
            template.proposalType,
            template.templateData,
            template.active
        );
    }

    function setTemplateActive(uint256 templateId, bool active) external override onlyAdmin {
        TemplateStorage storage ts = templateStorage();
        require(ts.templates[templateId].id != 0 || templateId == 0, "ProposalTemplateFacet: Template not found");
        
        ts.templates[templateId].active = active;
        emit TemplateUpdated(templateId, active);
    }

    function createProposalFromTemplate(
        uint256 templateId,
        bytes calldata parameters,
        uint256 votingPeriod
    ) external override returns (uint256 proposalId) {
        TemplateStorage storage ts = templateStorage();
        ProposalTemplate storage template = ts.templates[templateId];
        require(template.id != 0 || templateId == 0, "ProposalTemplateFacet: Template not found");
        require(template.active, "ProposalTemplateFacet: Template not active");

        // Merge template data with parameters
        bytes memory proposalData = abi.encodePacked(template.templateData, parameters);

        // Call GovernanceFacet to create proposal
        IGovernanceFacet governanceFacet = IGovernanceFacet(address(this));
        proposalId = governanceFacet.createProposal(
            template.proposalType,
            template.description,
            proposalData,
            votingPeriod
        );
    }
}

