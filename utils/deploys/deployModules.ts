import { Signer } from "ethers";

export default class DeployModules { 
    private _deployerSigner: Signer;

    constructor(deployerSigner: Signer) {
        this._deployerSigner = deployerSigner;
    }
}