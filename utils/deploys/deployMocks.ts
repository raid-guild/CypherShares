import { Address } from "../types";
import { Signer } from "ethers";
import { BigNumberish } from "@ethersproject/bignumber";

import {
    StandardTokenMock,
    ModuleBaseMock,
} from "../contracts";

import { StandardTokenMockFactory } from "../../typechain/StandardTokenMockFactory";
import { ModuleBaseMockFactory } from "../../typechain/ModuleBaseMockFactory";

import { ether } from "../common";

export default class DeployMocks { 
    private _deployerSigner: Signer;

    constructor(deployerSigner: Signer) {
        this._deployerSigner = deployerSigner;
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

    public async deployModuleBaseMock(controllerAddress: Address): Promise<ModuleBaseMock> {
        return await new ModuleBaseMockFactory(this._deployerSigner).deploy(controllerAddress);
    }
}