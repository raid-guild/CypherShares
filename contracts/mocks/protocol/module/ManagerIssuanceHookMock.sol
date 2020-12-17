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

import { ICSToken } from "../../../interfaces/ICSToken.sol";

contract ManagerIssuanceHookMock {
    ICSToken public retrievedCSToken;
    uint256 public retrievedIssueQuantity;
    address public retrievedSender;
    address public retrievedTo;

    function invokePreIssueHook(ICSToken _csToken, uint256 _issueQuantity, address _sender, address _to) external {
        retrievedCSToken = _csToken;
        retrievedIssueQuantity = _issueQuantity;
        retrievedSender = _sender;    
        retrievedTo = _to;        
    }

    function invokePreRedeemHook(ICSToken _csToken, uint256 _redeemQuantity, address _sender, address _to) external {
        retrievedCSToken = _csToken;
        retrievedIssueQuantity = _redeemQuantity;
        retrievedSender = _sender;    
        retrievedTo = _to;        
    }
}