import { Signer } from "ethers";

export default class DeployAdapters { 
    private _deployerSigner: Signer;

    constructor(deployerSigner: Signer) {
        this._deployerSigner = deployerSigner;
    }
}