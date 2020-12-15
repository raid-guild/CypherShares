import { Signer } from "ethers";

export default class DeployExternal { 
    private _deployerSigner: Signer;

    constructor(deployerSigner: Signer) {
        this._deployerSigner = deployerSigner;
    }
}