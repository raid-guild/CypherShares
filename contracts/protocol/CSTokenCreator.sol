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

import { IController } from "../interfaces/IController.sol";
import { CSToken } from "./CSToken.sol";
import { AddressArrayUtils } from "../lib/AddressArrayUtils.sol";

/**
 * @title CSTokenCreator
 * @author Set Protocol
 *
 * CSTokenCreator is a smart contract used to deploy new CSToken contracts. The CSTokenCreator
 * is a Factory contract that is enabled by the controller to create and register new CSTokens.
 */
contract CSTokenCreator {
    using AddressArrayUtils for address[];

    /* ============ Events ============ */

    event CSTokenCreated(address indexed _csToken, address _manager, string _name, string _symbol);

    /* ============ State Variables ============ */

    // Instance of the controller smart contract
    IController public controller;

    /* ============ Functions ============ */

    /**
     * @param _controller          Instance of the controller
     */
    constructor(IController _controller) {
        controller = _controller;
    }

    /**
     * Creates a CSToken smart contract and registers the CSToken with the controller. The CSTokens are composed
     * of positions that are instantiated as DEFAULT (positionState = 0) state.
     *
     * @param _components             List of addresses of components for initial Positions
     * @param _units                  List of units. Each unit is the # of components per 10^18 of a CSToken
     * @param _modules                List of modules to enable. All modules must be approved by the Controller
     * @param _manager                Address of the manager
     * @param _name                   Name of the CSToken
     * @param _symbol                 Symbol of the CSToken
     * @return address                Address of the newly created CSToken
     */
    function create(
        address[] memory _components,
        int256[] memory _units,
        address[] memory _modules,
        address _manager,
        string memory _name,
        string memory _symbol
    )
        external
        returns (address)
    {
        require(_components.length > 0, "Must have at least 1 component");
        require(_components.length == _units.length, "Component and unit lengths must be the same");
        require(!_components.hasDuplicate(), "Components must not have a duplicate");
        require(_modules.length > 0, "Must have at least 1 module");
        require(_manager != address(0), "Manager must not be empty");

        for (uint256 i = 0; i < _components.length; i++) {
            require(_components[i] != address(0), "Component must not be null address");
            require(_units[i] > 0, "Units must be greater than 0");
        }

        for (uint256 j = 0; j < _modules.length; j++) {
            require(controller.isModule(_modules[j]), "Must be enabled module");
        }

        // Creates a new CSToken instance
        CSToken setToken = new CSToken(
            _components,
            _units,
            _modules,
            controller,
            _manager,
            _name,
            _symbol
        );

        // Registers Set with controller
        controller.addSet(address(setToken));

        emit CSTokenCreated(address(setToken), _manager, _name, _symbol);

        return address(setToken);
    }
}
