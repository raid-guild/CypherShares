/*
    Copyright 2020 Set Labs Inc.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

    SPDX-License-Identifier: Apache License, Version 2.0
*/

pragma solidity 0.7.5;
pragma experimental "ABIEncoderV2";

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IController } from "../../interfaces/IController.sol";
import { IGovernanceAdapter } from "../../interfaces/IGovernanceAdapter.sol";
import { Invoke } from "../lib/Invoke.sol";
import { ICSToken } from "../../interfaces/ICSToken.sol";
import { ModuleBase } from "../lib/ModuleBase.sol";


/**
 * @title GovernanceModule
 * @author Set Protocol
 *
 * A smart contract module that enables participating in governance of component tokens held in the CSToken.
 * Examples of intended protocols include Compound, Uniswap, and Maker governance. 
 */
contract GovernanceModule is ModuleBase, ReentrancyGuard {
    using Invoke for ICSToken;

    /* ============ Events ============ */
    event ProposalVoted(
        ICSToken indexed _csToken,
        IGovernanceAdapter indexed _governanceAdapter,
        uint256 indexed _proposalId,
        bool _support
    );

    event VoteDelegated(
        ICSToken indexed _csToken,
        IGovernanceAdapter indexed _governanceAdapter,
        address _delegatee
    );

    event ProposalCreated(
        ICSToken indexed _csToken,
        IGovernanceAdapter indexed _governanceAdapter,
        bytes _proposalData
    );

    event RegistrationSubmitted(
        ICSToken indexed _csToken,
        IGovernanceAdapter indexed _governanceAdapter
    );

    event RegistrationRevoked(
        ICSToken indexed _csToken,
        IGovernanceAdapter indexed _governanceAdapter
    );

    /* ============ Constructor ============ */

    constructor(IController _controller) public ModuleBase(_controller) {}

    /* ============ External Functions ============ */

    /**
     * SET MANAGER ONLY. Delegate voting power to an Ethereum address. Note: for some governance adapters, delegating to self is
     * equivalent to registering and delegating to zero address is revoking right to vote.
     *
     * @param _csToken                 Address of CSToken
     * @param _governanceName           Human readable name of integration (e.g. COMPOUND) stored in the IntegrationRegistry
     * @param _delegatee                Address of delegatee
     */
    function delegate(
        ICSToken _csToken,
        string memory _governanceName,
        address _delegatee
    )
        external
        nonReentrant
        onlyManagerAndValidSet(_csToken)
    {
        IGovernanceAdapter governanceAdapter = IGovernanceAdapter(getAndValidateAdapter(_governanceName));

        (
            address targetExchange,
            uint256 callValue,
            bytes memory methodData
        ) = governanceAdapter.getDelegateCalldata(_delegatee);

        _csToken.invoke(targetExchange, callValue, methodData);

        emit VoteDelegated(_csToken, governanceAdapter, _delegatee);
    }

    /**
     * SET MANAGER ONLY. Create a new proposal for a specified governance protocol.
     *
     * @param _csToken                 Address of CSToken
     * @param _governanceName           Human readable name of integration (e.g. COMPOUND) stored in the IntegrationRegistry
     * @param _proposalData             Byte data of proposal to pass into governance adapter
     */
    function propose(
        ICSToken _csToken,
        string memory _governanceName,
        bytes memory _proposalData
    )
        external
        nonReentrant
        onlyManagerAndValidSet(_csToken)
    {
        IGovernanceAdapter governanceAdapter = IGovernanceAdapter(getAndValidateAdapter(_governanceName));

        (
            address targetExchange,
            uint256 callValue,
            bytes memory methodData
        ) = governanceAdapter.getProposeCalldata(_proposalData);

        _csToken.invoke(targetExchange, callValue, methodData);

        emit ProposalCreated(_csToken, governanceAdapter, _proposalData);
    }

    /**
     * SET MANAGER ONLY. Register for voting for the CSToken
     *
     * @param _csToken                 Address of CSToken
     * @param _governanceName           Human readable name of integration (e.g. COMPOUND) stored in the IntegrationRegistry
     */
    function register(
        ICSToken _csToken,
        string memory _governanceName
    )
        external
        nonReentrant
        onlyManagerAndValidSet(_csToken)
    {
        IGovernanceAdapter governanceAdapter = IGovernanceAdapter(getAndValidateAdapter(_governanceName));

        (
            address targetExchange,
            uint256 callValue,
            bytes memory methodData
        ) = governanceAdapter.getRegisterCalldata(address(_csToken));

        _csToken.invoke(targetExchange, callValue, methodData);

        emit RegistrationSubmitted(_csToken, governanceAdapter);
    }

    /**
     * SET MANAGER ONLY. Revoke voting for the CSToken
     *
     * @param _csToken                 Address of CSToken
     * @param _governanceName           Human readable name of integration (e.g. COMPOUND) stored in the IntegrationRegistry
     */
    function revoke(
        ICSToken _csToken,
        string memory _governanceName
    )
        external
        nonReentrant
        onlyManagerAndValidSet(_csToken)
    {
        IGovernanceAdapter governanceAdapter = IGovernanceAdapter(getAndValidateAdapter(_governanceName));

        (
            address targetExchange,
            uint256 callValue,
            bytes memory methodData
        ) = governanceAdapter.getRevokeCalldata();

        _csToken.invoke(targetExchange, callValue, methodData);

        emit RegistrationRevoked(_csToken, governanceAdapter);
    }

    /**
     * SET MANAGER ONLY. Cast vote for a specific governance token held in the CSToken. Manager specifies whether to vote for or against
     * a given proposal
     *
     * @param _csToken                 Address of CSToken
     * @param _governanceName           Human readable name of integration (e.g. COMPOUND) stored in the IntegrationRegistry
     * @param _proposalId               ID of the proposal to vote on
     * @param _support                  Boolean indicating whether to support proposal
     * @param _data                     Arbitrary bytes to be used to construct vote call data
     */
    function vote(
        ICSToken _csToken,
        string memory _governanceName,
        uint256 _proposalId,
        bool _support,
        bytes memory _data
    )
        external
        nonReentrant
        onlyManagerAndValidSet(_csToken)
    {
        IGovernanceAdapter governanceAdapter = IGovernanceAdapter(getAndValidateAdapter(_governanceName));

        (
            address targetExchange,
            uint256 callValue,
            bytes memory methodData
        ) = governanceAdapter.getVoteCalldata(
            _proposalId,
            _support,
            _data
        );

        _csToken.invoke(targetExchange, callValue, methodData);

        emit ProposalVoted(_csToken, governanceAdapter, _proposalId, _support);
    }

    /**
     * Initializes this module to the CSToken. Only callable by the CSToken's manager.
     *
     * @param _csToken             Instance of the CSToken to issue
     */
    function initialize(ICSToken _csToken) external onlySetManager(_csToken, msg.sender) onlyValidAndPendingSet(_csToken) {
        _csToken.initializeModule();
    }

    /**
     * Removes this module from the CSToken, via call by the CSToken.
     */
    function removeModule() external override {}
}