import { Signer } from "ethers";

import {
    Weth9
} from "./../contracts";

import { Weth9Factory } from "../../typechain/Weth9Factory";
export default class DeployExternal { 
    private _deployerSigner: Signer;

    constructor(deployerSigner: Signer) {
        this._deployerSigner = deployerSigner;
    }

    // WETH
    public async deployWETH(): Promise<Weth9> {
        return await new Weth9Factory(this._deployerSigner).deploy();
    }
}