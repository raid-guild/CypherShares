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

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/SafeCast.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { SignedSafeMath } from "@openzeppelin/contracts/math/SignedSafeMath.sol";

import { AddressArrayUtils } from "../../lib/AddressArrayUtils.sol";
import { IController } from "../../interfaces/IController.sol";
import { INAVIssuanceHook } from "../../interfaces/INAVIssuanceHook.sol";
import { Invoke } from "../lib/Invoke.sol";
import { ICSToken } from "../../interfaces/ICSToken.sol";
import { IWETH } from "../../interfaces/external/IWETH.sol";
import { ModuleBase } from "../lib/ModuleBase.sol";
import { Position } from "../lib/Position.sol";
import { PreciseUnitMath } from "../../lib/PreciseUnitMath.sol";
import { ResourceIdentifier } from "../lib/ResourceIdentifier.sol";


/**
 * @title NavIssuanceModule
 * @author Set Protocol
 *
 * Module that enables issuance and redemption with any valid ERC20 token or ETH if allowed by the manager. Sender receives
 * a proportional amount of CSTokens on issuance or ERC20 token on redemption based on the calculated net asset value using
 * oracle prices. Manager is able to enforce a premium / discount on issuance / redemption to avoid arbitrage and front
 * running when relying on oracle prices. Managers can charge a fee (denominated in reserve asset).
 */
contract NavIssuanceModule is ModuleBase, ReentrancyGuard {
    using AddressArrayUtils for address[];
    using Invoke for ICSToken;
    using Position for ICSToken;
    using PreciseUnitMath for uint256;
    using PreciseUnitMath for int256;
    using ResourceIdentifier for IController;
    using SafeMath for uint256;
    using SafeCast for int256;
    using SafeCast for uint256;
    using SignedSafeMath for int256;

    /* ============ Events ============ */

    event CSTokenNAVIssued(
        ICSToken indexed _csToken,
        address _issuer,
        address _to,
        address _reserveAsset,
        address _hookContract,
        uint256 _csTokenQuantity,
        uint256 _managerFee,
        uint256 _premium
    );

    event CSTokenNAVRedeemed(
        ICSToken indexed _csToken,
        address _redeemer,
        address _to,
        address _reserveAsset,
        address _hookContract,
        uint256 _csTokenQuantity,
        uint256 _managerFee,
        uint256 _premium
    );

    event ReserveAssetAdded(
        ICSToken indexed _csToken,
        address _newReserveAsset
    );

    event ReserveAssetRemoved(
        ICSToken indexed _csToken,
        address _removedReserveAsset
    );

    event PremiumEdited(
        ICSToken indexed _csToken,
        uint256 _newPremium
    );

    event ManagerFeeEdited(
        ICSToken indexed _csToken,
        uint256 _newManagerFee,
        uint256 _index
    );

    event FeeRecipientEdited(
        ICSToken indexed _csToken,
        address _feeRecipient
    );

    /* ============ Structs ============ */

    struct NAVIssuanceSettings {
        INAVIssuanceHook managerIssuanceHook;      // Issuance hook configurations
        INAVIssuanceHook managerRedemptionHook;    // Redemption hook configurations
        address[] reserveAssets;                       // Allowed reserve assets - Must have a price enabled with the price oracle
        address feeRecipient;                          // Manager fee recipient
        uint256[2] managerFees;                        // Manager fees. 0 index is issue and 1 index is redeem fee (0.01% = 1e14, 1% = 1e16)
        uint256 maxManagerFee;                         // Maximum fee manager is allowed to set for issue and redeem
        uint256 premiumPercentage;                     // Premium percentage (0.01% = 1e14, 1% = 1e16). This premium is a buffer around oracle
                                                       // prices paid by user to the CSToken, which prevents arbitrage and oracle front running
        uint256 maxPremiumPercentage;                  // Maximum premium percentage manager is allowed to set (configured by manager)
        uint256 minCSTokenSupply;                     // Minimum CSToken supply required for issuance and redemption 
                                                       // to prevent dramatic inflationary changes to the CSToken's position multiplier
    }

    struct ActionInfo {
        uint256 preFeeReserveQuantity;                 // Reserve value before fees; During issuance, represents raw quantity
                                                       // During redeem, represents post-premium value
        uint256 protocolFees;                          // Total protocol fees (direct + manager revenue share)
        uint256 managerFee;                            // Total manager fee paid in reserve asset
        uint256 netFlowQuantity;                       // When issuing, quantity of reserve asset sent to CSToken
                                                       // When redeeming, quantity of reserve asset sent to redeemer
        uint256 setTokenQuantity;                      // When issuing, quantity of CSTokens minted to mintee
                                                       // When redeeming, quantity of CSToken redeemed
        uint256 previousCSTokenSupply;                // CSToken supply prior to issue/redeem action
        uint256 newCSTokenSupply;                     // CSToken supply after issue/redeem action
        int256 newPositionMultiplier;                  // CSToken position multiplier after issue/redeem
        uint256 newReservePositionUnit;                // CSToken reserve asset position unit after issue/redeem
    }

    /* ============ State Variables ============ */

    // Wrapped ETH address
    IWETH public immutable weth;

    // Mapping of CSToken to NAV issuance settings struct
    mapping(ICSToken => NAVIssuanceSettings) public navIssuanceSettings;
    
    // Mapping to efficiently check a CSToken's reserve asset validity
    // CSToken => reserveAsset => isReserveAsset
    mapping(ICSToken => mapping(address => bool)) public isReserveAsset;

    /* ============ Constants ============ */

    // 0 index stores the manager fee in managerFees array, percentage charged on issue (denominated in reserve asset)
    uint256 constant internal MANAGER_ISSUE_FEE_INDEX = 0;

    // 1 index stores the manager fee percentage in managerFees array, charged on redeem
    uint256 constant internal MANAGER_REDEEM_FEE_INDEX = 1;

    // 0 index stores the manager revenue share protocol fee % on the controller, charged in the issuance function
    uint256 constant internal PROTOCOL_ISSUE_MANAGER_REVENUE_SHARE_FEE_INDEX = 0;

    // 1 index stores the manager revenue share protocol fee % on the controller, charged in the redeem function
    uint256 constant internal PROTOCOL_REDEEM_MANAGER_REVENUE_SHARE_FEE_INDEX = 1;

    // 2 index stores the direct protocol fee % on the controller, charged in the issuance function
    uint256 constant internal PROTOCOL_ISSUE_DIRECT_FEE_INDEX = 2;

    // 3 index stores the direct protocol fee % on the controller, charged in the redeem function
    uint256 constant internal PROTOCOL_REDEEM_DIRECT_FEE_INDEX = 3;

    /* ============ Constructor ============ */

    /**
     * @param _controller               Address of controller contract
     * @param _weth                     Address of wrapped eth
     */
    constructor(IController _controller, IWETH _weth) ModuleBase(_controller) {
        weth = _weth;
    }

    /* ============ External Functions ============ */
    
    /**
     * Deposits the allowed reserve asset into the CSToken and mints the appropriate % of Net Asset Value of the CSToken
     * to the specified _to address.
     *
     * @param _csToken                     Instance of the CSToken contract
     * @param _reserveAsset                 Address of the reserve asset to issue with
     * @param _reserveAssetQuantity         Quantity of the reserve asset to issue with
     * @param _minCSTokenReceiveQuantity   Min quantity of CSToken to receive after issuance
     * @param _to                           Address to mint CSToken to
     */
    function issue(
        ICSToken _csToken,
        address _reserveAsset,
        uint256 _reserveAssetQuantity,
        uint256 _minCSTokenReceiveQuantity,
        address _to
    ) 
        external
        nonReentrant
        onlyValidAndInitializedSet(_csToken)
    {
        _validateCommon(_csToken, _reserveAsset, _reserveAssetQuantity);
        
        _callPreIssueHooks(_csToken, _reserveAsset, _reserveAssetQuantity, msg.sender, _to);

        ActionInfo memory issueInfo = _createIssuanceInfo(_csToken, _reserveAsset, _reserveAssetQuantity);

        _validateIssuanceInfo(_csToken, _minCSTokenReceiveQuantity, issueInfo);

        _transferCollateralAndHandleFees(_csToken, IERC20(_reserveAsset), issueInfo);

        _handleIssueStateUpdates(_csToken, _reserveAsset, _to, issueInfo);
    }

    /**
     * Wraps ETH and deposits WETH if allowed into the CSToken and mints the appropriate % of Net Asset Value of the CSToken
     * to the specified _to address.
     *
     * @param _csToken                     Instance of the CSToken contract
     * @param _minCSTokenReceiveQuantity   Min quantity of CSToken to receive after issuance
     * @param _to                           Address to mint CSToken to
     */
    function issueWithEther(
        ICSToken _csToken,
        uint256 _minCSTokenReceiveQuantity,
        address _to
    ) 
        external
        payable
        nonReentrant
        onlyValidAndInitializedSet(_csToken)
    {
        weth.deposit{ value: msg.value }();

        _validateCommon(_csToken, address(weth), msg.value);
        
        _callPreIssueHooks(_csToken, address(weth), msg.value, msg.sender, _to);

        ActionInfo memory issueInfo = _createIssuanceInfo(_csToken, address(weth), msg.value);

        _validateIssuanceInfo(_csToken, _minCSTokenReceiveQuantity, issueInfo);

        _transferWETHAndHandleFees(_csToken, issueInfo);

        _handleIssueStateUpdates(_csToken, address(weth), _to, issueInfo);
    }

    /**
     * Redeems a CSToken into a valid reserve asset representing the appropriate % of Net Asset Value of the CSToken
     * to the specified _to address. Only valid if there are available reserve units on the CSToken.
     *
     * @param _csToken                     Instance of the CSToken contract
     * @param _reserveAsset                 Address of the reserve asset to redeem with
     * @param _csTokenQuantity             Quantity of CSTokens to redeem
     * @param _minReserveReceiveQuantity    Min quantity of reserve asset to receive
     * @param _to                           Address to redeem reserve asset to
     */
    function redeem(
        ICSToken _csToken,
        address _reserveAsset,
        uint256 _csTokenQuantity,
        uint256 _minReserveReceiveQuantity,
        address _to
    ) 
        external
        nonReentrant
        onlyValidAndInitializedSet(_csToken)
    {
        _validateCommon(_csToken, _reserveAsset, _csTokenQuantity);

        _callPreRedeemHooks(_csToken, _csTokenQuantity, msg.sender, _to);

        ActionInfo memory redeemInfo = _createRedemptionInfo(_csToken, _reserveAsset, _csTokenQuantity);

        _validateRedemptionInfo(_csToken, _minReserveReceiveQuantity, _csTokenQuantity, redeemInfo);

        _csToken.burn(msg.sender, _csTokenQuantity);

        // Instruct the CSToken to transfer the reserve asset back to the user
        _csToken.strictInvokeTransfer(
            _reserveAsset,
            _to,
            redeemInfo.netFlowQuantity
        );

        _handleRedemptionFees(_csToken, _reserveAsset, redeemInfo);

        _handleRedeemStateUpdates(_csToken, _reserveAsset, _to, redeemInfo);
    }

    /**
     * Redeems a CSToken into Ether (if WETH is valid) representing the appropriate % of Net Asset Value of the CSToken
     * to the specified _to address. Only valid if there are available WETH units on the CSToken.
     *
     * @param _csToken                     Instance of the CSToken contract
     * @param _csTokenQuantity             Quantity of CSTokens to redeem
     * @param _minReserveReceiveQuantity    Min quantity of reserve asset to receive
     * @param _to                           Address to redeem reserve asset to
     */
    function redeemIntoEther(
        ICSToken _csToken,
        uint256 _csTokenQuantity,
        uint256 _minReserveReceiveQuantity,
        address payable _to
    ) 
        external
        nonReentrant
        onlyValidAndInitializedSet(_csToken)
    {
        _validateCommon(_csToken, address(weth), _csTokenQuantity);

        _callPreRedeemHooks(_csToken, _csTokenQuantity, msg.sender, _to);

        ActionInfo memory redeemInfo = _createRedemptionInfo(_csToken, address(weth), _csTokenQuantity);

        _validateRedemptionInfo(_csToken, _minReserveReceiveQuantity, _csTokenQuantity, redeemInfo);

        _csToken.burn(msg.sender, _csTokenQuantity);

        // Instruct the CSToken to transfer WETH from CSToken to module
        _csToken.strictInvokeTransfer(
            address(weth),
            address(this),
            redeemInfo.netFlowQuantity
        );

        weth.withdraw(redeemInfo.netFlowQuantity);
        
        _to.transfer(redeemInfo.netFlowQuantity);

        _handleRedemptionFees(_csToken, address(weth), redeemInfo);

        _handleRedeemStateUpdates(_csToken, address(weth), _to, redeemInfo);
    }

    /**
     * SET MANAGER ONLY. Add an allowed reserve asset
     *
     * @param _csToken                     Instance of the CSToken
     * @param _reserveAsset                 Address of the reserve asset to add
     */
    function addReserveAsset(ICSToken _csToken, address _reserveAsset) external onlyManagerAndValidSet(_csToken) {
        require(!isReserveAsset[_csToken][_reserveAsset], "Reserve asset already exists");
        
        navIssuanceSettings[_csToken].reserveAssets.push(_reserveAsset);
        isReserveAsset[_csToken][_reserveAsset] = true;

        emit ReserveAssetAdded(_csToken, _reserveAsset);
    }

    /**
     * SET MANAGER ONLY. Remove a reserve asset
     *
     * @param _csToken                     Instance of the CSToken
     * @param _reserveAsset                 Address of the reserve asset to remove
     */
    function removeReserveAsset(ICSToken _csToken, address _reserveAsset) external onlyManagerAndValidSet(_csToken) {
        require(isReserveAsset[_csToken][_reserveAsset], "Reserve asset does not exist");

        navIssuanceSettings[_csToken].reserveAssets = navIssuanceSettings[_csToken].reserveAssets.remove(_reserveAsset);
        delete isReserveAsset[_csToken][_reserveAsset];

        emit ReserveAssetRemoved(_csToken, _reserveAsset);
    }

    /**
     * SET MANAGER ONLY. Edit the premium percentage
     *
     * @param _csToken                     Instance of the CSToken
     * @param _premiumPercentage            Premium percentage in 10e16 (e.g. 10e16 = 1%)
     */
    function editPremium(ICSToken _csToken, uint256 _premiumPercentage) external onlyManagerAndValidSet(_csToken) {
        require(_premiumPercentage <= navIssuanceSettings[_csToken].maxPremiumPercentage, "Premium must be less than maximum allowed");
        
        navIssuanceSettings[_csToken].premiumPercentage = _premiumPercentage;

        emit PremiumEdited(_csToken, _premiumPercentage);
    }

    /**
     * SET MANAGER ONLY. Edit manager fee
     *
     * @param _csToken                     Instance of the CSToken
     * @param _managerFeePercentage         Manager fee percentage in 10e16 (e.g. 10e16 = 1%)
     * @param _managerFeeIndex              Manager fee index. 0 index is issue fee, 1 index is redeem fee
     */
    function editManagerFee(
        ICSToken _csToken,
        uint256 _managerFeePercentage,
        uint256 _managerFeeIndex
    )
        external
        onlyManagerAndValidSet(_csToken)
    {
        require(_managerFeePercentage <= navIssuanceSettings[_csToken].maxManagerFee, "Manager fee must be less than maximum allowed");
        
        navIssuanceSettings[_csToken].managerFees[_managerFeeIndex] = _managerFeePercentage;

        emit ManagerFeeEdited(_csToken, _managerFeePercentage, _managerFeeIndex);
    }

    /**
     * SET MANAGER ONLY. Edit the manager fee recipient
     *
     * @param _csToken                     Instance of the CSToken
     * @param _managerFeeRecipient          Manager fee recipient
     */
    function editFeeRecipient(ICSToken _csToken, address _managerFeeRecipient) external onlyManagerAndValidSet(_csToken) {
        require(_managerFeeRecipient != address(0), "Fee recipient must not be 0 address");
        
        navIssuanceSettings[_csToken].feeRecipient = _managerFeeRecipient;

        emit FeeRecipientEdited(_csToken, _managerFeeRecipient);
    }

    /**
     * SET MANAGER ONLY. Initializes this module to the CSToken with hooks, allowed reserve assets,
     * fees and issuance premium. Only callable by the CSToken's manager. Hook addresses are optional.
     * Address(0) means that no hook will be called.
     *
     * @param _csToken                     Instance of the CSToken to issue
     * @param _navIssuanceSettings          NAVIssuanceSettings struct defining parameters
     */
    function initialize(
        ICSToken _csToken,
        NAVIssuanceSettings memory _navIssuanceSettings
    )
        external
        onlySetManager(_csToken, msg.sender)
        onlyValidAndPendingSet(_csToken)
    {
        require(_navIssuanceSettings.reserveAssets.length > 0, "Reserve assets must be greater than 0");
        require(_navIssuanceSettings.maxManagerFee < PreciseUnitMath.preciseUnit(), "Max manager fee must be less than 100%");
        require(_navIssuanceSettings.maxPremiumPercentage < PreciseUnitMath.preciseUnit(), "Max premium percentage must be less than 100%");
        require(_navIssuanceSettings.managerFees[0] <= _navIssuanceSettings.maxManagerFee, "Manager issue fee must be less than max");
        require(_navIssuanceSettings.managerFees[1] <= _navIssuanceSettings.maxManagerFee, "Manager redeem fee must be less than max");
        require(_navIssuanceSettings.premiumPercentage <= _navIssuanceSettings.maxPremiumPercentage, "Premium must be less than max");
        require(_navIssuanceSettings.feeRecipient != address(0), "Fee Recipient must be non-zero address.");
        // Initial mint of Set cannot use NAVIssuance since minCSTokenSupply must be > 0
        require(_navIssuanceSettings.minCSTokenSupply > 0, "Min CSToken supply must be greater than 0");

        for (uint256 i = 0; i < _navIssuanceSettings.reserveAssets.length; i++) {
            require(!isReserveAsset[_csToken][_navIssuanceSettings.reserveAssets[i]], "Reserve assets must be unique");
            isReserveAsset[_csToken][_navIssuanceSettings.reserveAssets[i]] = true;
        }

        navIssuanceSettings[_csToken] = _navIssuanceSettings;

        _csToken.initializeModule();
    }

    /**
     * Removes this module from the CSToken, via call by the CSToken. Issuance settings and
     * reserve asset states are deleted.
     */
    function removeModule() external override {
        ICSToken setToken = ICSToken(msg.sender);
        for (uint256 i = 0; i < navIssuanceSettings[setToken].reserveAssets.length; i++) {
            delete isReserveAsset[setToken][navIssuanceSettings[setToken].reserveAssets[i]];
        }
        
        delete navIssuanceSettings[setToken];
    }

    receive() external payable {}

    /* ============ External Getter Functions ============ */

    function getReserveAssets(ICSToken _csToken) external view returns (address[] memory) {
        return navIssuanceSettings[_csToken].reserveAssets;
    }

    function getIssuePremium(
        ICSToken _csToken,
        address _reserveAsset,
        uint256 _reserveAssetQuantity
    )
        external
        view
        returns (uint256)
    {
        return _getIssuePremium(_csToken, _reserveAsset, _reserveAssetQuantity);
    }

    function getRedeemPremium(
        ICSToken _csToken,
        address _reserveAsset,
        uint256 _csTokenQuantity
    )
        external
        view
        returns (uint256)
    {
        return _getRedeemPremium(_csToken, _reserveAsset, _csTokenQuantity);
    }

    function getManagerFee(ICSToken _csToken, uint256 _managerFeeIndex) external view returns (uint256) {
        return navIssuanceSettings[_csToken].managerFees[_managerFeeIndex];
    }

    /**
     * Get the expected CSTokens minted to recipient on issuance
     *
     * @param _csToken                     Instance of the CSToken
     * @param _reserveAsset                 Address of the reserve asset
     * @param _reserveAssetQuantity         Quantity of the reserve asset to issue with
     *
     * @return  uint256                     Expected CSTokens to be minted to recipient
     */
    function getExpectedCSTokenIssueQuantity(
        ICSToken _csToken,
        address _reserveAsset,
        uint256 _reserveAssetQuantity
    )
        external
        view
        returns (uint256)
    {
        (,, uint256 netReserveFlow) = _getFees(
            _csToken,
            _reserveAssetQuantity,
            PROTOCOL_ISSUE_MANAGER_REVENUE_SHARE_FEE_INDEX,
            PROTOCOL_ISSUE_DIRECT_FEE_INDEX,
            MANAGER_ISSUE_FEE_INDEX
        );

        uint256 setTotalSupply = _csToken.totalSupply();

        return _getCSTokenMintQuantity(
            _csToken,
            _reserveAsset,
            netReserveFlow,
            setTotalSupply
        );
    }

    /**
     * Get the expected reserve asset to be redeemed
     *
     * @param _csToken                     Instance of the CSToken
     * @param _reserveAsset                 Address of the reserve asset
     * @param _csTokenQuantity             Quantity of CSTokens to redeem
     *
     * @return  uint256                     Expected reserve asset quantity redeemed
     */
    function getExpectedReserveRedeemQuantity(
        ICSToken _csToken,
        address _reserveAsset,
        uint256 _csTokenQuantity
    )
        external
        view
        returns (uint256)
    {
        uint256 preFeeReserveQuantity = _getRedeemReserveQuantity(_csToken, _reserveAsset, _csTokenQuantity);

        (,, uint256 netReserveFlows) = _getFees(
            _csToken,
            preFeeReserveQuantity,
            PROTOCOL_REDEEM_MANAGER_REVENUE_SHARE_FEE_INDEX,
            PROTOCOL_REDEEM_DIRECT_FEE_INDEX,
            MANAGER_REDEEM_FEE_INDEX
        );

        return netReserveFlows;
    }

    /**
     * Checks if issue is valid
     *
     * @param _csToken                     Instance of the CSToken
     * @param _reserveAsset                 Address of the reserve asset
     * @param _reserveAssetQuantity         Quantity of the reserve asset to issue with
     *
     * @return  bool                        Returns true if issue is valid
     */
    function isIssueValid(
        ICSToken _csToken,
        address _reserveAsset,
        uint256 _reserveAssetQuantity
    )
        external
        view
        returns (bool)
    {
        uint256 setTotalSupply = _csToken.totalSupply();

    return _reserveAssetQuantity != 0
            && isReserveAsset[_csToken][_reserveAsset]
            && setTotalSupply >= navIssuanceSettings[_csToken].minCSTokenSupply;
    }

    /**
     * Checks if redeem is valid
     *
     * @param _csToken                     Instance of the CSToken
     * @param _reserveAsset                 Address of the reserve asset
     * @param _csTokenQuantity             Quantity of CSTokens to redeem
     *
     * @return  bool                        Returns true if redeem is valid
     */
    function isRedeemValid(
        ICSToken _csToken,
        address _reserveAsset,
        uint256 _csTokenQuantity
    )
        external
        view
        returns (bool)
    {
        uint256 setTotalSupply = _csToken.totalSupply();

        if (
            _csTokenQuantity == 0
            || !isReserveAsset[_csToken][_reserveAsset]
            || setTotalSupply < navIssuanceSettings[_csToken].minCSTokenSupply.add(_csTokenQuantity)
        ) {
            return false;
        } else {
            uint256 totalRedeemValue =_getRedeemReserveQuantity(_csToken, _reserveAsset, _csTokenQuantity);

            (,, uint256 expectedRedeemQuantity) = _getFees(
                _csToken,
                totalRedeemValue,
                PROTOCOL_REDEEM_MANAGER_REVENUE_SHARE_FEE_INDEX,
                PROTOCOL_REDEEM_DIRECT_FEE_INDEX,
                MANAGER_REDEEM_FEE_INDEX
            );

            uint256 existingUnit = _csToken.getDefaultPositionRealUnit(_reserveAsset).toUint256();

            return existingUnit.preciseMul(setTotalSupply) >= expectedRedeemQuantity;
        }
    }

    /* ============ Internal Functions ============ */

    function _validateCommon(ICSToken _csToken, address _reserveAsset, uint256 _quantity) internal view {
        require(_quantity > 0, "Quantity must be > 0");
        require(isReserveAsset[_csToken][_reserveAsset], "Must be valid reserve asset");
    }

    function _validateIssuanceInfo(ICSToken _csToken, uint256 _minCSTokenReceiveQuantity, ActionInfo memory _issueInfo) internal view {
        // Check that total supply is greater than min supply needed for issuance
        // Note: A min supply amount is needed to avoid division by 0 when CSToken supply is 0
        require(
            _issueInfo.previousCSTokenSupply >= navIssuanceSettings[_csToken].minCSTokenSupply,
            "Supply must be greater than minimum to enable issuance"
        );

        require(_issueInfo.setTokenQuantity >= _minCSTokenReceiveQuantity, "Must be greater than min CSToken");
    }

    function _validateRedemptionInfo(
        ICSToken _csToken,
        uint256 _minReserveReceiveQuantity,
        uint256 _csTokenQuantity,
        ActionInfo memory _redeemInfo
    )
        internal
        view
    {
        // Check that new supply is more than min supply needed for redemption
        // Note: A min supply amount is needed to avoid division by 0 when redeeming CSToken to 0
        require(
            _redeemInfo.newCSTokenSupply >= navIssuanceSettings[_csToken].minCSTokenSupply,
            "Supply must be greater than minimum to enable redemption"
        );

        require(_redeemInfo.netFlowQuantity >= _minReserveReceiveQuantity, "Must be greater than min receive reserve quantity");
    }

    function _createIssuanceInfo(
        ICSToken _csToken,
        address _reserveAsset,
        uint256 _reserveAssetQuantity
    )
        internal
        view
        returns (ActionInfo memory)
    {
        ActionInfo memory issueInfo;

        issueInfo.previousCSTokenSupply = _csToken.totalSupply();

        issueInfo.preFeeReserveQuantity = _reserveAssetQuantity;

        (issueInfo.protocolFees, issueInfo.managerFee, issueInfo.netFlowQuantity) = _getFees(
            _csToken,
            issueInfo.preFeeReserveQuantity,
            PROTOCOL_ISSUE_MANAGER_REVENUE_SHARE_FEE_INDEX,
            PROTOCOL_ISSUE_DIRECT_FEE_INDEX,
            MANAGER_ISSUE_FEE_INDEX
        );

        issueInfo.setTokenQuantity = _getCSTokenMintQuantity(
            _csToken,
            _reserveAsset,
            issueInfo.netFlowQuantity,
            issueInfo.previousCSTokenSupply
        );

        (issueInfo.newCSTokenSupply, issueInfo.newPositionMultiplier) = _getIssuePositionMultiplier(_csToken, issueInfo);

        issueInfo.newReservePositionUnit = _getIssuePositionUnit(_csToken, _reserveAsset, issueInfo);

        return issueInfo;
    }

    function _createRedemptionInfo(
        ICSToken _csToken,
        address _reserveAsset,
        uint256 _csTokenQuantity
    )
        internal
        view
        returns (ActionInfo memory)
    {
        ActionInfo memory redeemInfo;

        redeemInfo.setTokenQuantity = _csTokenQuantity;

        redeemInfo.preFeeReserveQuantity =_getRedeemReserveQuantity(_csToken, _reserveAsset, _csTokenQuantity);

        (redeemInfo.protocolFees, redeemInfo.managerFee, redeemInfo.netFlowQuantity) = _getFees(
            _csToken,
            redeemInfo.preFeeReserveQuantity,
            PROTOCOL_REDEEM_MANAGER_REVENUE_SHARE_FEE_INDEX,
            PROTOCOL_REDEEM_DIRECT_FEE_INDEX,
            MANAGER_REDEEM_FEE_INDEX
        );

        redeemInfo.previousCSTokenSupply = _csToken.totalSupply();

        (redeemInfo.newCSTokenSupply, redeemInfo.newPositionMultiplier) = _getRedeemPositionMultiplier(_csToken, _csTokenQuantity, redeemInfo);

        redeemInfo.newReservePositionUnit = _getRedeemPositionUnit(_csToken, _reserveAsset, redeemInfo);

        return redeemInfo;
    }

    /**
     * Transfer reserve asset from user to CSToken and fees from user to appropriate fee recipients
     */
    function _transferCollateralAndHandleFees(ICSToken _csToken, IERC20 _reserveAsset, ActionInfo memory _issueInfo) internal {
        transferFrom(_reserveAsset, msg.sender, address(_csToken), _issueInfo.netFlowQuantity);

        if (_issueInfo.protocolFees > 0) {
            transferFrom(_reserveAsset, msg.sender, controller.feeRecipient(), _issueInfo.protocolFees);
        }

        if (_issueInfo.managerFee > 0) {
            transferFrom(_reserveAsset, msg.sender, navIssuanceSettings[_csToken].feeRecipient, _issueInfo.managerFee);
        }
    }


    /**
      * Transfer WETH from module to CSToken and fees from module to appropriate fee recipients
     */
    function _transferWETHAndHandleFees(ICSToken _csToken, ActionInfo memory _issueInfo) internal {
        weth.transfer(address(_csToken), _issueInfo.netFlowQuantity);

        if (_issueInfo.protocolFees > 0) {
            weth.transfer(controller.feeRecipient(), _issueInfo.protocolFees);
        }

        if (_issueInfo.managerFee > 0) {
            weth.transfer(navIssuanceSettings[_csToken].feeRecipient, _issueInfo.managerFee);
        }
    }

    function _handleIssueStateUpdates(
        ICSToken _csToken,
        address _reserveAsset,
        address _to,
        ActionInfo memory _issueInfo
    ) 
        internal
    {
        _csToken.editPositionMultiplier(_issueInfo.newPositionMultiplier);

        _csToken.editDefaultPosition(_reserveAsset, _issueInfo.newReservePositionUnit);

        _csToken.mint(_to, _issueInfo.setTokenQuantity);

        emit CSTokenNAVIssued(
            _csToken,
            msg.sender,
            _to,
            _reserveAsset,
            address(navIssuanceSettings[_csToken].managerIssuanceHook),
            _issueInfo.setTokenQuantity,
            _issueInfo.managerFee,
            _issueInfo.protocolFees
        );        
    }

    function _handleRedeemStateUpdates(
        ICSToken _csToken,
        address _reserveAsset,
        address _to,
        ActionInfo memory _redeemInfo
    ) 
        internal
    {
        _csToken.editPositionMultiplier(_redeemInfo.newPositionMultiplier);

        _csToken.editDefaultPosition(_reserveAsset, _redeemInfo.newReservePositionUnit);

        emit CSTokenNAVRedeemed(
            _csToken,
            msg.sender,
            _to,
            _reserveAsset,
            address(navIssuanceSettings[_csToken].managerRedemptionHook),
            _redeemInfo.setTokenQuantity,
            _redeemInfo.managerFee,
            _redeemInfo.protocolFees
        );      
    }

    function _handleRedemptionFees(ICSToken _csToken, address _reserveAsset, ActionInfo memory _redeemInfo) internal {
        // Instruct the CSToken to transfer protocol fee to fee recipient if there is a fee
        payProtocolFeeFromCSToken(_csToken, _reserveAsset, _redeemInfo.protocolFees);

        // Instruct the CSToken to transfer manager fee to manager fee recipient if there is a fee
        if (_redeemInfo.managerFee > 0) {
            _csToken.strictInvokeTransfer(
                _reserveAsset,
                navIssuanceSettings[_csToken].feeRecipient,
                _redeemInfo.managerFee
            );
        }
    }

    /**
     * Returns the issue premium percentage. Virtual function that can be overridden in future versions of the module
     * and can contain arbitrary logic to calculate the issuance premium.
     */
    function _getIssuePremium(
        ICSToken _csToken,
        address /* _reserveAsset */,
        uint256 /* _reserveAssetQuantity */
    )
        virtual
        internal
        view
        returns (uint256)
    {
        return navIssuanceSettings[_csToken].premiumPercentage;
    }

    /**
     * Returns the redeem premium percentage. Virtual function that can be overridden in future versions of the module
     * and can contain arbitrary logic to calculate the redemption premium.
     */
    function _getRedeemPremium(
        ICSToken _csToken,
        address /* _reserveAsset */,
        uint256 /* _csTokenQuantity */
    )
        virtual
        internal
        view
        returns (uint256)
    {
        return navIssuanceSettings[_csToken].premiumPercentage;
    }

    /**
     * Returns the fees attributed to the manager and the protocol. The fees are calculated as follows:
     *
     * ManagerFee = (manager fee % - % to protocol) * reserveAssetQuantity
     * Protocol Fee = (% manager fee share + direct fee %) * reserveAssetQuantity
     *
     * @param _csToken                     Instance of the CSToken
     * @param _reserveAssetQuantity         Quantity of reserve asset to calculate fees from
     * @param _protocolManagerFeeIndex      Index to pull rev share NAV Issuance fee from the Controller
     * @param _protocolDirectFeeIndex       Index to pull direct NAV issuance fee from the Controller
     * @param _managerFeeIndex              Index from NAVIssuanceSettings (0 = issue fee, 1 = redeem fee)
     *
     * @return  uint256                     Fees paid to the protocol in reserve asset
     * @return  uint256                     Fees paid to the manager in reserve asset
     * @return  uint256                     Net reserve to user net of fees
     */
    function _getFees(
        ICSToken _csToken,
        uint256 _reserveAssetQuantity,
        uint256 _protocolManagerFeeIndex,
        uint256 _protocolDirectFeeIndex,
        uint256 _managerFeeIndex
    )
        internal
        view
        returns (uint256, uint256, uint256)
    {
        (uint256 protocolFeePercentage, uint256 managerFeePercentage) = _getProtocolAndManagerFeePercentages(
            _csToken,
            _protocolManagerFeeIndex,
            _protocolDirectFeeIndex,
            _managerFeeIndex
        );

        // Calculate total notional fees
        uint256 protocolFees = protocolFeePercentage.preciseMul(_reserveAssetQuantity);
        uint256 managerFee = managerFeePercentage.preciseMul(_reserveAssetQuantity);

        uint256 netReserveFlow = _reserveAssetQuantity.sub(protocolFees).sub(managerFee);

        return (protocolFees, managerFee, netReserveFlow);
    }

    function _getProtocolAndManagerFeePercentages(
        ICSToken _csToken,
        uint256 _protocolManagerFeeIndex,
        uint256 _protocolDirectFeeIndex,
        uint256 _managerFeeIndex
    )
        internal
        view
        returns(uint256, uint256)
    {
        // Get protocol fee percentages
        uint256 protocolDirectFeePercent = controller.getModuleFee(address(this), _protocolDirectFeeIndex);
        uint256 protocolManagerShareFeePercent = controller.getModuleFee(address(this), _protocolManagerFeeIndex);
        uint256 managerFeePercent = navIssuanceSettings[_csToken].managerFees[_managerFeeIndex];
        
        // Calculate revenue share split percentage
        uint256 protocolRevenueSharePercentage = protocolManagerShareFeePercent.preciseMul(managerFeePercent);
        uint256 managerRevenueSharePercentage = managerFeePercent.sub(protocolRevenueSharePercentage);
        uint256 totalProtocolFeePercentage = protocolRevenueSharePercentage.add(protocolDirectFeePercent);

        return (managerRevenueSharePercentage, totalProtocolFeePercentage);
    }

    function _getCSTokenMintQuantity(
        ICSToken _csToken,
        address _reserveAsset,
        uint256 _netReserveFlows,            // Value of reserve asset net of fees
        uint256 _setTotalSupply
    )
        internal
        view
        returns (uint256)
    {
        uint256 premiumPercentage = _getIssuePremium(_csToken, _reserveAsset, _netReserveFlows);
        uint256 premiumValue = _netReserveFlows.preciseMul(premiumPercentage);

        // Get valuation of the CSToken with the quote asset as the reserve asset. Returns value in precise units (1e18)
        // Reverts if price is not found
        uint256 setTokenValuation = controller.getCSValuer().calculateCSTokenValuation(_csToken, _reserveAsset);

        // Get reserve asset decimals
        uint256 reserveAssetDecimals = ERC20(_reserveAsset).decimals();
        uint256 normalizedTotalReserveQuantityNetFees = _netReserveFlows.preciseDiv(10 ** reserveAssetDecimals);
        uint256 normalizedTotalReserveQuantityNetFeesAndPremium = _netReserveFlows.sub(premiumValue).preciseDiv(10 ** reserveAssetDecimals);

        // Calculate CSTokens to mint to issuer
        uint256 denominator = _setTotalSupply.preciseMul(setTokenValuation).add(normalizedTotalReserveQuantityNetFees).sub(normalizedTotalReserveQuantityNetFeesAndPremium);
        return normalizedTotalReserveQuantityNetFeesAndPremium.preciseMul(_setTotalSupply).preciseDiv(denominator);
    }

    function _getRedeemReserveQuantity(
        ICSToken _csToken,
        address _reserveAsset,
        uint256 _csTokenQuantity
    )
        internal
        view
        returns (uint256)
    {
        // Get valuation of the CSToken with the quote asset as the reserve asset. Returns value in precise units (10e18)
        // Reverts if price is not found
        uint256 setTokenValuation = controller.getCSValuer().calculateCSTokenValuation(_csToken, _reserveAsset);

        uint256 totalRedeemValueInPreciseUnits = _csTokenQuantity.preciseMul(setTokenValuation);
        // Get reserve asset decimals
        uint256 reserveAssetDecimals = ERC20(_reserveAsset).decimals();
        uint256 prePremiumReserveQuantity = totalRedeemValueInPreciseUnits.preciseMul(10 ** reserveAssetDecimals);

        uint256 premiumPercentage = _getRedeemPremium(_csToken, _reserveAsset, _csTokenQuantity);
        uint256 premiumQuantity = prePremiumReserveQuantity.preciseMulCeil(premiumPercentage);

        return prePremiumReserveQuantity.sub(premiumQuantity);
    }

    /**
     * The new position multiplier is calculated as follows:
     * inflationPercentage = (newSupply - oldSupply) / newSupply
     * newMultiplier = (1 - inflationPercentage) * positionMultiplier
     */    
    function _getIssuePositionMultiplier(
        ICSToken _csToken,
        ActionInfo memory _issueInfo
    )
        internal
        view
        returns (uint256, int256)
    {
        // Calculate inflation and new position multiplier. Note: Round inflation up in order to round position multiplier down
        uint256 newTotalSupply = _issueInfo.setTokenQuantity.add(_issueInfo.previousCSTokenSupply);
        int256 newPositionMultiplier = _csToken.positionMultiplier()
            .mul(_issueInfo.previousCSTokenSupply.toInt256())
            .div(newTotalSupply.toInt256());

        return (newTotalSupply, newPositionMultiplier);
    }

    /**
     * Calculate deflation and new position multiplier. Note: Round deflation down in order to round position multiplier down
     * 
     * The new position multiplier is calculated as follows:
     * deflationPercentage = (oldSupply - newSupply) / newSupply
     * newMultiplier = (1 + deflationPercentage) * positionMultiplier
     */ 
    function _getRedeemPositionMultiplier(
        ICSToken _csToken,
        uint256 _csTokenQuantity,
        ActionInfo memory _redeemInfo
    )
        internal
        view
        returns (uint256, int256)
    {
        uint256 newTotalSupply = _redeemInfo.previousCSTokenSupply.sub(_csTokenQuantity);
        int256 newPositionMultiplier = _csToken.positionMultiplier()
            .mul(_redeemInfo.previousCSTokenSupply.toInt256())
            .div(newTotalSupply.toInt256());

        return (newTotalSupply, newPositionMultiplier);
    }

    /**
     * The new position reserve asset unit is calculated as follows:
     * totalReserve = (oldUnit * oldCSTokenSupply) + reserveQuantity
     * newUnit = totalReserve / newCSTokenSupply
     */ 
    function _getIssuePositionUnit(
        ICSToken _csToken,
        address _reserveAsset,
        ActionInfo memory _issueInfo
    )
        internal
        view
        returns (uint256)
    {
        uint256 existingUnit = _csToken.getDefaultPositionRealUnit(_reserveAsset).toUint256();
        uint256 totalReserve = existingUnit
            .preciseMul(_issueInfo.previousCSTokenSupply)
            .add(_issueInfo.netFlowQuantity);

        return totalReserve.preciseDiv(_issueInfo.newCSTokenSupply);
    }

    /**
     * The new position reserve asset unit is calculated as follows:
     * totalReserve = (oldUnit * oldCSTokenSupply) - reserveQuantityToSendOut
     * newUnit = totalReserve / newCSTokenSupply
     */ 
    function _getRedeemPositionUnit(
        ICSToken _csToken,
        address _reserveAsset,
        ActionInfo memory _redeemInfo
    )
        internal
        view
        returns (uint256)
    {
        uint256 existingUnit = _csToken.getDefaultPositionRealUnit(_reserveAsset).toUint256();
        uint256 totalExistingUnits = existingUnit.preciseMul(_redeemInfo.previousCSTokenSupply);

        uint256 outflow = _redeemInfo.netFlowQuantity.add(_redeemInfo.protocolFees).add(_redeemInfo.managerFee);

        // Require withdrawable quantity is greater than existing collateral
        require(totalExistingUnits >= outflow, "Must be greater than total available collateral");

        return totalExistingUnits.sub(outflow).preciseDiv(_redeemInfo.newCSTokenSupply);
    }

    /**
     * If a pre-issue hook has been configured, call the external-protocol contract. Pre-issue hook logic
     * can contain arbitrary logic including validations, external function calls, etc.
     */
    function _callPreIssueHooks(
        ICSToken _csToken,
        address _reserveAsset,
        uint256 _reserveAssetQuantity,
        address _caller,
        address _to
    )
        internal
    {
        INAVIssuanceHook preIssueHook = navIssuanceSettings[_csToken].managerIssuanceHook;
        if (address(preIssueHook) != address(0)) {
            preIssueHook.invokePreIssueHook(_csToken, _reserveAsset, _reserveAssetQuantity, _caller, _to);
        }
    }

    /**
     * If a pre-redeem hook has been configured, call the external-protocol contract.
     */
    function _callPreRedeemHooks(ICSToken _csToken, uint256 _setQuantity, address _caller, address _to) internal {
        INAVIssuanceHook preRedeemHook = navIssuanceSettings[_csToken].managerRedemptionHook;
        if (address(preRedeemHook) != address(0)) {
            preRedeemHook.invokePreRedeemHook(_csToken, _setQuantity, _caller, _to);
        }
    }
}