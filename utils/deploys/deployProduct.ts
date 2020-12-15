import { Signer } from "ethers";

export default class DeployProducts { 
    private _deployerSigner: Signer;

    constructor(deployerSigner: Signer) {
        this._deployerSigner = deployerSigner;
    }
}