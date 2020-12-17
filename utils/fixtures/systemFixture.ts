import { JsonRpcProvider, Web3Provider } from "@ethersproject/providers";
import { ContractTransaction, Signer } from "ethers";
import { BigNumber } from "@ethersproject/bignumber";

import {
    BasicIssuanceModule,
    Controller,
    IntegrationRegistry,
    OracleMock,
    PriceOracle,
    CSToken,
    CSTokenCreator,
    CSValuer,
    StandardTokenMock,
    StreamingFeeModule,
    Weth9,
    NavIssuanceModule
} from "../contracts";
import DeployHelper from "../deploys";
import {
    ether,
    ProtocolUtils,
} from "../common";
import {
    Address,
} from "../types";
import {
    MAX_UINT_256,
} from "../constants";

import { CsTokenFactory as CSTokenFactory } from "../../typechain/CsTokenFactory";

export class SystemFixture {
    private _provider: Web3Provider | JsonRpcProvider;
    private _ownerAddress: Address;
    private _ownerSigner: Signer;
    private _deployer: DeployHelper;

    public feeRecipient!: Address;

    public controller!: Controller;
    public factory!: CSTokenCreator;
    public priceOracle!: PriceOracle;
    public integrationRegistry!: IntegrationRegistry;
    public csValuer!: CSValuer;

    public issuanceModule!: BasicIssuanceModule;
    public streamingFeeModule!: StreamingFeeModule;
    public navIssuanceModule!: NavIssuanceModule;

    public weth!: Weth9;
    public usdc!: StandardTokenMock;
    public wbtc!: StandardTokenMock;
    public dai!: StandardTokenMock;

    public ETH_USD_Oracle!: OracleMock;
    public USD_USD_Oracle!: OracleMock;
    public BTC_USD_Oracle!: OracleMock;
    public DAI_USD_Oracle!: OracleMock;

    public component1Price!: BigNumber;
    public component2Price!: BigNumber;
    public component3Price!: BigNumber;
    public component4Price!: BigNumber;

    constructor(provider: Web3Provider | JsonRpcProvider, ownerAddress: Address) {
        this._provider = provider;
        this._ownerAddress = ownerAddress;
        this._ownerSigner = provider.getSigner(ownerAddress);
        this._deployer = new DeployHelper(this._ownerSigner);
    }

    public async initialize(): Promise<void> {
        // Choose an arbitrary address as fee recipient
        [, , , this.feeRecipient] = await this._provider.listAccounts();

        this.controller = await this._deployer.core.deployController(this.feeRecipient);
        this.issuanceModule = await this._deployer.modules.deployBasicIssuanceModule(this.controller.address);

        await this.initializeStandardComponents();

        this.integrationRegistry = await this._deployer.core.deployIntegrationRegistry(this.controller.address);

        this.factory = await this._deployer.core.deployCSTokenCreator(this.controller.address);
        this.priceOracle = await this._deployer.core.deployPriceOracle(
            this.controller.address,
            this.usdc.address,
            [],
            [this.weth.address, this.usdc.address, this.wbtc.address, this.dai.address],
            [this.usdc.address, this.usdc.address, this.usdc.address, this.usdc.address],
            [
                this.ETH_USD_Oracle.address,
                this.USD_USD_Oracle.address,
                this.BTC_USD_Oracle.address,
                this.DAI_USD_Oracle.address,
            ]
        );

        this.integrationRegistry = await this._deployer.core.deployIntegrationRegistry(this.controller.address);
        this.csValuer = await this._deployer.core.deployCSValuer(this.controller.address);
        this.streamingFeeModule = await this._deployer.modules.deployStreamingFeeModule(this.controller.address);
        this.navIssuanceModule = await this._deployer.modules.deployNavIssuanceModule(this.controller.address, this.weth.address);

        await this.controller.initialize(
            [this.factory.address], // Factories
            [this.issuanceModule.address, this.streamingFeeModule.address, this.navIssuanceModule.address], // Modules
            [this.integrationRegistry.address, this.priceOracle.address, this.csValuer.address], // Resources
            [0, 1, 2]  // Resource IDs where IntegrationRegistry is 0, PriceOracle is 1, CSValuer is 2
        );
    }

    public async initializeStandardComponents(): Promise<void> {
        this.weth = await this._deployer.external.deployWETH();
        this.usdc = await this._deployer.mocks.deployTokenMock(this._ownerAddress, ether(10000), 6);
        this.wbtc = await this._deployer.mocks.deployTokenMock(this._ownerAddress, ether(10000), 8);
        this.dai = await this._deployer.mocks.deployTokenMock(this._ownerAddress, ether(1000000), 18);

        this.component1Price = ether(230);
        this.component2Price = ether(1);
        this.component3Price = ether(9000);
        this.component4Price = ether(1);

        this.ETH_USD_Oracle = await this._deployer.mocks.deployOracleMock(this.component1Price);
        this.USD_USD_Oracle = await this._deployer.mocks.deployOracleMock(this.component2Price);
        this.BTC_USD_Oracle = await this._deployer.mocks.deployOracleMock(this.component3Price);
        this.DAI_USD_Oracle = await this._deployer.mocks.deployOracleMock(this.component4Price);

        await this.weth.deposit({ value: ether(5000) });
        await this.weth.approve(this.issuanceModule.address, ether(10000));
        await this.usdc.approve(this.issuanceModule.address, ether(10000));
        await this.wbtc.approve(this.issuanceModule.address, ether(10000));
        await this.dai.approve(this.issuanceModule.address, ether(10000));
    }

    public async createCSToken(
        components: Address[],
        units: BigNumber[],
        modules: Address[],
        manager: Address = this._ownerAddress,
        name: string = "CSToken",
        symbol: string = "SET",
    ): Promise<CSToken> {
        const txHash: ContractTransaction = await this.factory.create(
            components,
            units,
            modules,
            manager,
            name,
            symbol,
        );

        const retrievedSetAddress = await new ProtocolUtils(this._provider).getCreatedCSTokenAddress(txHash.hash);

        return new CSTokenFactory(this._ownerSigner).attach(retrievedSetAddress);
    }

    public async createNonControllerEnabledCSToken(
        components: Address[],
        units: BigNumber[],
        modules: Address[],
        manager: Address = this._ownerAddress,
        name: string = "CSToken",
        symbol: string = "SET",
    ): Promise<CSToken> {
        return await this._deployer.core.deployCSToken(
            components,
            units,
            modules,
            this.controller.address,
            manager,
            name,
            symbol
        );
    }

    public async approveAndIssueCSToken(
        csToken: CSToken,
        issueQuantity: BigNumber,
        to: Address = this._ownerAddress
    ): Promise<any> {
        const positions = await csToken.getPositions();
        for (let i = 0; i < positions.length; i++) {
            const { component } = positions[i];
            const componentInstance = await this._deployer.mocks.getTokenMock(component);
            await componentInstance.approve(this.issuanceModule.address, MAX_UINT_256);
        }

        await this.issuanceModule.issue(csToken.address, issueQuantity, to);
    }
}