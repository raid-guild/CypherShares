import { Address } from "../types";
import { Signer } from "ethers";
import { BigNumberish } from "@ethersproject/bignumber";

import {
    StandardTokenMock,
    StandardTokenWithFeeMock,
    ModuleBaseMock,
    OracleMock,
    ManagerIssuanceHookMock,
    GovernanceAdapterMock
} from "../contracts";

import { StandardTokenMockFactory } from "../../typechain/StandardTokenMockFactory";
import { StandardTokenWithFeeMockFactory } from "../../typechain/StandardTokenWithFeeMockFactory";
import { ModuleBaseMockFactory } from "../../typechain/ModuleBaseMockFactory";
import { OracleMockFactory } from "../../typechain/OracleMockFactory";
import { ManagerIssuanceHookMockFactory } from "../../typechain/ManagerIssuanceHookMockFactory";
import { GovernanceAdapterMockFactory } from "../../typechain/GovernanceAdapterMockFactory";

import { ether } from "../common";

export default class DeployMocks { 
    private _deployerSigner: Signer;

    constructor(deployerSigner: Signer) {
        this._deployerSigner = deployerSigner;
    }

    public async deployManagerIssuanceHookMock(): Promise<ManagerIssuanceHookMock> {
        return await new ManagerIssuanceHookMockFactory(this._deployerSigner).deploy();
    }

    public async deployTokenMock(
        initialAccount: Address,
        initialBalance: BigNumberish = ether(1000000000),
        decimals: BigNumberish = 18,
        name: string = "Token",
        symbol: string = "Symbol"
    ): Promise<StandardTokenMock> {
        return await new StandardTokenMockFactory(this._deployerSigner)
            .deploy(initialAccount, initialBalance, name, symbol, decimals);
    }

    public async deployTokenWithFeeMock(
        initialAccount: Address,
        initialBalance: BigNumberish = ether(1000000000),
        fee: BigNumberish = ether(0.1),
        name: string = "Token",
        symbol: string = "Symbol"
    ): Promise<StandardTokenWithFeeMock> {
        return await new StandardTokenWithFeeMockFactory(this._deployerSigner)
            .deploy(initialAccount, initialBalance, name, symbol, fee);
    }

    public async deployModuleBaseMock(controllerAddress: Address): Promise<ModuleBaseMock> {
        return await new ModuleBaseMockFactory(this._deployerSigner).deploy(controllerAddress);
    }

    public async deployOracleMock(initialValue: BigNumberish): Promise<OracleMock> {
        return await new OracleMockFactory(this._deployerSigner).deploy(initialValue);
    }

    public async deployGovernanceAdapterMock(initialProposalId: BigNumberish): Promise<GovernanceAdapterMock> {
        return await new GovernanceAdapterMockFactory(this._deployerSigner).deploy(initialProposalId);
    }

    /*************************************
   * Instance getters
   ************************************/

    public async getTokenMock(token: Address): Promise<StandardTokenMock> {
        return await new StandardTokenMockFactory(this._deployerSigner).attach(token);
    }
}