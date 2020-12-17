import { Signer } from "ethers";

import {
    BasicIssuanceModule,
    StreamingFeeModule,
    NavIssuanceModule
} from "../contracts";
import { Address } from "../types";

import { BasicIssuanceModuleFactory } from "../../typechain/BasicIssuanceModuleFactory";
import { StreamingFeeModuleFactory } from "../../typechain/StreamingFeeModuleFactory";
import { NavIssuanceModuleFactory } from "../../typechain/NavIssuanceModuleFactory";

export default class DeployModules { 
    private _deployerSigner: Signer;

    constructor(deployerSigner: Signer) {
        this._deployerSigner = deployerSigner;
    }

    public async deployBasicIssuanceModule(controller: Address): Promise<BasicIssuanceModule> {
        return await new BasicIssuanceModuleFactory(this._deployerSigner).deploy(controller);
    }

    public async deployStreamingFeeModule(controller: Address): Promise<StreamingFeeModule> {
        return await new StreamingFeeModuleFactory(this._deployerSigner).deploy(controller);
    }

    public async deployNavIssuanceModule(controller: Address, weth: Address): Promise<NavIssuanceModule> {
        return await new NavIssuanceModuleFactory(this._deployerSigner).deploy(controller, weth);
    }
}