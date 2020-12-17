import { Signer } from "ethers";
import { BigNumberish } from "@ethersproject/bignumber";

import {
    Controller,
    CSToken,
    CSTokenCreator,
    CSValuer,
    IntegrationRegistry,
    PriceOracle
} from "./../contracts";

import { Address } from "./../types";

import { ControllerFactory } from "../../typechain/ControllerFactory";
import { CsTokenFactory as CSTokenFactory } from "../../typechain/CsTokenFactory";
import { CsTokenCreatorFactory as CSTokenCreatorFactory } from "../../typechain/CsTokenCreatorFactory";
import { CsValuerFactory as CSValuerFactory } from "../../typechain/CsValuerFactory";
import { IntegrationRegistryFactory } from "../../typechain/IntegrationRegistryFactory";
import { PriceOracleFactory } from "../../typechain/PriceOracleFactory";

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

    public async deployPriceOracle(
        controller: Address,
        masterQuoteAsset: Address,
        adapters: Address[],
        assetOnes: Address[],
        assetTwos: Address[],
        oracles: Address[],
    ): Promise<PriceOracle> {
        return await new PriceOracleFactory(this._deployerSigner).deploy(
            controller,
            masterQuoteAsset,
            adapters,
            assetOnes,
            assetTwos,
            oracles,
        );
    }

    public async deployIntegrationRegistry(controller: Address): Promise<IntegrationRegistry> {
        return await new IntegrationRegistryFactory(this._deployerSigner).deploy(controller);
    }

    public async deployCSValuer(controller: Address): Promise<CSValuer> {
        return await new CSValuerFactory(this._deployerSigner).deploy(controller);
    }
}