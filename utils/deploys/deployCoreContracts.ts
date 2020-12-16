import { Signer } from "ethers";
import { BigNumberish } from "@ethersproject/bignumber";

import {
    Controller,
    CSToken,
    CSTokenCreator,
} from "./../contracts";

import { Address } from "./../types";

import { ControllerFactory } from "../../typechain/ControllerFactory";
import { CsTokenFactory as CSTokenFactory } from "../../typechain/CsTokenFactory";
import { CsTokenCreatorFactory as CSTokenCreatorFactory } from "../../typechain/CsTokenCreatorFactory";

export default class DeployCoreContracts { 
    private _deployerSigner: Signer;

    constructor(deployerSigner: Signer) {
        this._deployerSigner = deployerSigner;
    }

    public async deployController(feeRecipient: Address): Promise<Controller> {
        return await new ControllerFactory(this._deployerSigner).deploy(feeRecipient);
    }

    public async deployCSToken(
        _components: Address[],
        _units: BigNumberish[],
        _modules: Address[],
        _controller: Address,
        _manager: Address,
        _name: string,
        _symbol: string,
    ): Promise<CSToken> {
        return await new CSTokenFactory(this._deployerSigner).deploy(
            _components,
            _units,
            _modules,
            _controller,
            _manager,
            _name,
            _symbol,
        );
    }

    public async deployCSTokenCreator(controller: Address): Promise<CSTokenCreator> {
        return await new CSTokenCreatorFactory(this._deployerSigner).deploy(controller);
    }
}