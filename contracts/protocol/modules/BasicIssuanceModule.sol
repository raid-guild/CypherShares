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

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/SafeCast.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { IController } from "../../interfaces/IController.sol";
import { IManagerIssuanceHook } from "../../interfaces/IManagerIssuanceHook.sol";
import { Invoke } from "../lib/Invoke.sol";
import { ICSToken } from "../../interfaces/ICSToken.sol";
import { ModuleBase } from "../lib/ModuleBase.sol";
import { Position } from "../lib/Position.sol";
import { PreciseUnitMath } from "../../lib/PreciseUnitMath.sol";

/**
 * @title BasicIssuanceModule
 * @author Set Protocol
 *
 * Module that enables issuance and redemption functionality on a CSToken. This is a module that is
 * required to bring the totalSupply of a Set above 0.
 */
contract BasicIssuanceModule is ModuleBase, ReentrancyGuard {
    using Invoke for ICSToken;
    using Position for ICSToken.Position;
    using Position for ICSToken;
    using PreciseUnitMath for uint256;
    using SafeMath for uint256;
    using SafeCast for int256;

    /* ============ Events ============ */

    event CSTokenIssued(
        address indexed _csToken,
        address indexed _issuer,
        address indexed _to,
        address _hookContract,
        uint256 _quantity
    );
    event CSTokenRedeemed(
        address indexed _csToken,
        address indexed _redeemer,
        address indexed _to,
        uint256 _quantity
    );

    /* ============ State Variables ============ */

    // Mapping of CSToken to Issuance hook configurations
    mapping(ICSToken => IManagerIssuanceHook) public managerIssuanceHook;

    /* ============ Constructor ============ */

    /**
     * Set state controller state variable
     *
     * @param _controller             Address of controller contract
     */
    constructor(IController _controller) ModuleBase(_controller) {}

    /* ============ External Functions ============ */

    /**
     * Deposits the CSToken's position components into the CSToken and mints the CSToken of the given quantity
     * to the specified _to address. This function only handles Default Positions (positionState = 0).
     *
     * @param _csToken             Instance of the CSToken contract
     * @param _quantity             Quantity of the CSToken to mint
     * @param _to                   Address to mint CSToken to
     */
    function issue(
        ICSToken _csToken,
        uint256 _quantity,
        address _to
    ) 
        external
        nonReentrant
        onlyValidAndInitializedSet(_csToken)
    {
        require(_quantity > 0, "Issue quantity must be > 0");

        address hookContract = _callPreIssueHooks(_csToken, _quantity, msg.sender, _to);

        (
            address[] memory components,
            uint256[] memory componentQuantities
        ) = getRequiredComponentUnitsForIssue(_csToken, _quantity);

        // For each position, transfer the required underlying to the CSToken
        for (uint256 i = 0; i < components.length; i++) {
            // Transfer the component to the CSToken
            transferFrom(
                IERC20(components[i]),
                msg.sender,
                address(_csToken),
                componentQuantities[i]
            );
        }

        // Mint the CSToken
        _csToken.mint(_to, _quantity);

        emit CSTokenIssued(address(_csToken), msg.sender, _to, hookContract, _quantity);
    }

    /**
     * Redeems the CSToken's positions and sends the components of the given
     * quantity to the caller. This function only handles Default Positions (positionState = 0).
     *
     * @param _csToken             Instance of the CSToken contract
     * @param _quantity             Quantity of the CSToken to redeem
     * @param _to                   Address to send component assets to
     */
    function redeem(
        ICSToken _csToken,
        uint256 _quantity,
        address _to
    )
        external
        nonReentrant
        onlyValidAndInitializedSet(_csToken)
    {
        require(_quantity > 0, "Redeem quantity must be > 0");

        // Burn the CSToken - ERC20's internal burn already checks that the user has enough balance
        _csToken.burn(msg.sender, _quantity);

        // For each position, invoke the CSToken to transfer the tokens to the user
        address[] memory components = _csToken.getComponents();
        for (uint256 i = 0; i < components.length; i++) {
            address component = components[i];
            require(!_csToken.hasExternalPosition(component), "Only default positions are supported");

            uint256 unit = _csToken.getDefaultPositionRealUnit(component).toUint256();

            // Use preciseMul to round down to ensure overcollateration when small redeem quantities are provided
            uint256 componentQuantity = _quantity.preciseMul(unit);

            // Instruct the CSToken to transfer the component to the user
            _csToken.strictInvokeTransfer(
                component,
                _to,
                componentQuantity
            );
        }

        emit CSTokenRedeemed(address(_csToken), msg.sender, _to, _quantity);
    }

    /**
     * Initializes this module to the CSToken with issuance-related hooks. Only callable by the CSToken's manager.
     * Hook addresses are optional. Address(0) means that no hook will be called
     *
     * @param _csToken             Instance of the CSToken to issue
     * @param _preIssueHook         Instance of the Manager Contract with the Pre-Issuance Hook function
     */
    function initialize(
        ICSToken _csToken,
        IManagerIssuanceHook _preIssueHook
    )
        external
        onlySetManager(_csToken, msg.sender)
        onlyValidAndPendingSet(_csToken)
    {
        managerIssuanceHook[_csToken] = _preIssueHook;

        _csToken.initializeModule();
    }

    /**
     * Reverts as this module should not be removable after added. Users should always
     * have a way to redeem their Sets
     */
    function removeModule() external pure override {
        revert("The BasicIssuanceModule module cannot be removed");
    }

    /* ============ External Getter Functions ============ */

    /**
     * Retrieves the addresses and units required to mint a particular quantity of CSToken.
     *
     * @param _csToken             Instance of the CSToken to issue
     * @param _quantity             Quantity of CSToken to issue
     * @return address[]            List of component addresses
     * @return uint256[]            List of component units required to issue the quantity of CSTokens
     */
    function getRequiredComponentUnitsForIssue(
        ICSToken _csToken,
        uint256 _quantity
    )
        public
        view
        onlyValidAndInitializedSet(_csToken)
        returns (address[] memory, uint256[] memory)
    {
        address[] memory components = _csToken.getComponents();

        uint256[] memory notionalUnits = new uint256[](components.length);

        for (uint256 i = 0; i < components.length; i++) {
            require(!_csToken.hasExternalPosition(components[i]), "Only default positions are supported");

            notionalUnits[i] = _csToken.getDefaultPositionRealUnit(components[i]).toUint256().preciseMulCeil(_quantity);
        }

        return (components, notionalUnits);
    }

    /* ============ Internal Functions ============ */

    /**
     * If a pre-issue hook has been configured, call the external-protocol contract. Pre-issue hook logic
     * can contain arbitrary logic including validations, external function calls, etc.
     */
    function _callPreIssueHooks(
        ICSToken _csToken,
        uint256 _quantity,
        address _caller,
        address _to
    )
        internal
        returns(address)
    {
        IManagerIssuanceHook preIssueHook = managerIssuanceHook[_csToken];
        if (address(preIssueHook) != address(0)) {
            preIssueHook.invokePreIssueHook(_csToken, _quantity, _caller, _to);
            return address(preIssueHook);
        }

        return address(0);
    }
}